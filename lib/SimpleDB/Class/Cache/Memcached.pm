package SimpleDB::Class::Cache::Memcached;


=head1 NAME

SimpleDB::Class::Cache::Memcached - Memcached interface for SimpleDB.

=head1 DESCRIPTION

An API that allows you to cache item data to a memcached server. Technically I should be storing the item itself, but since the item has a reference to the domain, and the domain has a reference to the simpledb object, it could cause all sorts of problems, so it's just safer to store just the item's data.

=head1 SYNOPSIS

 use SimpleDB::Class::Cache;
 
 my $cache = SimpleDB::Class::Cache->new( type => 'Memcached', args => { servers=>[{host=>'127.0.0.1', port=>11211}] } );

 $cache->set($domain->name, $id, $value);

 my $value = $cache->get($domain->name, $id);
 my ($val1, $val2) = @{$cache->mget([[$domain->name, $id1], [$domain->name, $id2]])};

 $cache->delete($domain->name, $id);

 $cache->flush;

=cut

use Any::Moose;
with qw/ SimpleDB::Class::Cache /;

use SimpleDB::Class::Exception;
use Memcached::libmemcached;
use Storable ();
use Params::Validate qw(:all);
Params::Validate::validation_options( on_fail => sub { 
        my $error = shift; 
        warn "Error in Cache params: ".$error; 
        SimpleDB::Class::Exception::InvalidParam->throw( error => $error );
        } );



=head1 METHODS

These methods are available from this class:

=cut

#-------------------------------------------------------------------

=head2 new ( params ) 

Constructor.

=head3 params

A hash containing configuration params to connect to memcached.

=head4 servers

An array reference of servers (sockets and/or hosts). It should look similar to:

 [
    { host => '127.0.0.1', port=> '11211' },
    { socket  => '/path/to/unix/socket' },
 ]

=cut

#-------------------------------------------------------------------

=head2 init_cache

Setup the L<Cache::Memory> instance

=cut

sub init_cache {
    my ( $self ) = @_;
    
    my $memcached = Memcached::libmemcached::memcached_create();
    foreach my $server (@{$self->servers}) {
        if (exists $server->{socket}) {
            Memcached::libmemcached::memcached_server_add_unix_socket($memcached, $server->{socket}); 
        }
        else {
            Memcached::libmemcached::memcached_server_add($memcached, $server->{host}, $server->{port});
        }
    }
    $self->{ memcached } = $memcached;
}

#-------------------------------------------------------------------

=head2 servers ( )

Returns the array reference of servers passed into the constructor.

=cut

has 'servers' => (
    is       => 'ro',
    required => 1,
);

#-------------------------------------------------------------------

=head2 memcached ( )

Returns a L<Memcached::libmemcached> object, which is constructed using the information passed into the constructor.

=cut

has 'memcached' => (
    is      => 'ro',
    clearer => 'clear_memcached',
);


#-------------------------------------------------------------------

=head2 delete ( domain, id )

Delete a key from the cache.

Throws SimpleDB::Class::Exception::InvalidParam, SimpleDB::Class::Exception::Connection and SimpleDB::Class::Exception.

=head3 domain

The domain name to delete from.

=head3 id

The key to delete.

=cut

sub delete {
    my ( $self, $key, $retry ) = @_;
    my $memcached = $self->memcached;
    Memcached::libmemcached::memcached_delete($memcached, $key);
    if ($memcached->errstr eq 'SYSTEM ERROR Unknown error: 0') {
        SimpleDB::Class::Exception::Connection->throw(
            error   => "Cannot connect to memcached server."
            );
    }
    elsif ($memcached->errstr eq 'UNKNOWN READ FAILURE' ) {
        if ($retry) {
            SimpleDB::Class::Exception::Connection->throw(
                error   => "Cannot connect to memcached server."
            );
        }
        else {
            warn "Memcached went away, reconnecting.";
            $self->clear_memcached;
            $self->delete( \$key, undef, 1);
        }
    }
    elsif ($memcached->errstr eq 'NOT FOUND' ) {
       SimpleDB::Class::Exception::ObjectNotFound->throw(
            error   => "The cache key $key has no value.",
            id      => $key,
            );
    }
    elsif ($memcached->errstr eq 'NO SERVERS DEFINED') {
       SimpleDB::Class::Exception->throw(
            error   => "No memcached servers specified."
            );
    }
    elsif ($memcached->errstr ne 'SUCCESS' # deleted
        && $memcached->errstr ne 'PROTOCOL ERROR' # doesn't exist to delete
        ) {
        SimpleDB::Class::Exception->throw(
            error   => "Couldn't delete $key from cache because ".$memcached->errstr
            );
    }
}

#-------------------------------------------------------------------

=head2 flush ( )

Empties the caching system.

Throws SimpleDB::Class::Exception::Connection and SimpleDB::Class::Exception.

=cut

sub flush {
    my ($self, $retry) = @_;
    my $memcached = $self->memcached;
    Memcached::libmemcached::memcached_flush($memcached);
    if ($memcached->errstr eq 'SYSTEM ERROR Unknown error: 0') {
        SimpleDB::Class::Exception::Connection->throw(
            error   => "Cannot connect to memcached server."
        );
    }
    elsif ($memcached->errstr eq 'UNKNOWN READ FAILURE' ) {
        SimpleDB::Class::Exception::Connection->throw(
            error   => "Cannot connect to memcached server."
        ) if $retry;

        warn "Memcached went away, reconnecting.";
        $self->clear_memcached;
        return $self->flush(1);
    }
    elsif ($memcached->errstr eq 'NO SERVERS DEFINED') {
        SimpleDB::Class::Exception->throw(
            error   => "No memcached servers specified."
        );
    }
    elsif ($memcached->errstr ne 'SUCCESS') {
        SimpleDB::Class::Exception->throw(
            error   => "Couldn't flush cache because ".$memcached->errstr
        );
    }
}

