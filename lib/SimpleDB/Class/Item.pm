package SimpleDB::Class::Item;

=head1 NAME

SimpleDB::Class::Item - An object representation from an item in a SimpleDB domain.

=head1 DESCRIPTION

An object representation from an item in a SimpleDB domain.

=head1 METHODS

The following methods are available from this class.

=cut

use Moose;
use UUID::Tiny;
use SimpleDB::Class::Types ':all';
use Sub::Name ();
use Carp qw/ carp /;

# with qw/ SimpleDB::Class::Role::ItemBase /;
extends qw/ SimpleDB::Class::ItemExtendable /;

#--------------------------------------------------------
sub _install_sub {
    my ($name, $sub) = @_;
    no strict 'refs';
    *{$name} = Sub::Name::subname($name, $sub);
}

#--------------------------------------------------------

=head2 set_domain_name ( name )

Class method. Used to set the SimpleDB domain name associated with a sublcass.

=head3 name

The domain name to set.

=head2 domain_name ( )

Class method. After set_domain_name() has been called, there will be a domain_name method, that will return the value of the domain name.

=cut

sub set_domain_name {
    my ($class, $name) = @_;
    # inject domain_name sub
    _install_sub($class.'::domain_name', sub { return $name });
    # register the name and class with the schema
    my $names = SimpleDB::Class->domain_names;
    $names->{$name} = $class; 
    SimpleDB::Class->domain_names($names);
}

=head2 set_domain_pk

