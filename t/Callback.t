use strict;
use warnings;

eval {
    require Log::Log4perl;
    Log::Log4perl->easy_init( $Log::Log4perl::ERROR );
};

use Test::More tests => 16;
use IPC::Open3::Callback qw(safe_open3);

BEGIN { use_ok('IPC::Open3::Callback') }

my @methods = (
    'new',               'get_err_callback', 'set_err_callback', 'get_last_command',
    '_set_last_command', 'get_out_callback', 'set_out_callback', 'get_buffer_size',
    'set_buffer_size',   'get_pid',          '_set_pid',         'get_input_buffer',
    'run_command'
);

my $echo              = 'Hello World';
my $echo_result_regex = qr/^$echo[\r\n]?[\r\n]?$/;
my $buffer            = '';
my $err_buffer        = '';
my $runner;

ok( $runner = IPC::Open3::Callback->new(
        {   out_callback => sub {
                $buffer .= shift;
            },
            err_callback => sub {
                $err_buffer .= shift;
                }
        }
    ),
    'can get an instance'
);

isa_ok( $runner, 'IPC::Open3::Callback' );
can_ok( $runner, @methods );
isa_ok( $runner->get_out_callback(), 'CODE' );
isa_ok( $runner->get_err_callback(), 'CODE' );
is( $runner->get_buffer_size(), 1024, 'get_buffer_size returns the default value' );
is( $runner->run_command("echo $echo"),
    0, 'run_command() method child process returns zero (success)' );
$runner->set_buffer_size(512);
is( $runner->get_buffer_size(),  512,          'get_buffer_size returns the new value' );
is( $runner->get_last_command(), "echo $echo", 'get_last_command returns the correct value' );
is( $err_buffer,                 '',           "err_buffer has the correct value" );
like( $buffer, $echo_result_regex, "outbuffer has the correct value" );

my ( $pid, $in, $out, $err );
$runner->run_command(
    'echo', 'hello', 'world',
    {   out_callback => sub {
            $pid = $runner->get_pid();
            }
    }
);
like( $pid, qr/^\d+$/, 'get_pid returns something like a PID' );

$buffer = '';
$runner = IPC::Open3::Callback->new();
$runner->run_command(
    "echo", "Hello", "World",
    {   out_callback => sub {
            $buffer .= shift;
            }
    }
);
like( $buffer, $echo_result_regex, "out_callback as command option" );

( $pid, $in, $out, $err ) = safe_open3("echo $echo");
$buffer = '';
my $select = IO::Select->new();
$select->add($out);
while ( my @ready = $select->can_read(5) ) {
    foreach my $fh (@ready) {
        my $line;
        my $bytes_read = sysread( $fh, $line, 1024 );
        if ( !defined($bytes_read) && !$!{ECONNRESET} ) {
            die("error in running ('echo $echo'): $!");
        }
        elsif ( !defined($bytes_read) || $bytes_read == 0 ) {
            $select->remove($fh);
            next;
        }
        else {
            if ( $fh == $out ) {
                $buffer .= $line;
            }
            else {
                die("impossible... somehow got a filehandle i dont know about!");
            }
        }
    }
}
like( $buffer, $echo_result_regex, "safe_open3 read out" );
waitpid( $pid, 0 );
my $exit_code = $? >> 8;
ok( !$exit_code, "safe_open3 exited $exit_code" );
