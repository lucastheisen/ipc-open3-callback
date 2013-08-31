use strict;
use warnings;

use Test::More tests => 13;

BEGIN { use_ok('IPC::Open3::Callback::Command') };

use IPC::Open3::Callback::Command qw(command batch_command mkdir_command pipe_command rm_command sed_command);
is( command( 'echo' ), 'echo', 'command' );
is( command( 'echo', {hostname=>'foo'} ), 'ssh foo "echo"', 'remote command' );
is( command( 'echo', {username=>'bar',hostname=>'foo'} ), 'ssh bar@foo "echo"', 'remote command as user' );
is( command( 'echo', {username=>'bar',hostname=>'foo',ssh=>'plink'} ), 'plink -l bar foo "echo"', 'plink command as user' );
is( batch_command( 'cd foo', 'cd bar' ), 'cd foo;cd bar', 'batch cd foo then bar' );
is( batch_command( 'cd foo', 'cd bar', {hostname=>'baz'} ), 'ssh baz "cd foo;cd bar"', 'remote batch cd foo then bar' );
is( batch_command( 'cd foo', 'cd bar', {hostname=>'baz',command_prefix=>'sudo '} ), 'ssh baz "sudo cd foo;sudo cd bar"', 'remote batch sudo cd foo then bar' );
is( mkdir_command( 'foo', 'bar', {hostname=>'baz'} ), 'ssh baz "mkdir -p \\"foo\\" \\"bar\\""', 'remote mkdirs foo and bar' );
is( pipe_command( 
        'cat abc', 
        command( 'dd of=def', {hostname=>'baz'} ) 
    ), 
    'cat abc|ssh baz "dd of=def"', 
    'pipe cat to remote dd' );
is( rm_command( 'foo', 'bar', {username=>'fred',hostname=>'baz',command_prefix=>'sudo -u joe '} ), 
    'ssh fred@baz "sudo -u joe rm -rf \\"foo\\" \\"bar\\""', 
    'remote sudo rm' );
is( sed_command( 's/foo/bar/' ), 'sed -e \'s/foo/bar/\'', 'simple sed' );
is( batch_command(
        pipe_command( 
            'curl http://www.google.com',
            sed_command( {replace_map=>{google=>'gaggle'}} ),
            command( 'dd of="/tmp/gaggle.com"', {username=>'fred',hostname=>'baz',command_prefix=>'sudo -u joe '} )
        ),
        rm_command( '/tmp/google.com', {username=>'fred',hostname=>'baz',command_prefix=>'sudo -u joe '}) 
    ),
    'curl http://www.google.com|sed -e \'s/google/gaggle/g\'|ssh fred@baz "sudo -u joe dd of=\"/tmp/gaggle.com\"";ssh fred@baz "sudo -u joe rm -rf \"/tmp/google.com\""',
    'crazy command' );