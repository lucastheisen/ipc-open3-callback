# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Silly-Proj.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 3;

BEGIN { use_ok('IPC::Open3::Callback') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

use IPC::Open3::Callback;
my $echo = 'Hello World';
my $buffer = '';
my $errBuffer = '';
my $runner = IPC::Open3::Callback->new(
    outCallback => sub {
        $buffer .= shift;
    },
    errCallback => sub {
        $errBuffer .= shift;
    } );
$runner->runCommand( "echo $echo" );
ok( $errBuffer eq '', "errbuffer" );
ok( $buffer =~ /^$echo[\r\n]?[\r\n]?$/, "outbuffer" );
