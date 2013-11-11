#!/usr/bin/perl

use strict;
use warnings;

package IPC::Open3::Callback::NullLogger;

use AutoLoader;

our $LOG_TO_STDOUT = 0;

sub AUTOLOAD {
    shift;
    print("IPC::Open3::Callback::NullLogger: @_\n") if $LOG_TO_STDOUT;
}

sub new {
    return bless( {}, shift );
}

no AutoLoader;

package IPC::Open3::Callback;

# ABSTRACT: An extension to IPC::Open3 that will feed out and err to callbacks instead of requiring the caller to handle them.

use Exporter qw(import);
our @EXPORT_OK = qw(safe_open3);

use Data::Dumper;
use Hash::Util qw(lock_keys);
use IO::Select;
use IO::Socket;
use IPC::Open3;
use Symbol qw(gensym);

use parent qw(Class::Accessor);
__PACKAGE__->follow_best_practice;
__PACKAGE__->mk_accessors(
    qw(out_callback err_callback buffer_output select_timeout buffer_size input_buffer));
__PACKAGE__->mk_ro_accessors(qw(pid last_command));

my $logger;
eval {
    require Log::Log4perl;
    $logger = Log::Log4perl->get_logger('IPC::Open3::Callback');
};
if ($@) {
    $logger = IPC::Open3::Callback::NullLogger->new();
}

sub _set_pid {
		
		my $self = shift;
		my $value = shift;

		$logger->logdie('the parameter must be an integer') unless((defined($value)) and ($value =~ /^\d+$/));

		$self->{pid} = $value;
		
		}

sub new {
    my $prototype = shift;
    my $class = ref($prototype) || $prototype;

    my $self = {
        out_callback   => undef,
        err_callback   => undef,
        buffer_output  => undef,
        select_timeout => undef,
        buffer_size    => undef,
        pid            => undef,
        last_command   => undef,
        input_buffer   => undef
    };
    bless( $self, $class );

    my $args_ref = shift;

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

    lock_keys( %{$self} );

    return $self;
}

sub _append_to_buffer {
    my $self       = shift;
    my $buffer_ref = shift;
    my $data       = $$buffer_ref . shift;
    my $flush      = shift;

    my @lines = split( /\n/, $data, -1 );

    # save the last line in the buffer as it may not yet be a complete line
    $$buffer_ref = $flush ? '' : pop(@lines);

    # return all complete lines
    return @lines;
}

sub clear_input_buffer {
    my $self = shift;
    delete( $self->{input_buffer} );
}

sub DESTROY {
    my $self = shift;
    $self->_destroy_child();
}

sub _destroy_child {
    my $self = shift;

    waitpid( $self->get_pid(), 0 ) if ( $self->get_pid() );
    my $exit_code = $? >> 8;

    $logger->debug( "exited '", $self->get_last_command(), "' with code ", $exit_code );
    return $exit_code;
}

sub _nix_open3 {
    my @command = @_;

    my ( $in_fh, $out_fh, $err_fh ) = ( gensym(), gensym(), gensym() );
    return ( open3( $in_fh, $out_fh, $err_fh, @command ), $in_fh, $out_fh, $err_fh );
}

