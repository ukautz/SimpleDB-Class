package SimpleDB::Class::Cache::FastMmap;


=head1 NAME

SimpleDB::Class::Cache::FastMmap - MMap based cache

=head1 DESCRIPTION

Uses L<Cache::FastMMap> as underlying cache. Fast enough, persistent (optional), not shareable.

=head1 SYNOPSIS

 use SimpleDB::Class::Cache;
 
 my $cache = SimpleDB::Class::Cache->instance( FastMMap => {
     
 } );

 $cache->set($domain->name, $id, $value);

 my $value = $cache->get($domain->name, $id);
 my ($val1, $val2) = @{$cache->mget([[$domain->name, $id1], [$domain->name, $id2]])};

 $cache->delete($domain->name, $id);

 $cache->flush;

=cut

use Moose;
with qw/ SimpleDB::Class::Cache /;

use Cache::FastMmap;
use Storable;
use Clone;

has fastmmap => ( isa => 'Cache::FastMmap', is => 'ro' );

=head1 METHODS

These methods are available from this class:

=cut

#-------------------------------------------------------------------

=head2 new ( %args )

    SimpleDB::Class::Cache->instance( FastMmap => {
        share_file => '/tmp/mycache.mmap',
        expire_time => 600
    } );

=head3 %args

See L<Cache::FastMMap/new>

=cut

#-------------------------------------------------------------------

=head2 init_cache

Setup the L<Cache::Memory> instance

=cut

sub init_cache {
    my ( $self ) = @_;
    $self->{ fastmmap } = Cache::FastMmap->new( %{ $self->args }, raw_values => 1 );
}

#-------------------------------------------------------------------

sub delete {
    my ( $self, $key ) = @_;
    $self->fastmmap->remove( $key ) || 
       SimpleDB::Class::Exception::ObjectNotFound->throw(
            error   => "The cache key $key has no value.",
            id      => $key
        );
    return ;
}

#-------------------------------------------------------------------

sub flush {
    my ( $self ) = @_;
    $self->fastmmap->clear();
    return ;
}

#-------------------------------------------------------------------

sub get {
    my ( $self, $key ) = @_;
    if ( my $content = $self->fastmmap->get( $key ) ) {
        $content = Storable::thaw( $content );
        return $content if ref $content;
        SimpleDB::Class::Exception::InvalidObject->throw(
            error   => "Couldn't thaw value for $key."
        );
    }
    SimpleDB::Class::Exception::ObjectNotFound->throw(
        error   => "The cache key $key has no value.",
        id      => $key,
    );
    return ;
}

#-------------------------------------------------------------------

sub mget {
    my ( $self, $keys_ref ) = @_;
    
    my @values;
    foreach my $key ( @$keys_ref ) {
        if ( my $content = $self->fastmmap->get( $key ) ) {
            $content = Storable::thaw( $content );
            unless (ref $content) {
                SimpleDB::Class::Exception::InvalidObject->throw(
                    id      => $key,
                    error   => "Can't thaw object returned from cache for $key.",
                );
                push @values, undef;
                next;
            }
            push @values, $content;
        }
        else {
            push @values, undef;
        }
    }
    return \@values;
}

#-------------------------------------------------------------------

sub set {
    my ( $self, $key, $value, $ttl ) = @_;
    if ( $ttl && $ttl =~ /^[0-9]+$/ ) {
        $ttl = "${ttl}s";
    }
    $self->fastmmap->set( $key, Storable::nfreeze( $value ), $ttl );
    return ;
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


no Moose;
__PACKAGE__->meta->make_immutable;

