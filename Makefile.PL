use 5.010001; # 5.014002;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'IPC::Open3::Callback',
    VERSION_FROM      => 'lib/IPC/Open3/Callback.pm', # finds $VERSION
    PREREQ_PM         => { 'IPC::Open3' => 1.01 }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/IPC/Open3/Callback.pm', # retrieve abstract from module
       AUTHOR         => 'Lucas Theisen <lucastheisen@pastdev.com>') : ()),
);