#-------------------------------------------------------------------

=head2 get ( domain, id )

Retrieves a key value from the cache.

Throws SimpleDB::Class::Exception::InvalidObject, SimpleDB::Class::Exception::InvalidParam, SimpleDB::Class::Exception::ObjectNotFound, SimpleDB::Class::Exception::Connection and SimpleDB::Class::Exception.

=head3 domain

The domain name to retrieve from.

=head3 id

The key to retrieve.

=cut

sub get {
    my ( $self, $key, $retry ) = @_;
    my $memcached = $self->memcached;
    my $content = Memcached::libmemcached::memcached_get($memcached, $key);
    $content = Storable::thaw($content);
    if ($memcached->errstr eq 'SUCCESS') {
        if (ref $content) {
            return $content;
        }
        else {
            SimpleDB::Class::Exception::InvalidObject->throw(
                error   => "Couldn't thaw value for $key."
                );
        }
    }
    elsif ($memcached->errstr eq 'NOT FOUND' ) {
        SimpleDB::Class::Exception::ObjectNotFound->throw(
            error   => "The cache key $key has no value.",
            id      => $key,
            );
    }
    elsif ($memcached->errstr eq 'NO SERVERS DEFINED') {
        SimpleDB::Class::Exception->throw(
            error   => "No memcached servers specified."
            );
    }
    elsif ($memcached->errstr eq 'SYSTEM ERROR Unknown error: 0' || $retry) {
        SimpleDB::Class::Exception::Connection->throw(
            error   => "Cannot connect to memcached server."
            );
    }
    elsif ($memcached->errstr eq 'UNKNOWN READ FAILURE' ) {
        warn "Memcached went away, reconnecting.";
        $self->clear_memcached;
        return $self->get( \$key, undef, 1);
    }
    SimpleDB::Class::Exception->throw(
        error   => "Couldn't get $key from cache because ".$memcached->errstr
    );
}

#-------------------------------------------------------------------

=head2 mget ( keys )

Retrieves multiple values from cache at once, which is much faster than retrieving one at a time. Returns an array reference containing the values in the order they were requested.

Throws SimpleDB::Class::Exception::InvalidParam, SimpleDB::Class::Exception::Connection and SimpleDB::Class::Exception.

=head3 keys

An array reference of domain names and ids to retrieve.

=cut

sub mget {
    my ( $self, $keys_ref, $retry ) = @_;
    my %result;
    my $memcached = $self->memcached;
    $memcached->mget_into_hashref( $keys_ref, \%result );
    if ($memcached->errstr eq 'SYSTEM ERROR Unknown error: 0') {
        SimpleDB::Class::Exception::Connection->throw(
            error   => "Cannot connect to memcached server."
            );
    }
    elsif ($memcached->errstr eq 'UNKNOWN READ FAILURE' ) {
        SimpleDB::Class::Exception::Connection->throw(
            error   => "Cannot connect to memcached server."
            ) if $retry;
        warn "Memcached went away, reconnecting.";
        $self->clear_memcached;
        return $self->get( \$keys_ref, 1);
    }
    elsif ($memcached->errstr eq 'NO SERVERS DEFINED') {
        SimpleDB::Class::Exception->throw(
            error   => "No memcached servers specified."
            );
    }
    # no other useful status messages are returned
    my @values;
    foreach my $key ( @$keys_ref ) {
        my $content = Storable::thaw($result{$key});
        unless (ref $content) {
            SimpleDB::Class::Exception::InvalidObject->throw(
                id      => $key,
                error   => "Can't thaw object returned from memcache for $key.",
                );
            next;
        }
        push @values, $content;
    }
    return \@values;
}

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

sub set {
    my ( $self, $key, $value, $ttl, $retry ) = @_;
    $ttl ||= 60;
    my $frozenValue = Storable::nfreeze($value); 
    my $memcached = $self->memcached;
    Memcached::libmemcached::memcached_set($memcached, $key, $frozenValue, $ttl);
    if ($memcached->errstr eq 'SUCCESS') {
        return $value;
    }
    elsif ($memcached->errstr eq 'SYSTEM ERROR Unknown error: 0' || $retry) {
        SimpleDB::Class::Exception::Connection->throw(
            error   => "Cannot connect to memcached server."
            );
    }
    elsif ($memcached->errstr eq 'UNKNOWN READ FAILURE' ) {
        warn "Memcached went away, reconnecting.";
        $self->clear_memcached;
        return $self->set( \$key, undef, $value, $ttl, 1);
    }
    elsif ($memcached->errstr eq 'NO SERVERS DEFINED') {
        SimpleDB::Class::Exception->throw(
            error   => "No memcached servers specified."
            );
    }
    SimpleDB::Class::Exception->throw(
        error   => "Couldn't set $key to cache because ".$memcached->errstr
        );
    return $value;
}


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


no Any::Moose;
__PACKAGE__->meta->make_immutable;

