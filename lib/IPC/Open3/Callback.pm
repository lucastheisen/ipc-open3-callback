use strict;
use warnings;

package IPC::Open3::Callback;

# ABSTRACT: An extension to IPC::Open3 that will feed out and err to callbacks instead of requiring the caller to handle them.
# PODNAME: IPC::Open3::Callback

use Data::Dumper;
use Exporter qw(import);
use Hash::Util qw(lock_keys);
use IO::Select;
use IO::Socket;
use IPC::Open3;
use Symbol qw(gensym);

use parent qw(Class::Accessor);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(
    qw(out_callback err_callback buffer_output select_timeout buffer_size input_buffer));
__PACKAGE__->mk_ro_accessors(qw(pid last_command last_exit_code));

our @EXPORT_OK = qw(safe_open3);

my $logger;
eval {
    require Log::Log4perl;
    $logger = Log::Log4perl->get_logger('IPC::Open3::Callback');
};
if ($@) {
    require IPC::Open3::Callback::NullLogger;
    $logger = IPC::Open3::Callback::NullLogger->new();
}

sub new {
    my ($class, @args) = @_;
    return bless( {}, $class )->_init( @args );
}

sub _append_to_buffer {
    my ($self, $buffer_ref, $data, $flush) = @_;

    my @lines = split( /\n/, $$buffer_ref . $data, -1 );

    # save the last line in the buffer as it may not yet be a complete line
    $$buffer_ref = $flush ? '' : pop(@lines);

    # return all complete lines
    return @lines;
}

sub _clear_input_buffer {
    my ($self) = shift;
    delete( $self->{input_buffer} );
}

sub DESTROY {
    my ($self) = shift;
    $self->_destroy_child();
}

sub _destroy_child {
    my $self = shift;

    my $pid = $self->get_pid();
    if ( $pid ) {
        waitpid( $pid, 0 );
        $self->_set_last_exit_code( $? >> 8 );

        $logger->debug( sub {
            "Exited '", 
            $self->get_last_command(),
            "' with code ", 
            $self->get_last_exit_code()
        } );
        $self->_set_pid();
    }

    return $self->{last_exit_code};
}

sub _init {
    my ($self, $args_ref) = @_;

    $self->{buffer_output}  = undef;
    $self->{buffer_size}    = undef;
    $self->{err_callback}   = undef;
    $self->{input_buffer}   = undef;
    $self->{last_command}   = undef;
    $self->{last_exit_code} = undef;
    $self->{out_callback}   = undef;
    $self->{pid}            = undef;
    $self->{select_timeout} = undef;
    lock_keys( %{$self} );

    if ( defined($args_ref) ) {
        $logger->logdie('parameters must be an hash reference')
            unless ( ( ref($args_ref) ) eq 'HASH' );
        $self->{out_callback}   = $args_ref->{out_callback};
        $self->{err_callback}   = $args_ref->{err_callback};
        $self->{buffer_output}  = $args_ref->{buffer_output};
        $self->{select_timeout} = $args_ref->{select_timeout} || 3;
        $self->{buffer_size}    = $args_ref->{buffer_size} || 1024;
    }
    else {
        $self->{select_timeout} = 3;
        $self->{buffer_size}    = 1024;
    }

    return $self;
}

sub _nix_open3 {
    my @command = @_;

    my ( $in_fh, $out_fh, $err_fh ) = ( gensym(), gensym(), gensym() );
    return ( open3( $in_fh, $out_fh, $err_fh, @command ), $in_fh, $out_fh, $err_fh );
}

