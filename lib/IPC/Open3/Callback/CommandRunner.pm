#!/usr/local/bin/perl

package IPC::Open3::Callback::CommandRunner;

use strict;
use warnings;

use IPC::Open3::Callback;

sub new {
    my $prototype = shift;
    my $class = ref( $prototype ) || $prototype;
    my $self = {};
    bless( $self, $class );

    $self->{commandRunner} = IPC::Open3::Callback->new();

    return $self
}

sub buildCallback {
    my $self = shift;
    my $outOrErr = shift;
    my $options = shift;

    if ( defined( $options->{$outOrErr . 'Callback'} ) ) {
        return $options->{$outOrErr . 'Callback'};
    }
    elsif ( $options->{$outOrErr . 'Buffer'} ) {
        $self->{$outOrErr . 'Buffer'} = ();
        return sub {
            push( @{$self->{$outOrErr . 'Buffer'}}, @_ );
        };
    }
    return undef;
}

sub clearBuffers {
    my $self = shift;
    delete( $self->{outBuffer} );
    delete( $self->{errBuffer} );
}

sub errBuffer {
    return join( '', @{shift->{errBuffer}} );
}

sub options {
    my $self = shift;
    my %options = @_;

    $options{outCallback} = $self->buildCallback( 'out', \%options );
    $options{errCallback} = $self->buildCallback( 'err', \%options );

    return %options;
}

sub outBuffer {
    return join( '', @{shift->{outBuffer}} );
}

sub run {
    my $self = shift;
    my $command = shift;
    my %options = $self->options( @_ );

    $self->clearBuffers();

    return $self->{commandRunner}->runCommand( $command, %options );
}

sub runOrDie {
    my $self = shift;
    my $command = shift;
    my %options = $self->options( @_ );

    $self->clearBuffers();

    my $exitCode = $self->{commandRunner}->runCommand( $command, %options );
    if ( $exitCode ) {
        my $message = "FAILED ($exitCode): $command";
        $message .= " outBuffer=($self->{outBuffer})" if ( $options{outBuffer} );
        $message .= " errBuffer=($self->{errBuffer})" if ( $options{errBuffer} );
        die( $message );
    }
}

1;