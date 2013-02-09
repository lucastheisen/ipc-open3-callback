#!/usr/bin/perl

package IPC::Open3::Callback::NullLogger;

use AutoLoader;

sub AUTOLOAD {
    print( "DO NOTHING" );
}

sub new {
    return bless( {}, shift );
}

no AutoLoader;

package IPC::Open3::Callback;

use strict;
use warnings;

use open OUT => ':utf8';

use IO::Select;
use IPC::Open3;
use Symbol;

my $logger;
eval {
    require Log::Log4perl;
    if(Log::Log4perl->initialized()) {
        $logger = Log::Log4perl->get_logger( 'IPC::Open3::Callback' );
        $logger->trace( "log4perl found, logger configured" );
    }
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

    $self->{outBuffer} = "";
    $self->{errBuffer} = "";

    return $self;
}

sub getLines {
    my $self = shift;
    my $buffer = shift;
    my $data = $self->{$buffer} . shift;
    my $flush = shift;

    my @lines = split( /\n/, $data, -1 );

    $self->{$buffer} = $flush ? "" : pop( @lines );
    
    return @lines;
}

sub sendInput {
    my $self = shift;
    $self->{inputBuffer} = shift;
}

sub writeErr {
    my $self = shift;
    my $data = shift;
    my $flush = shift;

    return if ( ! defined( $self->{errCallback} ) );

    if ( !$self->{bufferOutput} ) {
        $self->{errCallback}( $data );
        return;
    }

    my @lines = $self->getLines( 'errBuffer', $data, $flush );

    foreach my $line ( @lines ) {
        $self->{errCallback}( $line );
    }
}

sub writeOut {
    my $self = shift;
    my $data = shift;
    my $flush = shift;

    return if ( ! defined( $self->{outCallback} ) );

    if ( !$self->{bufferOutput} ) {
        $self->{outCallback}( $data );
        return;
    }

    my @lines = $self->getLines( 'outBuffer', $data, $flush );

    foreach my $line ( @lines ) {
        $self->{outCallback}( $line );
    }
}

sub runCommand {
    my $self = shift;
    my $command = shift;

    my ($infh, $outfh, $errfh);
    $errfh = gensym();

    $logger->info( "running '$command'" );
    my $pid;
    eval {
        $pid = open3( $infh, $outfh, $errfh, $command );
    };
    die( "failed to run '$command': $@" ) if ( $@ );

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
            if ( ! defined( $bytesRead ) ) {
                die( "error in running '$command': $!" );
            }
            elsif ( $bytesRead == 0 ) {
                $select->remove( $fh );
                next;
            }
            else {
                if ( $fh == $outfh ) {
                    $self->writeOut( $line );
                }
                elsif ( $fh == $errfh ) {
                    $self->writeErr( $line );
                }
                else {
                    die( "impossible... somehow got a filehandle i dont know about!" );
                }
            }
        }
    }
    $self->writeOut( "", 1 );
    $self->writeErr( "", 1 );

    waitpid( $pid, 0 );
    my $exitCode = $? >> 8;

    $logger->info( "exited '$command' with code $exitCode" );
    return $exitCode;
}

1;
__END__
=head1 NAME

NewModule - Perl module for hooting

=head1 SYNOPSIS

  use NewModule;
  my $hootie = new NewModule;
  $hootie->verbose(1);
  $hootie->hoot;  # Hoots
  $hootie->verbose(0);
  $hootie->hoot;  # Doesn't hoot
  

=head1 DESCRIPTION

This module hoots when it's verbose, and doesn't do anything 
when it's not verbose.  

=head2 Methods

=over 4

=item * $object->verbose(true or false)

=item * $object->verbose()

Returns the value of the 'verbose' property.  When called with an
argument, it also sets the value of the property.  Use a true or false
Perl value, such as 1 or 0.

=item * $object->hoot()

Returns a hoot if we're supposed to be verbose.  Otherwise it returns
nothing.

=back

=head1 AUTHOR

Ken Williams (ken@mathforum.org)

=head1 COPYRIGHT

Copyright 1998 Swarthmore College.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

perl(1).

=cut
