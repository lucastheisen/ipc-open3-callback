#!/usr/local/bin/perl

package IPC::Open3::Callback::Command;

use strict;
use warnings;

our (@ISA, @EXPORT_OK);
BEGIN {
    require Exporter;
    @ISA = qw(Exporter);
    @EXPORT_OK = qw(command batchCommand mkdirCommand pipeCommand rmCommand sedCommand);
};

sub batchCommand {
    wrap( {}, @_, sub {
        my $options = shift;
        return @_;
    } );
}

sub command {
    wrap( {}, @_, sub {
        my $options = shift;
        return shift;
    } );
}

sub mkdirCommand {
    wrap( {}, @_, sub {
        my $options = shift;
        return 'mkdir -p "' . join( '" "', @_ ) . '"';
    } );
}

sub pipeCommand {
    wrap( { commandSeparator => '|' }, @_, sub {
        my $options = shift;
        return @_;
    } );
}

sub rmCommand {
    wrap( {}, @_, sub {
        my $options = shift;
        return 'rm -rf "' . join( '" "', @_ ) . '"';
    } );
}

sub sedCommand {
    wrap( {}, @_, sub {
        my $options = shift;
        
        my $command = 'sed';
        $command .= ' -i' if ( $options->{inPlace} );
        if ( defined( $options->{tempScriptFile} ) ) {
            my $tempScriptFileName = $options->{tempScriptFile}->filename();
            print( {$options->{tempScriptFile}} join( ' ', '', map { "$_;" } @_ ) ) if ( scalar( @_ ) );
            print( {$options->{tempScriptFile}} join( ' ', '', map { "s/$_/$options->{replaceMap}{$_}/g;" } keys( %{$options->{replaceMap}} ) ) ) if ( defined( $options->{replaceMap} ) );
            $options->{tempScriptFile}->flush();
            $command .= " -f $tempScriptFileName";
        }
        else {
            $command .= join( ' ', '', map { "-e '$_'" } @_ ) if ( scalar( @_ ) );
            $command .= join( ' ', '', map { "-e 's/$_/$options->{replaceMap}{$_}/g'" } keys( %{$options->{replaceMap}} ) ) if ( defined( $options->{replaceMap} ) );
        }
        $command .= join( ' ', '', @{$options->{files}} ) if ( $options->{files} );
        
        return $command;
    } );
}

# Handles wrapping commands with possible ssh and command prefix
sub wrap {
    my $wrapOptions = shift;
    my $builder = pop;
    my $options = pop;
    my @args = @_;
    my ($ssh, $username, $hostname);
    my $commandPrefix = '';

    if ( ref( $options ) eq 'HASH' ) {
        $ssh = $options->{ssh} || 'ssh';
        $username = $options->{username};
        $hostname = $options->{hostname};
        if ( defined( $options->{commandPrefix} ) ) {
            $commandPrefix = $options->{commandPrefix};
        }
    }
    else {
        push( @args, $options );
        $options = {};
    }

    my $destinationCommand = '';
    my $commandSeparator = $wrapOptions->{commandSeparator} || ';';
    my $first = 1;
    foreach my $command ( &$builder( $options, @args ) ) {
        if ( defined( $command ) ) {
            if ( $first ) {
                $first = 0;
            }
            else {
                $destinationCommand .= $commandSeparator;
                if ( $options->{pretty} ) {
                    $destinationCommand .= "\n"
                }
            }
            $command =~ s/^(.*?);$/$1/;
            $destinationCommand .= "$commandPrefix$command";
        }
    }
    
    if ( !defined( $username ) && !defined( $hostname ) ) {
        # silly to ssh to localhost as current user, so dont
        return $destinationCommand;
    }
    
    my $userAt = defined( $options->{username} ) ? 
        (($ssh =~ /plink(?:\.exe)$/ ) ? "-l $options->{username} " : "$options->{username}\@") : 
        '';
        
    $destinationCommand =~ s/\\/\\\\/g;
    $destinationCommand =~ s/"/\\"/g;
    return "$ssh $userAt" . ($hostname || 'localhost' ) . " \"$destinationCommand\"";
}

1;