#!/usr/bin/perl

package IPC::Open3::Callback::NullLogger;

use AutoLoader;

our $LOG_TO_STDOUT = 0;

sub AUTOLOAD {
    shift;
    print( "NullLogger: @_\n" ) if $LOG_TO_STDOUT;
}

sub new {
    return bless( {}, shift );
}

no AutoLoader;

package IPC::Open3::Callback;

use strict;
use warnings;
our ($VERSION);

use Data::Dumper;
use IO::Select;
use IO::Socket;
use IPC::Open3;
use Symbol qw(gensym);

$VERSION = "1.00_01";

my $logger;
eval {
    require Log::Log4perl;
    $logger = Log::Log4perl->get_logger( 'IPC::Open3::Callback' );
};
if ( $@ ) {
    $logger = IPC::Open3::Callback::NullLogger->new();
}

sub new {
    my $prototype = shift;
    my $class = ref( $prototype ) || $prototype;
    my $self = {};
    bless( $self, $class );

    my %args = @_;

    $self->{outCallback} = $args{outCallback};
    $self->{errCallback} = $args{errCallback};
    $self->{bufferOutput} = $args{bufferOutput};
    $self->{selectTimeout} = $args{selectTimeout};

    return $self;
}

sub appendToBuffer {
    my $self = shift;
    my $bufferRef = shift;
    my $data = $$bufferRef . shift;
    my $flush = shift;

    my @lines = split( /\n/, $data, -1 );

    # save the last line in the buffer as it may not yet be a complete line
    $$bufferRef = $flush ? '' : pop( @lines );
    
    # return all complete lines
    return @lines;
}

sub nixOpen3 {
    my ($inFh, $outFh, $errFh) = (gensym(), gensym(), gensym());
    return ( open3( $inFh, $outFh, $errFh, shift ), $inFh, $outFh, $errFh );
}

sub runCommand {
    my $self = shift;
    my $command = shift;
    my %options = @_;
    
    my ($outCallback, $outBufferRef, $errCallback, $errBufferRef);
    $outCallback = $options{outCallback} || $self->{outCallback};
    $errCallback = $options{errCallback} || $self->{errCallback};
    if ( $options{bufferOutput} || $self->{bufferOutput} ) {
        $outBufferRef = \'';
        $errBufferRef = \'';
    }

    $logger->info( "running '$command'" );
    my ($pid, $infh, $outfh, $errfh) = safeOpen3( $command );

    my $select = IO::Select->new();
    $select->add( $outfh, $errfh );

    while ( my @ready = $select->can_read( $self->{selectTimeout} ) ) {
        if ( $self->{inputBuffer} ) {
            syswrite( $infh, $self->{inputBuffer} );
            delete( $self->{inputBuffer} );
        }
        foreach my $fh ( @ready ) {
            my $line;
            my $bytesRead = sysread( $fh, $line, 1024 );
            if ( ! defined( $bytesRead ) && !$!{ECONNRESET} ) {
                $logger->error( "sysread failed: ", sub { Dumper( %! ) } );
                die( "error in running '$command': $!" );
            }
            elsif ( ! defined( $bytesRead) || $bytesRead == 0 ) {
                $select->remove( $fh );
                next;
            }
            else {
                if ( $fh == $outfh ) {
                    $self->writeToCallback( $outCallback, $line, $outBufferRef );
                }
                elsif ( $fh == $errfh ) {
                    $self->writeToCallback( $errCallback, $line, $errBufferRef );
                }
                else {
                    die( "impossible... somehow got a filehandle i dont know about!" );
                }
            }
        }
    }
    # flush buffers
    $self->writeToCallback( $outCallback, '', $outBufferRef, 1 );
    $self->writeToCallback( $errCallback, '', $errBufferRef, 1 );

    waitpid( $pid, 0 );
    my $exitCode = $? >> 8;

    $logger->info( "exited '$command' with code $exitCode" );
    return $exitCode;
}

sub safeOpen3 {
    return ( $^O =~ /MSWin32/ ) ? winOpen3( $_[0] ) : nixOpen3( $_[0] );
}

sub sendInput {
    my $self = shift;
    $self->{inputBuffer} = shift;
}

sub winOpen3 {
    my $command = shift;
    
    my ($inRead, $inWrite) = winPipe();
    my ($outRead, $outWrite) = winPipe();
    my ($errRead, $errWrite) = winPipe();
    
    my $pid = open3( '>&'.fileno($inRead), 
        '<&'.fileno($outWrite), 
        '<&'.fileno($errWrite),
         $command );
    
    return ( $pid, $inWrite, $outRead, $errRead );
}

sub winPipe {
    my ($read, $write) = IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC );
    $read->shutdown( SHUT_WR );  # No more writing for reader
    $write->shutdown( SHUT_RD );  # No more reading for writer

    return ($read, $write);
}

sub writeToCallback {
    my $self = shift;
    my $callback = shift;
    my $data = shift;
    my $bufferRef = shift;
    my $flush = shift;
    
    return if ( ! defined( $callback ) );
    
    if ( ! defined( $bufferRef ) ) {
        &{$callback}( $data );
        return;
    }
    
    &{$callback}( $_ ) foreach ( $self->appendToBuffer( $bufferRef, $data, $flush ) ) ;
}

1;
__END__
=head1 NAME

IPC::Open3::Callback - An extension to Open3 that will feed out and err to
callbacks instead of requiring the caller to handle them.

=head1 SYNOPSIS

  use IPC::Open3::Callback;
  my $runner = IPC::Open3::Callback->new( 
      outCallback => sub {
          print( "$_[0]\n" );
      },
      errCallback => sub {
          print( STDERR "$_[0]\n" );
      } );
  $runner->runCommand( 'echo Hello World' );
  

=head1 DESCRIPTION

This module feeds output and error stream from a command to supplied callbacks.  

=head2 CONSTRUCTOR

=over 4

=item new( [ outCallback => SUB ], [ errCallback => SUB ] )

The constructor creates a new object and attaches callbacks for STDOUT and
STDERR streams from commands that will get run on this object.

=back

=head1 METHODS

=over 4

=item runCommand( [ COMMAND ] )

Returns the value of the 'verbose' property.  When called with an
argument, it also sets the value of the property.  Use a true or false
Perl value, such as 1 or 0.

=back

=head1 AUTHOR

Lucas Theisen (lucastheisen@pastdev.com)

=head1 COPYRIGHT

Copyright 2013 pastdev.com.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

IPC::Open3(1).

=cut
