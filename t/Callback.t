use strict;
use warnings;

use Test::More tests => 8;

BEGIN { use_ok('IPC::Open3::Callback') }

use IPC::Open3::Callback qw(safe_open3);
my $echo              = 'Hello World';
my $echo_result_regex = qr/^$echo[\r\n]?[\r\n]?$/;
my $buffer            = '';
my $err_buffer        = '';
my $runner            = IPC::Open3::Callback->new(
    {
        out_callback => sub {
            $buffer .= shift;
        },
        err_callback => sub {
            $err_buffer .= shift;
          }
    }
);

can_ok( $runner, @{ build_methods() } );

is( $runner->run_command("echo $echo"),
    0, 'run_command() method child process returns zero (success)' );
is( $err_buffer, '', "errbuffer" );
like( $buffer, $echo_result_regex, "outbuffer" );

$buffer = '';
$runner = IPC::Open3::Callback->new();
$runner->run_command(
    "echo", "Hello", "World",
    {
        out_callback => sub {
            $buffer .= shift;
          }
    }
);
like( $buffer, $echo_result_regex, "out_callback as command option" );

my ( $pid, $in, $out, $err ) = safe_open3("echo $echo");
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
                die( "impossible... somehow got a filehandle i dont know about!"
                );
            }
        }
    }
}
like( $buffer, $echo_result_regex, "safe_open3 read out" );
waitpid( $pid, 0 );
my $exit_code = $? >> 8;
ok( !$exit_code, "safe_open3 exited $exit_code" );

sub build_methods {

    my @methods;

    foreach (
        qw(out_callback err_callback buffer_output select_timeout buffer_size pid last_cmd input_buffer)
      )
    {

        push( @methods, "get_$_" );
        push( @methods, "set_$_" );

    }

    return \@methods;

}
