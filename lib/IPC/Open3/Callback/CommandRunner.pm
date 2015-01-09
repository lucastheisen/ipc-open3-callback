use strict;
use warnings;

package IPC::Open3::Callback::CommandRunner;

# ABSTRACT: A utility class that wraps IPC::Open3::Callback with available output buffers and an option to die on failure instead of returning exit code.

use Hash::Util qw(lock_keys);
use IPC::Open3::Callback;
use IPC::Open3::Callback::CommandFailedException;

sub new {
    return bless( {}, shift )->_init( @_ );
}

sub _build_callback {
    my ($self, $out_or_err, $options) = @_;

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
    my ($self) = @_;
    delete( $self->{out_buffer} );
    delete( $self->{err_buffer} );
}

sub _condense {
    my ($self, $buffer) = @_;

    if ( $self->{$buffer} ) {
        $self->{$buffer} = [join( '', @{$self->{$buffer}} )];
        return $self->{$buffer}[0];
    }
    
    return undef;
}

sub get_err_buffer {
    return $_[0]->_condense( 'err_buffer' );
}

sub _init {
    my ($self, @options) = @_;
    
    $self->{command_runner} = IPC::Open3::Callback->new( @options );

    lock_keys( %{$self}, keys( %{$self} ), 'out_buffer', 'err_buffer' );

    return $self;
}

sub _options {
    my ($self, %options) = @_;

    $options{out_callback} = $self->_build_callback( 'out', \%options );
    $options{err_callback} = $self->_build_callback( 'err', \%options );

    return %options;
}

sub get_out_buffer {
    return $_[0]->_condense( 'out_buffer' );
}

sub run {
    my ($self, @command) = @_;
    my %options = ();

    # if last arg is hashref, its command options not arg...
    if ( ref( $command[-1] ) eq 'HASH' ) {
        %options = $self->_options( %{ pop(@command) } );
    }

    $self->_clear_buffers();

    return $self->{command_runner}->run_command( @command, \%options );
}

sub run_or_die {
    my ($self, @command) = @_;
    my %options = ();

    # if last arg is hashref, its command options not arg...
    if ( ref( $command[-1] ) eq 'HASH' ) {
        %options = $self->_options( %{ pop(@command) } );
    }

    $self->_clear_buffers();

    my $exit_code = $self->{command_runner}->run_command( @command, \%options );
    if ($exit_code) {
        my $exception = IPC::Open3::Callback::CommandFailedException->new(
            \@command,
            $exit_code,
            $self->get_out_buffer(),
            $self->get_err_buffer() );
        die( $exception );
    }
    
    return $self->get_out_buffer();
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
will C<die> on a non-zero exit code instead of returning the exit code.  If the
C<out_buffer> option was specified, the output from the command will be returned.

=head1 SEE ALSO
IPC::Open3::Callback
IPC::Open3::Callback::Command
