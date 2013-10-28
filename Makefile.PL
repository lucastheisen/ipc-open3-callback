use strict;
use warnings;
use ExtUtils::MakeMaker 6.30;

my %WriteMakefileArgs = (
    ABSTRACT =>
'An extension to IPC::Open3 that will feed out and err to callbacks instead of requiring the caller to handle them.',
    AUTHOR             => 'Lucas Theisen <lucastheisen@pastdev.com>',
    BUILD_REQUIRES     => {},
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 6.30
    },
    DISTNAME      => 'IPC-Open3-Callback',
    EXE_FILES     => [],
    LICENSE       => 'perl',
    NAME          => 'IPC::Open3::Callback',
    PREREQ_PM     => {},
    TEST_REQUIRES => { 'Test::Most' => 0.31 },
	VERSION_FROM => 'lib/IPC/Open3/Callback.pm', 
    META_MERGE    => {
        resources => {
            homepage => 'https://github.com/lucastheisen/ipc-open3-callback',
            bugtracker =>
              'https://github.com/lucastheisen/ipc-open3-callback/issues',
            repository => 'https://github.com/lucastheisen/ipc-open3-callback'
        },
    },
    test => {
        TESTS => 't/*.t'
    }
);

unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
    my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
    my $br = $WriteMakefileArgs{BUILD_REQUIRES};
    for my $mod ( keys %$tr ) {
        if ( exists $br->{$mod} ) {
            $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
        }
        else {
            $br->{$mod} = $tr->{$mod};
        }
    }
}

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

