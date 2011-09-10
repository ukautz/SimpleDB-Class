use strict;
use warnings;



use ExtUtils::MakeMaker 6.31;

my %prereq = (
    'Clone' => '0.31',
    'DateTime' => '0',
    'DateTime::Format::Strptime' => '0',
    'Exception::Class' => '0',
    'JSON' => '2.16',
    'Module::Find' => '0',
    'Moose' => '0.93',
    'MooseX::ClassAttribute' => '0.16',
    'MooseX::Types' => '0.20',
    'SimpleDB::Client' => '1.0400',
    'Sub::Name' => '0.04',
    'Test::Deep' => '0',
    'Test::More' => '0',
    'UUID::Tiny' => '0'
);

# if Memcached::libmemcached is installed:
$prereq{ 'Memcached::libmemcached' } = '0.3102'
    if eval 'require "Memcached::libmemcached"; 1';

my %WriteMakefileArgs = (
    'ABSTRACT' => 'An Object Relational Mapper (ORM) for the Amazon SimpleDB service.',
    'AUTHOR' => 'JT Smith <RIZEN@cpan.org>',
    'BUILD_REQUIRES' => {},
    'CONFIGURE_REQUIRES' => {
        'ExtUtils::MakeMaker' => '6.31'
    },
    'DISTNAME' => 'SimpleDB-Class',
    'EXE_FILES' => [],
    'LICENSE' => 'perl',
    'NAME' => 'SimpleDB::Class',
    'PREREQ_PM' => \%prereq,
    'VERSION' => '1.0503_1',
    'test' => {
        'TESTS' => 't/*.t'
    }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
    my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
    my $pp = $WriteMakefileArgs{PREREQ_PM};
    for my $mod ( keys %$br ) {
        if ( exists $pp->{$mod} ) {
            $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
        }
        else {
            $pp->{$mod} = $br->{$mod};
        }
    }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
    unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



