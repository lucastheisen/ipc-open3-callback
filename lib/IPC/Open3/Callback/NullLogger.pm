use strict;
use warnings;

package IPC::Open3::Callback::NullLogger;

# ABSTRACT: A logger for when Log4perl is not available
# PODNAME: IPC::Open3::Callback::NullLogger

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

1;

__END__
=head1 SYNOPSIS

  use IPC::Open3::Callback;
  use IPC::Open3::Callback::NullLogger;

  $IPC::Open3::Callback::NullLogger::LOG_TO_STDOUT=1;

  # log messages will be written to std out
  my $runner = IPC::Open3::Callback->new();
  my $exit_code = $runner->run_command( 'echo Hello World' );

=head1 DESCRIPTION

This provides a very basic logger for when Log4perl is not available.

=for Pod::Coverage new AUTOLOAD

=head1 SEE ALSO
IPC::Open3::Callback
IPC::Open3::Callback::Command
IPC::Open3::Callback::CommandRunner
https://github.com/lucastheisen/ipc-open3-callback

