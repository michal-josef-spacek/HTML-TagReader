use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
my @programs_to_install = qw(tr_blck tr_xlnk tr_llnk tr_mvlnk tr_httpcheck tr_staticssi tr_tagcontentgrep);

WriteMakefile(
    'NAME'	=> 'HTML::TagReader',
    'VERSION_FROM' => 'TagReader.pm', # finds $VERSION
    'PL_FILES'  => { map {("bin/$_.PL" => "bin/$_")} @programs_to_install },
    'EXE_FILES' => [ map {"bin/$_"} @programs_to_install ],
    'clean'     => { FILES => '$(EXE_FILES)' },
    'LIBS'	=> [''],   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> '',     # e.g., '-I/usr/include/other' 
    dist    => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
);