sub run_command {
    my ($self, @command) = @_;

    # if last arg is hashref, its command options not arg...
    my $options = {};
    if ( ref( $command[-1] ) eq 'HASH' ) {
        $options = pop( @command );
    }

    my ($out_callback,   $out_buffer_ref, $err_callback,
        $err_buffer_ref, $buffer_size,    $select_timeout
    );
    $out_callback = $options->{out_callback} || $self->get_out_callback();
    $err_callback = $options->{err_callback} || $self->get_err_callback();
    if ( $options->{buffer_output} || $self->get_buffer_output() ) {
        my $out_temp = '';
        my $err_temp = '';
        $out_buffer_ref = \$out_temp;
        $err_buffer_ref = \$err_temp;
    }
    $buffer_size    = $options->{buffer_size}    || $self->get_buffer_size();
    $select_timeout = $options->{select_timeout} || $self->get_select_timeout();

    $self->_set_last_command( \@command );
    $logger->debug( "Running '", $self->get_last_command(), "'" );
    my ( $pid, $in_fh, $out_fh, $err_fh ) = safe_open3(@command);
    $self->_set_pid($pid);

    my $select = IO::Select->new();
    $select->add( $out_fh, $err_fh );

    while ( my @ready = $select->can_read($select_timeout) ) {
        if ( $self->get_input_buffer() ) {
            syswrite( $in_fh, $self->get_input_buffer() );
            $self->_clear_input_buffer();
        }
        foreach my $fh (@ready) {
            my $line;
            my $bytes_read = sysread( $fh, $line, $buffer_size );
            if ( !defined($bytes_read) && !$!{ECONNRESET} ) {
                $logger->error( "sysread failed: ", sub { Dumper(%!) } );
                $logger->logdie( "error in running '", $self->get_last_command(), "': ", $! );
            }
            elsif ( !defined($bytes_read) || $bytes_read == 0 ) {
                $select->remove($fh);
                next;
            }
            else {
                if ( $fh == $out_fh ) {
                    $self->_write_to_callback( $out_callback, $line, $out_buffer_ref, 0 );
                }
                elsif ( $fh == $err_fh ) {
                    $self->_write_to_callback( $err_callback, $line, $err_buffer_ref, 0 );
                }
                else {
                    $logger->logdie('Impossible... somehow got a filehandle I dont know about!');
                }
            }
        }
    }

    # flush buffers
    $self->_write_to_callback( $out_callback, '', $out_buffer_ref, 1 );
    $self->_write_to_callback( $err_callback, '', $err_buffer_ref, 1 );
    return $self->_destroy_child();
}

sub safe_open3 {
    return ( $^O =~ /MSWin32/ ) ? _win_open3(@_) : _nix_open3(@_);
}

sub send_input {
    my ($self) = @_;
    $self->set_input_buffer(shift);
}

sub _set_last_command {
    my ($self, $command_ref) = @_;

    $logger->logdie('the command parameter must be an array reference')
        unless ( ( ref($command_ref) ) eq 'ARRAY' );

    $self->{last_command} = join( ' ', @{$command_ref} );
}

sub _set_last_exit_code {
    my ($self, $code) = @_;
    $self->{last_exit_code} = $code;
}

sub _set_pid {
    my ($self, $pid) = @_;

    if ( !defined($pid) ) {
        delete( $self->{pid} );
    }
    elsif ( $pid !~ /^\d+$/ ) {
        $logger->logdie('the parameter must be an integer');
    }
    else {
        $self->{pid} = $pid;
    }
}

sub _win_open3 {
    my (@command) = @_;

    my ( $in_read,  $in_write )  = _win_pipe();
    my ( $out_read, $out_write ) = _win_pipe();
    my ( $err_read, $err_write ) = _win_pipe();

    my $pid = open3(
        '>&' . fileno($in_read),
        '<&' . fileno($out_write),
        '<&' . fileno($err_write), @command
    );

    return ( $pid, $in_write, $out_read, $err_read );
}

sub _win_pipe {
    my ($read, $write) = IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC );
    $read->shutdown(SHUT_WR);     # No more writing for reader
    $write->shutdown(SHUT_RD);    # No more reading for writer

    return ( $read, $write );
}

sub _write_to_callback {
    my ($self, $callback, $data, $buffer_ref, $flush) = @_;

    return if ( !defined($callback) );

    if ( !defined($buffer_ref) ) {
        &{$callback}( $data, $self->get_pid() );
        return;
    }

    &{$callback}($_) foreach ( $self->_append_to_buffer( $buffer_ref, $data, $flush ) );
}

1;

__END__
=head1 SYNOPSIS

  use IPC::Open3::Callback;
  my $runner = IPC::Open3::Callback->new( {
      out_callback => sub {
          my $data = shift;
          my $pid = shift;

          print( "$pid STDOUT: $data\n" );
      },
      err_callback => sub {
          my $data = shift;
          my $pid = shift;

          print( "$pid STDERR: $data\n" );
      } } );
  my $exit_code = $runner->run_command( 'echo Hello World' );

  use IPC::Open3::Callback qw(safe_open3);
  my ($pid, $in, $out, $err) = safe_open3( "echo", "Hello", "world" ); 
  $buffer = '';
  my $select = IO::Select->new();
  $select->add( $out );
  while ( my @ready = $select->can_read( 5 ) ) {
      foreach my $fh ( @ready ) {
          my $line;
          my $bytes_read = sysread( $fh, $line, 1024 );
          if ( ! defined( $bytes_read ) && !$!{ECONNRESET} ) {
              die( "error in running ('echo $echo'): $!" );
          }
          elsif ( ! defined( $bytes_read) || $bytes_read == 0 ) {
              $select->remove( $fh );
              next;
          }
          else {
              if ( $fh == $out ) {
                  $buffer .= $line;
              }
              else {
                  die( "impossible... somehow got a filehandle i dont know about!" );
              }
          }
      }
  } 
  waitpid( $pid, 0 );
  my $exit_code = $? >> 8;
  print( "$pid exited with $exit_code: $buffer\n" ); # 123 exited with 0: Hello World

