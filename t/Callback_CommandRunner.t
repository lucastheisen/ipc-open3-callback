use strict;
use warnings;

use Test::Most tests => 6;

BEGIN { use_ok('IPC::Open3::Callback::CommandRunner') }

my $echo              = 'Hello World';
my $echo_result_regex = qr/^$echo[\r\n]?[\r\n]?$/;
my $command_runner    = IPC::Open3::Callback::CommandRunner->new();
my $exit_code = $command_runner->run( "echo $echo", { out_buffer => 1 } );
is( $exit_code, 0, 'echo exit code means success' );
like( $command_runner->out_buffer(), $echo_result_regex, 'echo out match' );

lives_ok { $command_runner->run_or_die( "echo $echo", { out_buffer => 1 } ) }
'expected to live';

dies_ok { $command_runner->run_or_die("THIS_IS_NOT_A_COMMAND") }
'expected to die';

can_ok( $command_runner, @{ build_methods() } );

sub build_methods {

    my @methods;

    foreach (qw(out_buffer err_buffer command_runner)) {

        push( @methods, "get_$_" );
        push( @methods, "set_$_" );

    }

    return \@methods;

}
