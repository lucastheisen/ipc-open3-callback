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

use Exporter qw(import);
our @EXPORT_OK = qw(safe_open3);

use Data::Dumper;
use Hash::Util qw(lock_keys);
use IO::Select;
use IO::Socket;
use IPC::Open3;
use Symbol qw(gensym);

my $logger;
eval {
    require Log::Log4perl;
    $logger = Log::Log4perl->get_logger('IPC::Open3::Callback');
};
if ($@) {
    $logger = IPC::Open3::Callback::NullLogger->new();
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
        last_cmd       => undef,
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

sub append_to_buffer {
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

sub nix_open3 {
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
    $out_callback = $options->{out_callback} || $self->{out_callback};
    $err_callback = $options->{err_callback} || $self->{err_callback};
    if ( $options->{buffer_output} || $self->{buffer_output} ) {
        $out_buffer_ref = \'';
        $err_buffer_ref = \'';
    }

    $self->{last_cmd} = join( ' ', @command );
    $logger->debug( "Running '", $self->{last_cmd}, "'" );
    my ( $pid, $in_fh, $out_fh, $err_fh ) = safe_open3(@command);
    $self->{pid} = $pid;

    my $select = IO::Select->new();
    $select->add( $out_fh, $err_fh );

    while ( my @ready = $select->can_read( $self->{select_timeout} ) ) {
        if ( $self->{input_buffer} ) {
            syswrite( $in_fh, $self->{input_buffer} );
            delete( $self->{input_buffer} );
        }
        foreach my $fh (@ready) {
            my $line;
            my $bytes_read = sysread( $fh, $line, $self->{buffer_size} );
            if ( !defined($bytes_read) && !$!{ECONNRESET} ) {
                $logger->error( "sysread failed: ", sub { Dumper(%!) } );
                $logger->logdie( "error in running '", $self->{last_cmd}, "': ", $! );
            }
            elsif ( !defined($bytes_read) || $bytes_read == 0 ) {
                $select->remove($fh);
                next;
            }
            else {
                if ( $fh == $out_fh ) {
                    $self->write_to_callback( $out_callback, $line, $out_buffer_ref, 0, $pid );
                }
                elsif ( $fh == $err_fh ) {
                    $self->write_to_callback( $err_callback, $line, $err_buffer_ref, 0, $pid );
                }
                else {
                    $logger->logdie('Impossible... somehow got a filehandle I dont know about!');
                }
            }
        }
    }

    # flush buffers
    $self->write_to_callback( $out_callback, '', $out_buffer_ref, 1, $pid );
    $self->write_to_callback( $err_callback, '', $err_buffer_ref, 1, $pid );
    return $self->destroy_child();
}

sub DESTROY {
    my $self = shift;
    $self->destroy_child();
}

sub destroy_child {
    my $self = shift;

    waitpid( $self->{pid}, 0 ) if ( $self->{pid} );
    my $exit_code = $? >> 8;

    $logger->debug( "exited '", $self->{last_cmd}, "' with code ", $exit_code );
    $self->{pid} = undef;
    return $exit_code;
}

sub safe_open3 {
    return ( $^O =~ /MSWin32/ ) ? win_open3(@_) : nix_open3(@_);
}

sub send_input {
    my $self = shift;
    $self->{input_buffer} = shift;
}

sub win_open3 {
    my @command = @_;

    my ( $in_read,  $in_write )  = win_pipe();
    my ( $out_read, $out_write ) = win_pipe();
    my ( $err_read, $err_write ) = win_pipe();

    my $pid = open3(
        '>&' . fileno($in_read),
        '<&' . fileno($out_write),
        '<&' . fileno($err_write), @command
    );

    return ( $pid, $in_write, $out_read, $err_read );
}

sub win_pipe {
    my ( $read, $write ) = IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC );
    $read->shutdown(SHUT_WR);     # No more writing for reader
    $write->shutdown(SHUT_RD);    # No more reading for writer

    return ( $read, $write );
}

sub write_to_callback {
    my $self       = shift;
    my $callback   = shift;
    my $data       = shift;
    my $buffer_ref = shift;
    my $flush      = shift;
    my $pid        = shift;

    return if ( !defined($callback) );

    if ( !defined($buffer_ref) ) {
        &{$callback}( $data, $pid );
        return;
    }

    &{$callback}($_) foreach ( $self->append_to_buffer( $buffer_ref, $data, $flush ) );
}

1;
__END__
=head1 NAME

IPC::Open3::Callback - An extension to IPC::Open3 that will feed out and err to callbacks instead of requiring the caller to handle them.

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
also provides a workaround for Windows systems.

=head1 FUNCTIONS

=head2 safe_open3( $command, $arg1, ..., $argN )

Passes the command and arguments on to C<open3> and returns a list containing:

=over 4

=item pid

The process id of the forked process

=item stdin

An L<IO::Handle> to STDIN for the process

=item stdout

An L<IO::Handle> to STDOUT for the process

=item stderr

An L<IO::Handle> to STDERR for the process

=back

As with C<open3>, it is the callers responsibility to waitpid to
ensure forked processes do not become zombies.

This method works for both *nix and Windows sytems.  On a windows system,
it will use sockets per L<http://www.perlmonks.org/index.pl?node_id=811150>.

=head1 CONSTRUCTOR

=head2 new( \%options )

The constructor creates a new Callback object and optionally sets global 
callbacks for C<STDOUT> and C<STDERR> streams from commands that will get run by 
this object (can be overridden per call to 
L<run_command|/"run_command( $command, $arg1, ..., $argN, \%options )">).

=over 4

=item out_callback

A subroutine to call for each chunk of text written to C<STDOUT>. This subroutine
will be called with 2 arguments:

=over 4

=item data

A chunk of text written to the stream

=item pid

The pid of the forked process

=back

=item err_callback

A subroutine to call for each chunk of text written to C<STDERR>. This subroutine
will be called with the same 2 arguments as C<out_callback>

=item buffer_output

A boolean value, if true, will buffer output and send to callback one line
at a time (waits for '\n').  Otherwise, sends text in the same chunks returned
by L<sysread>.

=item select_timeout

The timeout, in seconds, provided to C<IO::Select>, by default 0 meaning no
timeout which will cause the loop to block until output is ready on either
C<STDOUT> or C<STDERR>.

=back

=head1 METHODS

=head2 run_command( $command, $arg1, ..., $argN, \%options )

Will run the specified command with the supplied arguments by passing them on 
to L<safe_open3|/"safe_open3( $command, $arg1, ..., $argN )">.  Arguments can be embedded in the command string and 
are thus optional.

If the last argument to this method is a hashref (C<ref(@_[-1]) eq 'HASH'>), then
it is treated as an options hash.  The supported allowed options are the same
as the constructor and will be used in preference to the values set in the 
constructor for this call.

Returns the exit code from the command.

=head1 AUTHOR

=over

=item *

Lucas Theisen E<lt>lucastheisen@pastdev.comE<gt>

=item *

Alceu Rodrigues de Freitas Junior E<lt>arfreitas@cpan.orgE<gt>

=back

=head1 COPYRIGHT

Copyright 2013 pastdev.com. All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

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

=cut
