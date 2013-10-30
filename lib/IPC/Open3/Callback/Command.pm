#!/usr/local/bin/perl

use strict;
use warnings;

package IPC::Open3::Callback::Command;

use Exporter qw(import);
our @EXPORT_OK = qw(command batch_command mkdir_command pipe_command rm_command sed_command);

sub batch_command {
    wrap(
        {},
        @_,
        sub {
            my $options = shift;
            return @_;
        }
    );
}

sub command {
    wrap(
        {},
        @_,
        sub {
            my $options = shift;
            return shift;
        }
    );
}

sub mkdir_command {
    wrap(
        {},
        @_,
        sub {
            my $options = shift;
            return 'mkdir -p "' . join( '" "', @_ ) . '"';
        }
    );
}

sub pipe_command {
    wrap(
        { command_separator => '|' },
        @_,
        sub {
            my $options = shift;
            return @_;
        }
    );
}

sub rm_command {
    wrap(
        {},
        @_,
        sub {
            my $options = shift;
            return 'rm -rf "' . join( '" "', @_ ) . '"';
        }
    );
}

sub sed_command {
    wrap(
        {},
        @_,
        sub {
            my $options = shift;

            my $command = 'sed';
            $command .= ' -i' if ( $options->{in_place} );
            if ( defined( $options->{temp_script_file} ) ) {
                my $temp_script_file_name = $options->{temp_script_file}->filename();
                print( { $options->{temp_script_file} } join( ' ', '', map {"$_;"} @_ ) )
                    if ( scalar(@_) );
                print(
                    { $options->{temp_script_file} } join( ' ',
                        '',
                        map {"s/$_/$options->{replace_map}{$_}/g;"}
                            keys( %{ $options->{replace_map} } ) )
                ) if ( defined( $options->{replace_map} ) );
                $options->{temp_script_file}->flush();
                $command .= " -f $temp_script_file_name";
            }
            else {
                $command .= join( ' ', '', map {"-e '$_'"} @_ ) if ( scalar(@_) );
                $command .= join( ' ',
                    '',
                    map {"-e 's/$_/$options->{replace_map}{$_}/g'"}
                        keys( %{ $options->{replace_map} } ) )
                    if ( defined( $options->{replace_map} ) );
            }
            $command .= join( ' ', '', @{ $options->{files} } ) if ( $options->{files} );

            return $command;
        }
    );
}

