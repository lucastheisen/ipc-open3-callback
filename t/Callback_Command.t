use strict;
use warnings;

use Test::More tests => 23;

BEGIN { use_ok('IPC::Open3::Callback::Command') }

use IPC::Open3::Callback::Command
    qw(batch_command command command_options  mkdir_command pipe_command rm_command sed_command write_command);

is( command('echo'), 'echo', 'command' );
is( command( 'echo', command_options( hostname => 'foo' ) ), 'ssh foo "echo"', 'remote command' );
is( command( 'echo', command_options( username => 'bar', hostname => 'foo' ) ),
    'ssh bar@foo "echo"',
    'remote command as user'
);
is( command( 'echo', command_options( username => 'bar', hostname => 'foo', ssh => 'plink' ) ),
    'plink -l bar foo "echo"',
    'plink command as user'
);
is( batch_command( 'cd foo', 'cd bar' ), 'cd foo;cd bar', 'batch cd foo then bar' );
is( batch_command( 'cd foo', 'cd bar', command_options( hostname => 'baz' ) ),
    'ssh baz "cd foo;cd bar"',
    'remote batch cd foo then bar'
);
is( batch_command( 'cd foo', 'cd bar', command_options( hostname => 'baz', sudo_username => '' ) ),
    'ssh baz "sudo bash -c \"cd foo;cd bar\""',
    'remote batch sudo cd foo then bar'
);
is( mkdir_command( 'foo', 'bar', command_options( hostname => 'baz' ) ),
    'ssh baz "mkdir -p \\"foo\\" \\"bar\\""',
    'remote mkdirs foo and bar'
);
is( pipe_command( 'cat abc', command( 'dd of=def', command_options( hostname => 'baz' ) ) ),
    'cat abc|ssh baz "dd of=def"',
    'pipe cat to remote dd'
);
is( rm_command(
        'foo', 'bar', command_options( username => 'fred', hostname => 'baz', sudo_username=> 'joe' )
    ),
    'ssh fred@baz "sudo -u joe bash -c \\"rm -rf \\\\\\"foo\\\\\\" \\\\\\"bar\\\\\\"\\""',
    'remote sudo rm'
);
is( sed_command('s/foo/bar/'), 'sed -e \'s/foo/bar/\'', 'simple sed' );
is( batch_command(
        pipe_command(
            'curl http://www.google.com',
            sed_command( { replace_map => { google => 'gaggle' } } ),
            command(
                'dd of="/tmp/gaggle.com"',
                command_options( username => 'fred', hostname => 'baz', sudo_username => 'joe' )
            )
        ),
        rm_command(
            '/tmp/google.com',
            command_options( username => 'fred', hostname => 'baz', sudo_username => 'joe' )
        )
    ),
    'curl http://www.google.com|sed -e \'s/google/gaggle/g\'|ssh fred@baz "sudo -u joe bash -c \"dd of=\\\\\\"/tmp/gaggle.com\\\\\\"\"";ssh fred@baz "sudo -u joe bash -c \"rm -rf \\\\\\"/tmp/google.com\\\\\\"\""',
    'crazy command'
);
is( write_command( 'skeorules.reasons', 'good looks', 'smarts', 'cool shoes, not really' ),
    'printf "good looks\nsmarts\ncool shoes, not really"|dd of=skeorules.reasons',
    'write command'
);
is( write_command( 'skeorules.reasons', 'good looks', 'smarts', 'cool shoes, not really', 
        command_options( 
            hostname => 'somewhere-out-there', 
            sudo_username => 'over-the-rainbow'
        ) ),
    'printf "good looks\\nsmarts\\ncool shoes, not really"|ssh somewhere-out-there "sudo -u over-the-rainbow bash -c \"dd of=skeorules.reasons\""',
    'write command with command_options'
);
is( write_command( 'skeorules.reasons', 'good looks', 'smarts', 'cool shoes, not really', 
        { mode => 700 },
        command_options( 
            hostname => 'somewhere-out-there', 
            sudo_username => 'over-the-rainbow'
        ) ),
    'printf "good looks\\nsmarts\\ncool shoes, not really"|ssh somewhere-out-there "sudo -u over-the-rainbow bash -c \"dd of=skeorules.reasons;chmod 700 skeorules.reasons\""',
    'write command with mode'
);
is( write_command( 'skeorules.reasons', 'good looks', 'smarts', 'cool shoes, not really', 
        { mode => 700, line_separator => '\r\n' },
        command_options( 
            hostname => 'somewhere-out-there', 
            sudo_username => 'over-the-rainbow'
        ) ),
    'printf "good looks\\r\\nsmarts\\r\\ncool shoes, not really"|ssh somewhere-out-there "sudo -u over-the-rainbow bash -c \"dd of=skeorules.reasons;chmod 700 skeorules.reasons\""',
    'write command with line_separator'
);
is( write_command( 'skeorules.reasons', "good\\nlooks", 'smarts', 'cool shoes, not really', 
        { mode => 700, line_separator => '\r\n' },
        command_options( 
            hostname => 'somewhere-out-there', 
            sudo_username => 'over-the-rainbow'
        ) ),
    'printf "good\\nlooks\\r\\nsmarts\\r\\ncool shoes, not really"|ssh somewhere-out-there "sudo -u over-the-rainbow bash -c \"dd of=skeorules.reasons;chmod 700 skeorules.reasons\""',
    'write command with embedded newline'
);
is( command( "find . -exec cat {} \\;" ),
    'find . -exec cat {} \;',
    'wrap doesn\'t remove ;' );
is( batch_command( "echo abc;", "echo def;" ),
    'echo abc;echo def',
    'wrap does remove ;' );
ok( command_options( hostname=>'localhost' )->is_local(),
    'localhost is local' );
ok( command_options( hostname=>'127.0.0.1' )->is_local(),
    '127.0.0.1 is local' );
ok( !command_options( hostname=>'google.com' )->is_local(),
    'google.com is not local (sorry google, force install if you decide to use this module)' );
