package SimpleDB::Class::Cache;


=head1 NAME

SimpleDB::Class::Cache - Memcached interface for SimpleDB.

=head1 DESCRIPTION

An API that allows you to cache item data to a memcached server. Technically I should be storing the item itself, but since the item has a reference to the domain, and the domain has a reference to the simpledb object, it could cause all sorts of problems, so it's just safer to store just the item's data.

=head1 SYNOPSIS

 use SimpleDB::Class::Cache;
 
 my $cache = SimpleDB::Class::Cache->new( type => $cache_type, args => $cache_args );

 $cache->set($domain->name, $id, $value);

 my $value = $cache->get($domain->name, $id);
 my ($val1, $val2) = @{$cache->mget([[$domain->name, $id1], [$domain->name, $id2]])};

 $cache->delete($domain->name, $id);

 $cache->flush;

=cut

use Moose::Role;
use SimpleDB::Class::Exception;
use Memcached::libmemcached;
use Storable ();
use Params::Validate qw(:all);
Params::Validate::validation_options( on_fail => sub { 
        my $error = shift; 
        warn "Error in Cache params: ".$error; 
        SimpleDB::Class::Exception::InvalidParam->throw( error => $error );
        } );
use Scalar::Util qw/ blessed /;

requires qw/ get mget set delete flush /;

has type => ( isa => 'Str', is => 'ro', required => 1 );
has args => ( isa => 'HashRef', is => 'ro', default => sub {{ }} );

=head1 METHODS

These methods are available from this class:

=cut

# providing default BUILD constructor and running possible init_cache() method 
# to allow the cache to setup itself after creation

sub BUILD {}
after BUILD => sub {
    my ( $self ) = @_;
    $self->init_cache() if $self->can( 'init_cache' );
};

#-------------------------------------------------------------------

=head2 new ( type, args ) 

Constructor.

=head3 type

The name of the cache-module to use, eg "Memcached" for L<SimpleDB::Class::Cache::Memcached>.

=head3 args

The arguments to pass to the constructor of the cache-module.

=cut

sub instance($$$) {
    my ( $class, $type, $args_ref ) = @_;
    die "Usage: my \$cache = SimpleDB::Class::Cache->instance( \$type => \$args_ref );"
        unless $type && $class eq 'SimpleDB::Class::Cache';
    my $cache = $class. '::'. $type;
    eval "use $cache; 1;"
        or die "Could not load $cache: $@";
    $args_ref ||= {};
    return $cache->new( %$args_ref, type => $type, args => $args_ref );
}

#-------------------------------------------------------------------


#-------------------------------------------------------------------

=head2 fix_key ( domain,  id )

Returns a key after it's been processed for completeness. Merges a domain name and a key name with a colon. Keys cannot have any spaces in them, and this fixes that. However, it means that "foo bar" and "foo_bar" are the same thing.

=head3 domain

They domain name to process.

=head3 id

They id name to process.

=cut

sub fix_key {
    my ($self, $domain, $id) = @_;
    my $key = $domain.":".$id;
    $key =~ s/\s+/_/g;
    return $key;
}

#-------------------------------------------------------------------

=head2 delete ( domain, id )

Delete a key from the cache.

Throws SimpleDB::Class::Exception::InvalidParam, SimpleDB::Class::Exception::Connection and SimpleDB::Class::Exception.

=head3 domain

The domain name to delete from.

=head3 id

The key to delete.

=cut

around delete => sub {
    my ( $next, $self, @args ) = @_;
    my ($domain, $id, $retry) = validate_pos( @args, { type => SCALAR }, { type => SCALAR }, { optional => 1 } );
    my $key = $self->fix_key( $domain, $id );
    return $self->$next( $key, $retry );
};

#-------------------------------------------------------------------

=head2 flush ( )

Empties the caching system.

Throws SimpleDB::Class::Exception::Connection and SimpleDB::Class::Exception.