# Handles wrapping commands with possible ssh and command prefix
sub wrap {
    my $wrap_options = shift;
    my $builder      = pop;
    my $options      = pop;
    my @args         = @_;
    my ( $ssh, $username, $hostname );
    my $command_prefix = '';

    if ( ref($options) eq 'HASH' ) {
        $ssh      = $options->{ssh} || 'ssh';
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
    my $command_separator   = $wrap_options->{command_separator} || ';';
    my $first               = 1;
    foreach my $command ( &$builder( $options, @args ) ) {
        if ( defined($command) ) {
            if ($first) {
                $first = 0;
            }
            else {
                $destination_command .= $command_separator;
                if ( $options->{pretty} ) {
                    $destination_command .= "\n";
                }
            }
            $command =~ s/^(.*?);$/$1/;
            $destination_command .= "$command_prefix$command";
        }
    }

    if ( !defined($username) && !defined($hostname) ) {

        # silly to ssh to localhost as current user, so dont
        return $destination_command;
    }

    my $userAt =
        defined( $options->{username} )
        ? (
        ( $ssh =~ /plink(?:\.exe)?$/ ) ? "-l $options->{username} " : "$options->{username}\@" )
        : '';

    $destination_command =~ s/\\/\\\\/g;
    $destination_command =~ s/"/\\"/g;
    return "$ssh $userAt" . ( $hostname || 'localhost' ) . " \"$destination_command\"";
}

1;
__END__
=head1 NAME

IPC::Open3::Callback::Command - A utility class that provides subroutines for building shell command strings.

=head1 SYNOPSIS

  use IPC::Open3::Callback::Command qw(command batch_command mkdir_command pipe_command rm_command sed_command);
  my $command = command( 'echo' ); # echo

  # ssh foo "echo"
  $command = command( 'echo', {hostname=>'foo'} ); 

  # ssh bar@foo "echo"
  $command = command( 'echo', {username=>'bar',hostname=>'foo'} ); 
  
  # plink -l bar foo "echo"
  $command = command( 'echo', {username=>'bar',hostname=>'foo',ssh=>'plink'} ); 
  
  # cd foo;cd bar
  $command = batch_command( 'cd foo', 'cd bar' ); 
  
  # ssh baz "cd foo;cd bar"
  $command = batch_command( 'cd foo', 'cd bar', {hostname=>'baz'} ); 
  
  # ssh baz "sudo cd foo;sudo cd bar"
  $command = batch_command( 'cd foo', 'cd bar', {hostname=>'baz',command_prefix=>'sudo '} ); 
  
  # ssh baz "mkdir -p \"foo\" \"bar\""
  $command = mkdir_command( 'foo', 'bar', {hostname=>'baz'} ); 

  # cat abc|ssh baz "dd of=def"
  $command = pipe_command( 
          'cat abc', 
          command( 'dd of=def', {hostname=>'baz'} ) 
      ); 

  # ssh fred@baz "sudo -u joe rm -rf \"foo\" \"bar\""
  $command = rm_command( 'foo', 'bar', {username=>'fred',hostname=>'baz',command_prefix=>'sudo -u joe '} ); 
  
  # sed -e 's/foo/bar/'
  $command = sed_command( 's/foo/bar/' ); 
  
  
  # curl http://www.google.com|sed -e 's/google/gaggle/g'|ssh fred@baz "sudo -u joe dd of=\"/tmp/gaggle.com\"";ssh fred@baz "sudo -u joe rm -rf \"/tmp/google.com\"";
  $command = batch_command(
          pipe_command( 
              'curl http://www.google.com',
              sed_command( {replace_map=>{google=>'gaggle'}} ),
              command( 'dd of="/tmp/gaggle.com"', {username=>'fred',hostname=>'baz',command_prefix=>'sudo -u joe '} )
          ),
          rm_command( '/tmp/google.com', {username=>'fred',hostname=>'baz',command_prefix=>'sudo -u joe '}) 
      );

=head1 DESCRIPTION

The subroutines exported by this module can build shell command strings that
can be executed by IPC::Open3::Callback, IPC::Open3::Callback::CommandRunner,
``, system(), or even plain old open 1, 2, or 3.  There is not much
point to I<shelling> out for commands locally as there is almost certainly a
perl function/library capable of doing whatever you need in perl code. However,
If you are designing a footprintless agent that will run commands on remote
machines using existing tools (gnu/powershell/bash...) these utilities can be
very helpful.  All functions in this module can take a C<\%destination_options>
hash defining who/where/how to run the command.

=head1 FUNCTIONS

All commands can be supplied with C<\%destination_options>.  
C<destination_options> control who/where/how to run the command.  The supported
options are:

=over 4

=item ssh

The ssh command to use, defaults to C<ssh>.  You can use this to specify other
commands like C<plink> for windows or an implementation of C<ssh> that is not
in your path.

=item command_prefix

As it sounds, this is a prefix to your command.  Mainly useful for using 
C<sudo>. This prefix is added like this C<$command_prefix$command> so be sure
to put a space at the end of your prefix unless you want to modify the name
of the command itself.  For example, 
C<$command_prefix = 'sudo -u priveleged_user ';>.

=item username

The username to C<ssh> with. If using C<ssh>, this will result in, 
C<ssh $username@$hostname> but if using C<plink> it will result in 
C<plink -l $username $hostname>.

=item hostname

The hostname/IP of the server to run this command on. If localhost, and no 
username is specified, the command will not be wrapped in C<ssh>

=back

=head2 command( $command, \%destination_options )

This wraps the supplied command with all the destination options.  If no 
options are supplied, $command is returned.

=head2 batch_command( $command1, $command2, ..., $commandN, \%destination_options )

This will join all the commands with a C<;> and apply the supplied 
C<\%destination_options> to the result.

=head2 mkdir_command( $path1, $path2, ..., $pathN, \%destination_options )

Results in C<mkdir -p $path1 $path2 ... $pathN> with the 
C<\%destination_options> applied.

=head2 pipe_command( $command1, $command2, ..., $commandN, \%destination_options )

Identical to 
L<batch_command|"batch_command( $command1, $command2, ..., $commandN, \%destination_options )">
except uses C<\|> to separate the commands instead of C<;>.

=head2 rm_command( $path1, $path2, ..., $pathN, \%destination_options )

Results in C<rm -rf $path1 $path2 ... $pathN> with the 
C<\%destination_options> applied. This is a I<VERY> dangerous command and should
be used with care.

=head2 sed_command( $expression1, $expression2, ..., $expressionN, \%destination_options )

Constructs a sed command

=over 4

=item files

An arrayref of files to apply the sed expressions to.  For use when not piping
from another command.

=item in_place

If specified, the C<-i> option will be supplied to C<sed> thus modifying the
file argument in place. Not useful for piping commands together, but can be 
useful if you copy a file to a temp directory, modify it in place, then 
transfer the file and delete the temp directory.  It would be more secure to 
follow this approach when using sed to fill in passwords in config files. For
example, if you wanted to use sed substitions to set passwords in a config file
template and then transfer that config file to a remote server:

C</my/config/passwords.cfg>

  app1.username=foo
  app1.password=##APP1_PASSWORD##
  app2.username=bar
  app2.password=##APP2_PASSWORD##

C<deploy_passwords.pl>

  use IPC::Open3::Callback::Command qw(batch_command command pipe_command sed_command);
  use IPC::Open3::Callback::CommandRunner;
  use File::Temp;
  
  my $temp_dir = File::Temp->newdir();
  my $temp_script_file = File::Temp->new();
  IPC::Open3::Callback::CommandRunner->new()->run_or_die(
      batch_command( 
          "cp /my/config/passwords.cfg $temp_dir->filename()/passwords.cfg",
          sed_command( 
              "s/##APP1_PASSWORD##/set4app1/g",
              "s/##APP2_PASSWORD##/set4app2/g", 
              {
                  in_place=>1,
                  temp_script_file=>$temp_script_file,
                  files=>[$temp_dir->filename()/passwords.cfg] 
              } 
          ),
          pipe_command( 
              "cat $temp_dir->filename()/passwords.cfg",
              command( "dd of='/remote/config/passwords.cfg'", {hostname=>'remote_host'} ) );
      )
  );

=item replace_map

A map used to construct a sed expression where the key is the match portion 
and the value is the replace portion. For example: C<{'key'=E<gt>'value'}> would 
result in C<'s/key/value/g'>.

=item temp_script_file

Specifies a file to write the sed script to rather than using the console.  
This is useful for avoiding generating commands that would get executed in the 
console that have protected information like passwords. If passwords are 
issued on the console, they might show up in the command history...

=back

=head1 AUTHOR

=over

=item *

Lucas Theisen E<lt>lucastheisen@pastdev.comE<gt>

=back

=head1 COPYRIGHT

Copyright 2013 pastdev.com.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