=head1 DESCRIPTION

This module feeds output and error stream from a command to supplied callbacks.  
Thus, this class removes the necessity of dealing with L<IO::Select> by hand and
also provides a workaround for the bad reputation associated with Microsoft 
Windows' IPC.

=export_ok safe_open3( $command, $arg1, ..., $argN )

Passes the command and arguments on to C<open3> and returns a list containing:

=over 4

=item pid

The process id of the forked process.

=item stdin

An L<IO::Handle> to STDIN for the process.

=item stdout

An L<IO::Handle> to STDOUT for the process.

=item stderr

An L<IO::Handle> to STDERR for the process.

=back

As with C<open3>, it is the callers responsibility to C<waitpid> to
ensure forked processes do not become zombies.

This method works for both *nix and Microsoft Windows OS's.  On a Windows 
system, it will use sockets per 
L<http://www.perlmonks.org/index.pl?node_id=811150>.

=constructor new( \%options )

The constructor creates a new Callback object and optionally sets global 
callbacks for C<STDOUT> and C<STDERR> streams from commands that will get run by 
this object (can be overridden per call to 
L<run_command|/"run_command( $command, $arg1, ..., $argN, \%options )">).
The currently available options are:

=over 4

=item out_callback

L<out_callback|/"set_out_callback( &subroutine )">

=item err_callback

L<err_callback|/"set_err_callback( &subroutine )">

=item buffer_output

L<buffer_output|/"set_buffer_output( $boolean )">

=item buffer_size

L<buffer_size|/"set_buffer_size( $bytes )">

=item select_timeout

L<select_timeout|/"set_select_timeout( $seconds )">

=back

=attribute get_buffer_output()

=attribute set_buffer_output( $boolean )

A boolean value, if true, will buffer output and send to callback one line
at a time (waits for '\n').  Otherwise, sends text in the same chunks returned
by L<sysread>.

=attribute get_buffer_size()

=attribute set_buffer_size( $bytes )

The size of the read buffer (in bytes) supplied to C<sysread>.

=attribute get_err_callback()

=attribute set_err_callback( &subroutine )

A subroutine that will be called for each chunk of text written to C<STDERR>. 
The subroutine will be called with the same 2 arguments as 
L<out_callback|/"set_out_callback( &subroutine )">.

=attribute get_last_command()

The last command run by the 
L<run_command|/"run_command( $command, $arg1, ..., $argN, \%options )"> method.

=attribute get_last_exit_code()

The exit code of the last command run by the 
L<run_command|/"run_command( $command, $arg1, ..., $argN, \%options )"> method.

=attribute get_out_callback()

=attribute set_out_callback( &subroutine )

A subroutine that will be called whenever a chunk of output is sent to STDOUT by the
opened process. The subroutine will be called with 2 arguments:

=over 4

=item data

A chunk of text written to the stream

=item pid

The pid of the forked process

=back

=attribute get_pid()

Will return the pid of the currently running process.  This pid is set by 
C<run_command> and will be cleared out when the C<run_command> completes.

=attribute get_select_timeout()

=attribute set_select_timeout( $seconds )

The timeout, in seconds, provided to C<IO::Select>, by default 0 meaning no
timeout which will cause the loop to block until output is ready on either
C<STDOUT> or C<STDERR>.

=method run_command( $command, $arg1, ..., $argN, \%options )

Will run the specified command with the supplied arguments by passing them on 
to L<safe_open3|/"safe_open3( $command, $arg1, ..., $argN )">.  Arguments can be embedded in the command string and 
are thus optional.

If the last argument to this method is a hashref (C<ref(@_[-1]) eq 'HASH'>), then
it is treated as an options hash.  The supported allowed options are the same
as the L<constructor|/"new( \%options )"> and will be used in preference to the values set by the  
constructor or any of the setters.  These options will be used for this single
call, and will not modify the C<Callback> object itself.

Returns the exit code from the command.

=for Pod::Coverage send_input

=head1 SEE ALSO
IPC::Open3
IPC::Open3::Callback::Command
IPC::Open3::Callback::CommandRunner
https://github.com/lucastheisen/ipc-open3-callback
http://stackoverflow.com/q/16675950/516433

