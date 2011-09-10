package SimpleDB::Class::Cache::Dummy;


=head1 NAME

SimpleDB::Class::Cache::Dummy - Dummy cache for testing

=head1 DESCRIPTION

See L<SimpleDB::Class::Cache>

=head1 SYNOPSIS

 use SimpleDB::Class::Cache;
 
 my $cache = SimpleDB::Class::Cache->instance( Dummy => { active => 1 } );

 $cache->set($domain->name, $id, $value);

 my $value = $cache->get($domain->name, $id);
 my ($val1, $val2) = @{$cache->mget([[$domain->name, $id1], [$domain->name, $id2]])};

 $cache->delete($domain->name, $id);

 $cache->flush;

=cut

use Any::Moose;
with qw/ SimpleDB::Class::Cache /;

use version 0.74; our $VERSION = qv( "v0.1.0" );

use SimpleDB::Class::Exception;
use Params::Validate qw(:all);
Params::Validate::validation_options( on_fail => sub { 
    my $error = shift; 
    warn "Error in Cache params: ".$error; 
    SimpleDB::Class::Exception::InvalidParam->throw( error => $error );
} );

has active => ( isa => 'Bool', is => 'rw', default => 0 );
has data=> ( isa => 'HashRef', is => 'rw', default => sub {{}} );

=head1 METHODS

These methods are available from this class:

=cut

#-------------------------------------------------------------------

=head2 new

    my $cache = SimpleDB::Class::Cache->Instance( Dummy => { active => 1 } );

=cut


sub delete {
    my ( $self, $key ) = @_;
    $self->active && delete $self->data->{ $key };
    return;
}

#-------------------------------------------------------------------

sub flush {
    my ( $self ) = @_;
    $self->active && $self->data( {} );
    return;
}

#-------------------------------------------------------------------

sub get {
    my ( $self, $key ) = @_;
    return ( defined $self->data->{ $key }
        ? $self->data->{ $key }
        : undef
    ) if $self->active;
    return;
}

#-------------------------------------------------------------------

sub mget {
    my ( $self, $keys_ref ) = @_;
    return [] unless $self->active;
    return [ map {
        defined $self->data->{ $_ } ? $self->data->{ $_ } : undef
    } @$keys_ref ];
}

#-------------------------------------------------------------------

sub set {
    my ( $self, $key, $value ) = @_;
    return unless $self->active;
    $self->data->{ $key } = $value;
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


no Any::Moose;
__PACKAGE__->meta->make_immutable;

