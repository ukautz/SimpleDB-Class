package SimpleDB::Class::ItemExtendable;

use Moose;
use SimpleDB::Class::Types ':all';
use SimpleDB::Class::Item;
use MooseX::ClassAttribute;


=head1 NAME

SimpleDB::Class::Role::ItemBase - Allow roles extending attributes


=head1 METHODS

The following methods are available from this role.

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

sub add_attributes {
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
        # $class->_clear_attributes();
        # $class->attributes->{ $name } = $attributes{ $name };
    }
    
    
    
    # my %new = (%{$class->attributes}, %attributes);
    # SimpleDB::Class::Item::_install_sub($class.'::attributes', sub { return \%new; });
}

#--------------------------------------------------------

# class_has _attributes => ( is => 'rw', isa => 'HashRef', clearer => '_clear_attributes', predicate => '_has_attributes' );

sub attributes {
    my ( $self ) = @_;
    my $class = ref( $self ) || $self;
    return {
        map { ( $_ => 1 ) } grep { !/^(?:id|domain_name_fq)$/ } map { $_->name } $class->meta->get_all_attributes
    };
    # unless ( $class->_attributes ) {
    #     $class->_attributes( {
    #         map { ( $_ => 1 ) } grep { !/^(?:id|domain_name_fq)$/ } map { $_->name } $class->meta->get_all_attributes
    #     } );
    # }
    # $class->_attributes();
}



=head1 AUTHOR

=over

=item *  Plain Black Corporation (L<http://www.plainblack.com/>)

=item * Ulrich Kautz <uk@fortrabbit.de>

=back

=head1 LEGAL

SimpleDB::Class is Copyright 2009-2010 Plain Black Corporation (L<http://www.plainblack.com/>) and is licensed under the same terms as Perl itself.

=cut

no Moose;
__PACKAGE__->meta->make_immutable;

1;