Set an alternative primary key, do not use the default UUID generation. Caution: You have to take care of uniqueness yourself..

    # assuming this
    __PACKAGE__->add_attributes(
        name => { isa => 'Str', is => 'rw', required => 1 },
        type => { isa => 'Str', is => 'rw', required => 1 },
    );
    
    # build unique key of name and type
    __PACKAGE__->set_domain_pk( qw/ name type / );
    
    # use a method to build pk
    __PACKAGE__->set_domain_pk( sub {
        my ( $self ) = @_;
        return map { my $s = lc( $self->$_() ); $s =~ s/[a-z0-9]//gms; $s } qw/ name type /;
    } );

=cut

sub set_domain_pk {
    my ( $class, @keys ) = @_;
    carp "Missing keys in set_domain_pk"
        unless @keys;
    
    # use method
    if ( ( ref( $keys[0] ) || '' ) eq 'CodeRef' ) {
        _install_sub( $class. '::generate_domain_pk', $keys[0] );
    }
    
    # use attributes
    else {
        _install_sub( $class. '::generate_domain_pk', sub {
            my ( $self ) = @_;
            return join( '-', map { $self->$_() } @keys );
        } );
    }
}

#--------------------------------------------------------

=head2 add_attributes ( list )

Class method. Adds more attributes to this class. B<NOTE:> This will add a method to your class which can be used as an accessor/mutator. Therefore make sure to avoid method name conflicts with this class.

=head3 list

A hashref that holds a list of attributes and their properties (a hashref itself). Example: title => { isa => 'Str', default => 'Untitled' }

=head4 attribute

The attribute name is key in the hashref.

=head4 isa

The type of data represented by this attribute. See L<SimpleDB::Class::Types> for the available types.

=head4 default

The default value for this attribute. This should be specified even if it is 'None' or 'Undefined' or 'Null', because actuall null queries are slow in SimpleDB.

=head4 trigger

A sub reference that will be called like a method (has reference to $self), and is also passed the new and old values of this attribute. Behind the scenes is a L<Moose> trigger. See also L<Moose::Manual::Attributes/"Triggers">.

=cut

sub add_attributes2 {
    my ($class, %attributes) = @_;
    my %defaults = (
        Str                 => '',
        DateTime            => sub { DateTime->now() },
        Int                 => 0,
        ArrayRefOfInt       => sub { [] },
        ArrayRefOfStr       => sub { [] },
        ArrayRefOfDateTime  => sub { [] },
        HashRef             => sub { {} },
        MediumStr           => '',
        );
    foreach my $name (keys %attributes) {
        my $type = $attributes{$name}{isa} || 'Str';
        my $isa = 'SimpleDB::Class::Types::Sdb'.$type;
        my %properties = (
            is      => 'rw',
            isa     => $isa,
            coerce  => 1,
            default => $attributes{$name}{default} || $defaults{$type},
            );
        if ($type ne 'Str') { # don't do any work we don't have to
            $properties{lazy} = 1;
        }
        if (defined $attributes{$name}{trigger}) {
            $properties{trigger} = $attributes{$name}{trigger};
        }
        $class->meta->add_attribute($name, \%properties);
    }
    my %new = (%{$class->attributes}, %attributes);
    _install_sub($class.'::attributes', sub { return \%new; });
}


#--------------------------------------------------------

=head2 has_many ( method, class, attribute )

Class method. Sets up a 1:N relationship between this class and a child class.

WARNING: With this method you need to be aware that SimpleDB is eventually consistent. See L<SimpleDB::Class/"Eventual Consistency"> for details.

=head3 method

The name of the method in this class you wish to use to access the relationship with the child class.

=head3 class

The class name of the class you're creating the child relationship with.

=head3 attribute

B<Scalar> The attribute in the child class that represents this class' id.

B<ArrayRef> Our (current class) and their (other class) attributes, eg [ "id", "super_id" ] for a ( CurrentClass.id = OtherClass.super_id) relation

=head3 options

A hash containing options that will modify the method created.

=head4 mate

The name of the attribute that will be created in C<class> to refer back to this object. If specified, a reference to this object will be set in C<class> when it is instantiated to avoid stale references.

=head4 consistent

A boolean which can enable SimpleDB's ConsistentRead option. Defaults to 0.

=head2 I<has_many_generated_method> ( [ options ] )

This is the documentation for the method generated by C<has_many>. It returns a L<SimpleDB::Class::ResultSet> object with a list of the related children to this class.

=head3 options

A hash of options to modify the result set at run time.

=head4 where

A where clause as defined by L<SimpleDB::Class::SQL>. This new clause will automatically be added to the relationship clause, so whatever you specify here is only to further limit the results returned.

=head4 order_by 

An order_by clause as defined by L<SimpleDB::Class::SQL>. By default no order is specified.

=head4 limit

A limit clause as defined by L<SimpleDB::Class::SQL>. By default all items in the relationship will be returned.

=head4 consistent

A boolean that can enable SimpleDB's ConsistentRead option. Setting this will override whatever was set in C<has_many>, if anything.

=head4 set

A hash reference of attribute names and values that will be applied to each object returned from the result set. The C<mate> option in C<has_many> can already set one of these.

=cut

sub has_many {
    my ($class, $name, $classname, $attribute, %options) = @_;
    _install_sub($class.'::'.$name, sub { 
        my ($self, %sub_options) = @_; 
        my %search_options = ref $attribute
            ? do {
                my ( $ours, $theirs ) = @$attribute;
                ( where => { $theirs => $self->$ours() } )
            }
            : ( where => { $attribute => $self->id} );
        if (exists $sub_options{where}) {
            $search_options{where}{'-and'} = $sub_options{where};
        }
        if ($sub_options{order_by}) {
            $search_options{order_by} = $sub_options{order_by};
        }
        if ($sub_options{limit}) {
            $search_options{limit} = $sub_options{limit};
        }
        if (exists $sub_options{set}) {
            $search_options{set} = $sub_options{set};
        }
        if ($options{mate}) {
            $search_options{set}{$options{mate}} = $self;
        }
        if (exists $options{consistent}) {
            $search_options{consistent} = $options{consistent};
        }
        if (exists $sub_options{consistent}) {
            $search_options{consistent} = $sub_options{consistent};
        }
        return $self->simpledb->domain($classname)->search(%search_options); 
    });
}

#--------------------------------------------------------

=head2 belongs_to ( method, class, attribute )

Class method. Adds a 1:N relationship between another class and this one.

=head3 method

The method name to create to represent this relationship in this class. 

=head3 class

The class name of the parent class you're relating this class to.

=head3 attribute

The attribute in this class' attribute list that represents the id of the parent class.

=head3 options

A hash of options to modify the created method.

=head4 mate

The name of the attribute that will be created in C<class> to refer back to this object. If specified, a reference to this object will be set in C<class> when it is instantiated to avoid stale references. This would only be useful in the case of a 1:1 relationship.

=head4 consistent

A boolean indicating whether to enable the SimpleDB's ConsistentRead option.

=head2 I<belongs_to_generated_method> ( [ item ] )

This is the documentation for the method that C<belongs_to> generates. This method caches the item it retrieves for faster future retrievals.

B<NOTE:> Will return C<undef> if the attribute specified has no value at the time it is called.

=head3 item

You can optionally precache the item that this method would produce, if you already have it by passing it to the method here. If you choose to use this option, make sure what you're setting here actually matches the id attribute that would normally be used to find the item in question.

=head2 has_I<belongs_to_generated_method>

Returns a boolean indicating whether the generated method is storing a cached result.

=head2 clear_I<belongs_to_generated_method>

Clears the cached result stored by the generated method. This method will be automatically called if a new value is set for the attribute.

=cut

sub belongs_to {
    my ($class, $name, $classname, $attribute, %options) = @_;
    my $clearer = 'clear_'.$name;
    my $predicate = 'has_'.$name;
    $class->meta->add_attribute($name, {
        is      => 'rw',
        lazy    => 1,
        default => sub {
                my $self = shift;
                my $id = $self->$attribute;
                return undef unless ($id ne '');
                my %find_options;
                if ($options{mate}) {
                    $find_options{set} = { $options{mate} => $self };
                }
                if (exists $options{consistent}) {
                    $find_options{consistent} = $options{consistent};
                }
                return $self->simpledb->domain($classname)->find($id, %find_options);
            },
        predicate => $predicate,
        clearer => $clearer,
        });
    $class->meta->add_after_method_modifier($attribute, sub {
        my ($self, $value) = @_;
        if (defined $value) {
            $self->$clearer;
        }
    });
}

#--------------------------------------------------------

=head2 has_one ( method, class, our_attrib, their_attrib )

Class method. Adds a 1:N relationship between another class and this one.

=head3 method

The method name to create to represent this relationship in this class. 

=head3 class

The class name of the parent class you're relating this class to.

=head3 our_attrib

The attribute on "our" side (current class)

=head3 our_attrib

The attribute on "their" side (the other class)

=head3 options

See L<SimpleDB::Class::Domain#search_(_options_)>

=cut

sub has_one {
    my ($class, $name, $classname, $our_attrib, $their_attrib, %options) = @_;
    my $clearer = 'clear_'.$name;
    my $predicate = 'has_'.$name;
    $class->meta->add_attribute($name, {
        is      => 'rw',
        lazy    => 1,
        default => sub {
            my $self = shift;
            my %search = (
                $their_attrib => $self->$our_attrib()
            );
            my $res = $self->simpledb->domain($classname)->search( where => \%search, %options);
            return $res->next if $res->has_result;
            return ;
        },
        predicate => $predicate,
        clearer => $clearer,
        });
    $class->meta->add_after_method_modifier($our_attrib, sub {
        my ($self, $value) = @_;
        if (defined $value) {
            $self->$clearer;
        }
    });
}


#--------------------------------------------------------

=head2 recast_using ( attribute_name ) 

Class method. Sets an attribue name to use to recast this object as another class. This allows you to pull multiple object types from the same domain. If the attribute is defined when reading the information from SimpleDB, the object will be cast as the classname returned, rather than the classname associated with the domain. The new class must be a subclass of the class associated with the domain, because you cannot C<set_domain_name> for the same domain twice, or you will break SimpleDB::Class.

=head3 attribute_name

The name of an attribute defined by C<add_attributes>. 

=cut

sub recast_using {
    my ($class, $attribute_name) = @_;
    _install_sub($class.'::_castor_attribute', sub { return $attribute_name });
}

sub _castor_attribute {
    return undef;
}

#--------------------------------------------------------

=head2 update ( attributes ) 

Update a bunch of attributes all at once. Returns a reference to L<$self> so it can be chained into other methods.

=head3 attributes

A hash reference containing attribute names and values.

=cut

sub update {
    my ($self, $attributes) = @_;
    my $registered_attributes = $self->attributes;
    foreach my $attribute (keys %{$attributes}) {
        $self->$attribute($attributes->{$attribute});
    }
    return $self;
}


#--------------------------------------------------------

=head2 new ( params )

Constructor.

=head3 params

A hash.

=head4 id

The unique identifier (ItemName) of the item represented by this class. If you don't pass this in, an item ID will be generated for you automatically.

=head4 simpledb 

Required. A L<SimpleDB::Class> object.

=cut

#--------------------------------------------------------

=head2 simpledb ( )

Returns the simpledb passed into the constructor.

=cut

has simpledb => (
    is          => 'ro',
    required    => 1,
    trigger => sub {
        my ($self, $new, $old)  = @_;

        if ($new->has_domain_prefix) {
            $self->_set_domain_name_fq($new->domain_prefix . $self->domain_name);
        }
    },
);

#--------------------------------------------------------

=head2 id ( )

Returns the unique id of this item. B<Note:> The primary key C<ItemName> (or C<id> as we call it) is a special property of an item that doesn't exist in it's own data. So if you want to search on the id, you have to use C<itemName()> in your queries as the attribute name.

=cut

has id => (
    is          => 'ro',
    isa         => SdbStr,
    builder     => 'generate_uuid',
    lazy        => 1,
);

#--------------------------------------------------------


=head2 domain_name_fq ( )

Fully qualified domain name

=cut

has domain_name_fq => (
    is          => 'ro',
    default     => undef,
    lazy        => 1,
    writer      => '_set_domain_name_fq',
);

#--------------------------------------------------------

=head2 copy ( [ id ] ) 

Creates a duplicate of this object, inserts it into the database, and returns a reference to it.

=head3 id

If you want to assign a specific id to the copy, then you can do it with this parameter.

=cut

sub copy {
    my ($self, $id) = @_;
    my %properties;
    foreach my $name (keys %{$self->attributes}) {
        $properties{$name} = $self->$name;
    }
    my %params = (simpledb => $self->simpledb);
    if (defined $id) {
        $params{id} = $id;
    }
    my $new = $self->new(\%params)->update(\%properties)->put;
    return $new;
}

#--------------------------------------------------------

=head2 delete

Removes this item from the database.

=cut

sub delete {
    my ($self) = @_;
    my $db = $self->simpledb;
    my $domain_name = $db->add_domain_prefix($self->domain_name);
    eval{$db->cache->delete($domain_name, $self->id)};
    $db->http->send_request('DeleteAttributes', {ItemName => $self->id, DomainName=>$domain_name});
}

#--------------------------------------------------------

=head2 delete_attribute

Removes a specific attribute from this item in the database. Great in conjunction with add_attribute().

=cut

sub delete_attribute {
    my ($self, $name) = @_;
    my $attributes = $self->attributes;
    delete $attributes->{$name};
    $self->attributes($attributes);
    my $db = $self->simpledb;
    my $domain_name = $db->add_domain_prefix($self->domain_name);
    eval{$db->cache->set($domain_name, $self->id, $attributes)};
    $db->http->send_request('DeleteAttributes', { ItemName => $self->id, DomainName => $domain_name, 'Attribute.0.Name' => $name } );
}

#--------------------------------------------------------

=head2 generate_uuid ( )

Class method. Generates a unique UUID that can be used as a unique id for new items.

If you set an alternative primary key via set_domain_pk, it will use this.

=cut 

sub generate_uuid {
    my ( $self ) = @_;
    return $self->can( 'generate_domain_pk' )
        ? $self->generate_domain_pk()
        : create_UUID_as_string(UUID_V4);
}

#--------------------------------------------------------

=head2 put ( )

Inserts/updates the current attributes of this Item object to the database.  Returns a reference to L<$self> so it can be chained into other methods.

=cut

sub put {
    my ($self) = @_;
    my $db = $self->simpledb;
    my $domain_name = $db->add_domain_prefix($self->domain_name);
    my $i = 0;
    my $attributes = $self->to_hashref;

    # build the parameter list
    my $params = {ItemName => $self->id, DomainName=>$domain_name};
    foreach my $name (keys %{$attributes}) {                                                
        my $values = $self->stringify_values($name, $self->$name);
        unless (ref $values eq 'ARRAY') {
            $values = [$values];
        }
        foreach my $value (@{$values}) {
            $params->{'Attribute.'.$i.'.Name'} = $name;
            $params->{'Attribute.'.$i.'.Value'} = $value;
            $params->{'Attribute.'.$i.'.Replace'} = 'true';
            $i++;
        }
    }

    # push changes
    eval{$db->cache->set($domain_name, $self->id, $attributes)};
    $db->http->send_request('PutAttributes', $params);
    return $self;
}

#--------------------------------------------------------

=head2 to_hashref ( )

Returns a hash reference of the attributes asscoiated with this item.

=cut

sub to_hashref {
    my ($self) = @_;
    my %properties;
    foreach my $attribute (keys %{$self->attributes}) {                                                
        next if $attribute eq 'id';
        $properties{$attribute} = $self->$attribute;
    }
    return \%properties;
}

#--------------------------------------------------------

=head2 parse_value ( name, value ) 

Class method. Returns the proper type for an attribute value in this class. So it could take a date string and turn it into a L<DateTime> object. See C<stringify_value> for the opposite.

=head3 name

The name of the attribute to parse.

=head3 value

The current stringified value to parse.

=cut

sub parse_value {
    my ($class, $name, $value) = @_;
    return $name if ($name eq 'itemName()');

    # find type
    my $attribute = $class->meta->find_attribute_by_name($name);
    SimpleDB::Class::Exception::InvalidParam->throw(
        name    => 'name',
        value   => $name,
        error   => q{There is no attribute called '}.$name.q{'.},
        ) unless defined $attribute;
    my $isa = $attribute->type_constraint;

    # coerce
    $isa->coerce($value);
}

#--------------------------------------------------------

=head2 stringify_value ( name, value )

Class method. Formats an attribute as a string using one of the L<SimpleDB::Class::Types> to_* functions in this class. See C<parse_value>, as this is the reverse of that.

=head3 name

The name of the attribute to format.

=head3 value

The value to format.

=cut

sub stringify_value {
    my ($class, $name, $value) = @_;
    return $value if ($name eq 'itemName()');

    # find type
    my $attribute = $class->meta->find_attribute_by_name($name);
    SimpleDB::Class::Exception::InvalidParam->throw(
        name    => 'name',
        value   => $name,
        error   => q{There is no attribute called '}.$name.q{'.},
        ) unless defined $attribute;
    my $isa = $attribute->type_constraint;

    # coerce
    # special cases for int stuff because technically ints are already strings
    if ($isa =~ /Int$/) {
        return to_SdbIntAsStr($value); 
    }
    elsif ($isa =~ /Decimal$/) {
        return to_SdbDecimalAsStr($value);
    }
    else {
        return to_SdbStr($value);
    }
}

#--------------------------------------------------------

=head2 stringify_values ( name, values )

Class method. Same as C<stringify_value>, but takes into account array types in addition to scalars.

=head3 name

The name of the attribute to format.

=head3 values

The value to format.

=cut

sub stringify_values {
    my ($class, $name, $value) = @_;
    return $name if ($name eq 'itemName()');

    # find type
    my $attribute = $class->meta->find_attribute_by_name($name);
    SimpleDB::Class::Exception::InvalidParam->throw(
        name    => 'name',
        value   => $name,
        error   => q{There is no attribute called '}.$name.q{'.},
        ) unless defined $attribute;
    my $isa = $attribute->type_constraint || '';

    # coerce
    # special cases for int stuff because technically ints are already strings
    if ($isa eq 'SimpleDB::Class::Types::SdbArrayRefOfInt') {
        return to_SdbArrayRefOfIntAsStr($value);
    }
    elsif ($isa eq 'SimpleDB::Class::Types::SdbInt') {
        return to_SdbIntAsStr($value); 
    }
    if ($isa eq 'SimpleDB::Class::Types::SdbArrayRefOfDecimal') {
        return to_SdbArrayRefOfDecimalAsStr($value);
    }
    elsif ($isa eq 'SimpleDB::Class::Types::SdbDecimal') {
        return to_SdbDecimalAsStr($value);
    }
    elsif ($isa =~ m/ArrayRefOf|HashRef|MediumStr/) {
        return to_SdbArrayRefOfStr($value);
    }
    else {
        return to_SdbStr($value);
    }
}

=head1 LEGAL

SimpleDB::Class is Copyright 2009-2010 Plain Black Corporation (L<http://www.plainblack.com/>) and is licensed under the same terms as Perl itself.

=cut

1;
