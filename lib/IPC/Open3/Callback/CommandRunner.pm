#!/usr/local/bin/perl

use strict;
use warnings;

package IPC::Open3::Callback::CommandRunner;

# ABSTRACT: A utility class that wraps IPC::Open3::Callback with available output buffers and an option to die on failure instead of returning exit code.

use Hash::Util qw(lock_keys);
use IPC::Open3::Callback;

sub new {
    my $prototype = shift;
    my $class     = ref($prototype) || $prototype;
    my $self      = { command_runner => IPC::Open3::Callback->new() };
    bless( $self, $class );

    lock_keys( %{$self}, keys( %{$self} ), 'out_buffer', 'err_buffer' );

    return $self;
}

sub _build_callback {
    my $self       = shift;
    my $out_or_err = shift;
    my $options    = shift;

    if ( defined( $options->{ $out_or_err . '_callback' } ) ) {
        return $options->{ $out_or_err . '_callback' };
    }
    elsif ( $options->{ $out_or_err . '_buffer' } ) {
        $self->{ $out_or_err . '_buffer' } = ();
        return sub {
            push( @{ $self->{ $out_or_err . '_buffer' } }, shift );
        };
    }
    return;
}

sub _clear_buffers {
    my $self = shift;
    delete( $self->{out_buffer} );
    delete( $self->{err_buffer} );
}

sub get_err_buffer {
    return join( '', @{ shift->{err_buffer} } );
}

sub _options {
    my $self    = shift;
    my %options = @_;

    $options{out_callback} = $self->_build_callback( 'out', \%options );
    $options{err_callback} = $self->_build_callback( 'err', \%options );

    return %options;
}

sub get_out_buffer {
    return join( '', @{ shift->{out_buffer} } );
}

sub run {
    my $self    = shift;
    my @command = @_;
    my %options = ();

    # if last arg is hashref, its command options not arg...
    if ( ref( $command[-1] ) eq 'HASH' ) {
        %options = $self->_options( %{ pop(@command) } );
    }

    $self->_clear_buffers();

    return $self->{command_runner}->run_command( @command, \%options );
}

sub run_or_die {
    my $self    = shift;
    my @command = @_;
    my %options = ();

    # if last arg is hashref, its command options not arg...
    if ( ref( $command[-1] ) eq 'HASH' ) {
        %options = $self->_options( %{ pop(@command) } );
    }

    $self->_clear_buffers();

    my $exit_code = $self->{command_runner}->run_command( @command, \%options );
    if ($exit_code) {
        my $message = "FAILED ($exit_code): @command";
        $message .= " out_buffer=($self->{out_buffer})" if ( $options{out_buffer} );
        $message .= " err_buffer=($self->{err_buffer})" if ( $options{err_buffer} );
        die($message);
    }
}

1;
__END__
=head1 SYNOPSIS

  use IPC::Open3::Callback::CommandRunner;

  my $command_runner = IPC::Open3::Callback::CommandRunner->new();
  my $exit_code = $command_runner->run( 'echo Hello, World!' );

  eval {
      $command_runner->run_or_die( $command_that_might_die );
  };
  if ( $@ ) {
      print( "command died: $@\n" );
  }

=head1 DESCRIPTION

Adds more convenience to IPC::Open3::Callback by buffering output and error
if needed and dieing on failure if wanted.

=constructor new()

The constructor creates a new CommandRunner.

=attribute get_err_buffer()

Returns the contents of the err_buffer from the last call to 
L<run|/"run( $command, $arg1, ..., $argN, \%options )"> or 
L<run_or_die|/"run_or_die( $command, $arg1, ..., $argN, \%options )">.

=attribute get_out_buffer()

Returns the contents of the err_buffer from the last call to 
L<run|/"run( $command, $arg1, ..., $argN, \%options )"> or 
L<run_or_die|/"run_or_die( $command, $arg1, ..., $argN, \%options )">.

=method run( $command, $arg1, ..., $argN, \%options )

Will run the specified command with the supplied arguments by passing them on to 
L<run_command|IPC::Open3::Callback/"run_command( $command, $arg1, ..., $argN, \%options )">.  
Arguments can be embedded in the command string and are thus optional.

If the last argument to this method is a hashref (C<ref(@_[-1]) eq 'HASH'>), then
it is treated as an options hash.  The supported allowed options are the same as 
L<run_command|IPC::Open3::Callback/"run_command( $command, $arg1, ..., $argN, \%options )"> 
plus:

=over 4

=item out_buffer

If true, a callback will be generated for C<STDOUT> that buffers all data 
and can be accessed via L<out_buffer()|/"out_buffer()">

=item err_buffer

If true, a callback will be generated for C<STDERR> that buffers all data 
and can be accessed via L<err_buffer()|/"err_buffer()">

=back

Returns the exit code from the command.

=method run_or_die( $command, $arg1, ..., $argN, \%options )

The same as L<run|/"run( $command, $arg1, ..., $argN, \%options )"> exept that it
will C<die> on a non-zero exit code instead of returning the exit code.

=head1 SEE ALSO
IPC::Open3::Callback
IPC::Open3::Callback::Command
