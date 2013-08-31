#!/usr/local/bin/perl

package IPC::Open3::Callback::Command;

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(command batch_command mkdir_command pipe_command rm_command sed_command);

sub batch_command {
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

sub mkdir_command {
    wrap( {}, @_, sub {
        my $options = shift;
        return 'mkdir -p "' . join( '" "', @_ ) . '"';
    } );
}

sub pipe_command {
    wrap( { command_separator => '|' }, @_, sub {
        my $options = shift;
        return @_;
    } );
}

sub rm_command {
    wrap( {}, @_, sub {
        my $options = shift;
        return 'rm -rf "' . join( '" "', @_ ) . '"';
    } );
}

sub sed_command {
    wrap( {}, @_, sub {
        my $options = shift;
        
        my $command = 'sed';
        $command .= ' -i' if ( $options->{in_place} );
        if ( defined( $options->{temp_script_file} ) ) {
            my $temp_script_file_name = $options->{temp_script_file}->filename();
            print( {$options->{temp_script_file}} join( ' ', '', map { "$_;" } @_ ) ) if ( scalar( @_ ) );
            print( {$options->{temp_script_file}} join( ' ', '', map { "s/$_/$options->{replace_map}{$_}/g;" } keys( %{$options->{replace_map}} ) ) ) if ( defined( $options->{replace_map} ) );
            $options->{temp_script_file}->flush();
            $command .= " -f $temp_script_file_name";
        }
        else {
            $command .= join( ' ', '', map { "-e '$_'" } @_ ) if ( scalar( @_ ) );
            $command .= join( ' ', '', map { "-e 's/$_/$options->{replace_map}{$_}/g'" } keys( %{$options->{replace_map}} ) ) if ( defined( $options->{replace_map} ) );
        }
        $command .= join( ' ', '', @{$options->{files}} ) if ( $options->{files} );
        
        return $command;
    } );
}

# Handles wrapping commands with possible ssh and command prefix
sub wrap {
    my $wrap_options = shift;
    my $builder = pop;
    my $options = pop;
    my @args = @_;
    my ($ssh, $username, $hostname);
    my $command_prefix = '';

    if ( ref( $options ) eq 'HASH' ) {
        $ssh = $options->{ssh} || 'ssh';
        $username = $options->{username};
        $hostname = $options->{hostname};
        if ( defined( $options->{command_prefix} ) ) {
            $command_prefix = $options->{command_prefix};
        }
    }
    else {
        push( @args, $options );
        $options = {};
    }

    my $destination_command = '';
    my $command_separator = $wrap_options->{command_separator} || ';';
    my $first = 1;
    foreach my $command ( &$builder( $options, @args ) ) {
        if ( defined( $command ) ) {
            if ( $first ) {
                $first = 0;
            }
            else {
                $destination_command .= $command_separator;
                if ( $options->{pretty} ) {
                    $destination_command .= "\n"
                }
            }
            $command =~ s/^(.*?);$/$1/;
            $destination_command .= "$command_prefix$command";
        }
    }
    
    if ( !defined( $username ) && !defined( $hostname ) ) {
        # silly to ssh to localhost as current user, so dont
        return $destination_command;
    }
    
    my $userAt = defined( $options->{username} ) ? 
        (($ssh =~ /plink(?:\.exe)$/ ) ? "-l $options->{username} " : "$options->{username}\@") : 
        '';
        
    $destination_command =~ s/\\/\\\\/g;
    $destination_command =~ s/"/\\"/g;
    return "$ssh $userAt" . ($hostname || 'localhost' ) . " \"$destination_command\"";
}

1;