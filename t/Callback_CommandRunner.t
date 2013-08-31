use strict;
use warnings;

use Test::More tests => 5;

BEGIN { use_ok('IPC::Open3::Callback::CommandRunner') };

use IPC::Open3::Callback::CommandRunner; 

my $echo = 'Hello World';
my $echo_result_regex = qr/^$echo[\r\n]?[\r\n]?$/;
my $command_runner = IPC::Open3::Callback::CommandRunner->new();
my $exit_code = $command_runner->run( "echo $echo", {out_buffer=>1} );
ok( !$exit_code, 'echo exit code' );
like( $command_runner->out_buffer(), $echo_result_regex, 'echo out match' );

eval {
    $command_runner->run_or_die( "echo $echo", {out_buffer=>1} );
};
ok( !$@, 'shouldnt die' );

eval {
    $command_runner->run_or_die( "THIS_IS_NOT_A_COMMAND" );
};
ok( $@, 'should die' );