=cut

around flush => sub {
    my ( $next, $self ) = @_;
    return $self->$next();
};


#-------------------------------------------------------------------

=head2 get ( domain, id )

Retrieves a key value from the cache.

Throws SimpleDB::Class::Exception::InvalidObject, SimpleDB::Class::Exception::InvalidParam, SimpleDB::Class::Exception::ObjectNotFound, SimpleDB::Class::Exception::Connection and SimpleDB::Class::Exception.

=head3 domain

The domain name to retrieve from.

=head3 id

The key to retrieve.

=cut

around get => sub {
    my ( $next, $self, @args ) = @_;
    my( $domain, $id, $retry ) = validate_pos( @args, { type => SCALAR }, { type => SCALAR }, { optional => 1 } );
    my $key = $self->fix_key($domain, $id);
    return $self->$next( $key, $retry );
};


#-------------------------------------------------------------------

=head2 mget ( keys )

Retrieves multiple values from cache at once, which is much faster than retrieving one at a time. Returns an array reference containing the values in the order they were requested.

Throws SimpleDB::Class::Exception::InvalidParam, SimpleDB::Class::Exception::Connection and SimpleDB::Class::Exception.

=head3 keys

An array reference of domain names and ids to retrieve.

=cut

around mget => sub {
    my ( $next, $self, @args ) = @_;
    my ( $names, $retry ) = validate_pos( @args, { type => ARRAYREF }, { optional => 1 } );
    my @keys = map { $self->fix_key( @{$_} ) } @{ $names };
    return $self->$next( \@keys, $retry );
};


#-------------------------------------------------------------------

=head2 set ( domain, id, value [, ttl] )

Sets a key value to the cache.

Throws SimpleDB::Class::Exception::InvalidParam, SimpleDB::Class::Exception::Connection, and SimpleDB::Class::Exception.

=head3 domain

The name of the domain to set the info into.

=head3 id

The name of the key to set.

=head3 value

A hash reference to store.

=head3 ttl

A time in seconds for the cache to exist. Default is 3600 seconds (1 hour).

=cut

around set => sub {
    my ( $next, $self, @args ) = @_;
    my ( $key, $domain, $id, $value, $ttl, $retry ) = ref( $args[0] )
        ? do {
            ( $args[0], undef, undef, $args[2], $args[3] );
        }
        : ( undef, validate_pos( @args,
            { type => SCALAR }, { type => SCALAR }, { type => HASHREF }, { type => SCALAR | UNDEF, optional => 1 }, { optional => 1 } ) );
    $key //= $self->fix_key( $domain, $id );
    return $self->$next( $key, $value, $ttl, $retry );
};



=head1 EXCEPTIONS

This class throws a lot of inconvenient, but useful exceptions. If you just want to avoid them you could:

 my $value = eval { $cache->get($key) };
 if (SimpleDB::Class::Exception::ObjectNotFound->caught) {
    $value = $db->fetchValueFromTheDatabase;
 }

The exceptions that can be thrown are:

=head2 SimpleDB::Class::Exception

When an uknown exception happens, or there are no configured memcahed servers in the cacheServers directive in your config file.

=head2 SimpleDB::Class::Exception::Connection

When it can't connect to the memcached servers that are configured.

=head2 SimpleDB::Class::Exception::InvalidParam

When you pass in the wrong arguments.

=head2 SimpleDB::Class::Exception::ObjectNotFound

When you request a cache key that doesn't exist on any configured memcached server.

=head2 SimpleDB::Class::Exception::InvalidObject

When an object can't be thawed from cache due to corruption of some sort.

=head1 LEGAL

SimpleDB::Class is Copyright 2009-2010 Plain Black Corporation (L<http://www.plainblack.com/>) and is licensed under the same terms as Perl itself.

=cut


# no Moose;
# __PACKAGE__->meta->make_immutable;

1;