sub run_command {
    my $self    = shift;
    my @command = @_;
    my $options = {};

    # if last arg is hashref, its command options not arg...
    if ( ref( $command[-1] ) eq 'HASH' ) {
        $options = pop(@command);
    }

    my ( $out_callback, $out_buffer_ref, $err_callback, $err_buffer_ref );
    $out_callback = $options->{out_callback} || $self->get_out_callback();
    $err_callback = $options->{err_callback} || $self->get_err_callback();

    if ( $options->{buffer_output} || $self->get_buffer_output() ) {
        $out_buffer_ref = \'';
        $err_buffer_ref = \'';
    }

    $self->_set_last_command( \@command );
    $logger->debug( "Running '", $self->get_last_command(), "'" );
    my ( $pid, $in_fh, $out_fh, $err_fh ) = safe_open3(@command);
    $self->_set_pid($pid);

    my $select = IO::Select->new();
    $select->add( $out_fh, $err_fh );

    while ( my @ready = $select->can_read( $self->get_select_timeout() ) ) {
        if ( $self->get_input_buffer() ) {
            syswrite( $in_fh, $self->get_input_buffer() );
            $self->clear_input_buffer();
        }
        foreach my $fh (@ready) {
            my $line;
            my $bytes_read = sysread( $fh, $line, $self->get_buffer_size() );
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
    my $self = shift;
    $self->set_input_buffer(shift);
}

sub _set_last_command {
    my $self        = shift;
    my $command_ref = shift;    #array ref

    $logger->logdie('the command parameter must be an array reference')
        unless ( ( ref($command_ref) ) eq 'ARRAY' );

    $self->{last_command} = join( ' ', @{$command_ref} );
}

sub _win_open3 {
    my @command = @_;

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
    my ( $read, $write ) = IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC );
    $read->shutdown(SHUT_WR);     # No more writing for reader
    $write->shutdown(SHUT_RD);    # No more reading for writer

    return ( $read, $write );
}

sub _write_to_callback {

    my $self       = shift;
    my $callback   = shift;
    my $data       = shift;
    my $buffer_ref = shift;
    my $flush      = shift;

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
also provides a workaround for Microsoft Windows' IPC bad reputation.

=head1 EXPORTS

Only C<safe_open3> is exported on demand.

=head2 safe_open3( $command, $arg1, ..., $argN )

Passes the command and arguments on to C<open3> and returns a list containing:

=over 4

=item 1.

The process id of the forked process.

=item 2.

An L<IO::Handle> to STDIN for the process.

=item 3. 

An L<IO::Handle> to STDOUT for the process.

=item 4.

An L<IO::Handle> to STDERR for the process.

=back

As with C<open3>, it is the callers responsibility to C<waitpid> to
ensure forked processes do not become zombies.

This method works for both *nix and Microsoft Windows OS's.  On a Windows system,
it will use sockets as described in L<http://www.perlmonks.org/index.pl?node_id=811150>.

=head1 ATTRIBUTES

=head2 out_callback

A subroutine to call for each chunk of text written to C<STDOUT>. This subroutine
will be called with 2 arguments:

=over 4

=item 1.

A chunk of text written to the stream.

=item 2.

The pid of the forked process.

=back

=head2 err_callback

A subroutine to call for each chunk of text written to C<STDERR>. This subroutine
will be called with the same 2 arguments as C<out_callback>.

=head2 buffer_output

A boolean value, if true, will buffer output and send to callback one line
at a time (waits for C<\n>).  Otherwise, sends text in the same chunks returned
by C<sysread>.

=head2 select_timeout

The timeout, in seconds, provided to L<IO::Select>, by default 0 meaning no
timeout which will cause the loop to block until output is ready on either
C<STDOUT> or C<STDERR>.

=head2 buffer_size

The size in bytes of the amount of data that C<sysread> will have to consider. It defaults to 1024.

Changing the buffer size can increase memory while improving performance since will reduce the amount of loops required to read all data.

=head2 pid

As integer as the process identificator of the OS.

=head2 input_buffer

A string with additional commands that can be submitted to the executed program through it's STDIN handle.

This attribute value is removed automatically during the C<run_command> method execution.

=head2 last_command

An string representing the last command executed by the L<IPC::Open3::Callback> instance.

=head1 METHODS

=head2 new

The constructor creates a new Callback object and optionally sets global 
callbacks for C<STDOUT> and C<STDERR> streams from commands that will get run by 
this object (can be overridden per call to C<run_command>).

Expects a hash reference as parameter containing the following keys explained below:

=over 4

=item *

out_callback

=item *

err_callback

=item *

buffer_output

=item *

select_timeout

=back

=head2 get_err_callback

Returns the content of the L<err_callback|err_callback> attribute.

=head2 set_err_callback

Sets the attribute L<err_callback|err_callback>. Expects a code reference as parameter.

=head2 get_last_command

Returns the content of the L<last_command|last_command> attribute.

=head2 _set_last_command

Sets the attribute L<last_command|last_command>. Expects an array reference as parameter.

This is a "private" method and should be invoked internally only.

=head2 get_out_callback

Returns the content of the L<out_callback|out_callback> attribute.

=head2 set_out_callback

Sets the L<out_callback|out_callback> attribute. Expects a code reference as parameter.

=head2 get_buffer_size

Returns the contents of the attribute L<buffer_size|buffer_size>.

=head2 set_buffer_size

Sets the contents of the attribute L<buffer_size|buffer_size>. Expects as parameter an integer.

=head2 get_pid

Returns the content of the L<pid|pid> attribute.

=head2 _set_pid

Sets the attribute L<pid|pid>. Expects an integer as parameter.

This is a "private" method and should be used internally only.

=head2 get_input_buffer

Returns the contents of the L<input_buffer|input_buffer> attribute.

=head2 set_input_buffer

Sets the attribute L<input_buffer|input_buffer>. Expects an string as parameter.

=head2 run_command

Will run the specified command with the supplied arguments by passing them on 
to L<safe_open3|/"safe_open3( $command, $arg1, ..., $argN )">.  Arguments can be embedded in the command string and 
are thus optional.

If the last argument to this method is a hash reference then it will be considered as the same allowed options used in the
L<constructor|new> and will be used in preference to the values set in the constructor for this call.

Returns the exit code from the command.

=head1 SEE ALSO

=over

=item *

L<IPC::Open3>

=item *

L<IPC::Open3::Callback::Command>

=item *

L<IPC::Open3::Callback::CommandRunner>

=item *

L<https://github.com/lucastheisen/ipc-open3-callback>

=item *

L<http://stackoverflow.com/q/16675950/516433>

=back
