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

    $self->{command_runner} = IPC::Open3::Callback->new();

    return $self
}

sub build_callback {
    my $self = shift;
    my $out_or_err = shift;
    my $options = shift;

    if ( defined( $options->{$out_or_err . '_callback'} ) ) {
        return $options->{$out_or_err . '_callback'};
    }
    elsif ( $options->{$out_or_err . '_buffer'} ) {
        $self->{$out_or_err . '_buffer'} = ();
        return sub {
            push( @{$self->{$out_or_err . '_buffer'}}, shift );
        };
    }
    return undef;
}

sub clear_buffers {
    my $self = shift;
    delete( $self->{out_buffer} );
    delete( $self->{err_buffer} );
}

sub err_buffer {
    return join( '', @{shift->{err_buffer}} );
}

sub options {
    my $self = shift;
    my %options = @_;

    $options{out_callback} = $self->build_callback( 'out', \%options );
    $options{err_callback} = $self->build_callback( 'err', \%options );

    return %options;
}

sub out_buffer {
    return join( '', @{shift->{out_buffer}} );
}

sub run {
    my $self = shift;
    my @command = @_;
    my %options = ();
    
    # if last arg is hashref, its command options not arg...
    if ( ref( $command[-1] ) eq 'HASH' ) {
        %options = $self->options( %{pop(@command)} );
    }
    
    $self->clear_buffers();

    return $self->{command_runner}->run_command( @command, \%options );
}

sub run_or_die {
    my $self = shift;
    my @command = @_;
    my %options = ();
    
    # if last arg is hashref, its command options not arg...
    if ( ref( $command[-1] ) eq 'HASH' ) {
        %options = $self->options( %{pop(@command)} );
    }

    $self->clear_buffers();

    my $exit_code = $self->{command_runner}->run_command( @command, \%options );
    if ( $exit_code ) {
        my $message = "FAILED ($exit_code): @command";
        $message .= " out_buffer=($self->{out_buffer})" if ( $options{out_buffer} );
        $message .= " err_buffer=($self->{err_buffer})" if ( $options{err_buffer} );
        die( $message );
    }
}

1;