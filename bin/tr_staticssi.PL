#!/usr/bin/perl
use Config;
# vim: set sw=4 ts=4 si et:
use File::Basename qw(basename dirname);
chdir(dirname($0));
($file = basename($0)) =~ s/\.PL$//;
$file =~ s/\.pl$//
        if ($Config{'osname'} eq 'VMS' or
            $Config{'osname'} eq 'OS2');  # "case-forgiving"
open OUT,">$file" or die "Can't create $file: $!";
chmod(0755, $file);
print "Extracting $file (with variable substitutions)\n";

my $VERSION="unknown";
if (-r "../TagReader.pm"){ # get version
    open(F,"../TagReader.pm")||die;
    while(<F>){
        if (/\$VERSION *= *(.+)/){
            $VERSION=$1;
            $VERSION=~s/[^\.\d]//g;
        }
    }
    close F;
}

print OUT "$Config{'startperl'} -w
my \$VERSION = \"$VERSION\";
";


print OUT <<'!NO!SUBS!';
# vim: set sw=4 ts=4 si et:
# Copyright: Guido Socher
#
use strict;
use vars qw($opt_d $opt_t $opt_h);
use Getopt::Std;
use IO::File;
use HTML::TagReader;
#
sub expandssi($);
sub readssifiles($$$$);
sub help();
#
getopts("d:h")||die "ERROR: tr_staticssi, No such option. -h for help.\n";
help() if ($opt_h);
die "ERROR: tr_staticssi option -d missing, -h for help\n" unless ($opt_d);
help() unless ($ARGV[0]);
$opt_d=~s=/$==; # kill tailing slash
( -d $opt_d ) || die "ERROR: tr_staticssi, $opt_d is not a directory\n";
my @docs;
my ($uri,$dn);
# 
push(@docs,$ARGV[0]);
#
for (@docs){
    unless(/\w/){
        die "ERROR: invalid file name $_\n";
    }
    unless(/htm/i){
        die "ERROR: not a html file: $_\n";
    }
    $uri =$_;
    $dn=$uri;
    $dn=~s=^.+/==; # basename
    $ENV{'DOCUMENT_URI'}=$uri;
    $ENV{'REQUEST_URI'}=$uri;
    $ENV{'DOCUMENT_NAME'}=$dn;
    expandssi($uri);
}
#
sub expandssi($){
    my $file=shift;
    my $outfh=new IO::Handle;
    $outfh->fdopen(fileno(STDOUT),"w")||die "ERROR: can not write to stdout\n";
    chdir $opt_d || die "ERROR: tr_staticssi, expandssi, can not chdir to $opt_d\n";
    readssifiles($file,$outfh,0,$file);
    $outfh->close();
}

sub readssifiles($$$$){
    my $file=shift; 
    my $outfh=shift; 
    my $count=shift; # recursion count
    my $firstfile=shift; 
    my $incl;
    if ($count > 0 && $file=~m!^/!){ # abs path is relative to docroot
        $file=$opt_d ."/".$file;
    }
    $count++;
    return 0 if ($count > 3);
    unless( -f "$file"){
        print STDERR "WARNING: tr_staticssi, not a file $file, ssi ignored, while working on $firstfile\n"; 
        return 0;
    }
    my $sourcedirname="$file";
    my $basename="$file";
    $basename=~s=^.+/==;
    if ($sourcedirname=~m=/=){
        $sourcedirname=~s=/[^/]+$==;
    }else{
        $sourcedirname="."; # stay here
    }
    #
    chdir $sourcedirname || die "ERROR: tr_staticssi, readssifiles, can not chdir to $sourcedirname, while working on $firstfile\n";

    my $p=new HTML::TagReader "$basename";
    die "ERROR: tr_staticssi, can not read $basename, while working on $firstfile\n" unless( -r "$basename");
    my @tag;
    while(@tag = $p->getbytoken(0)){
        # read out the tags
        unless($tag[1] eq "!--"){
            # just print
            $outfh->print($tag[0]);
            next;
        }
        # only comment tags after this line
        my $fastsearch=substr($tag[0],0,20);
        unless($fastsearch=~/include|exec/){
            $outfh->print($tag[0]);
            next;
        }
        $tag[0]=~s/\s+/ /g;
        if ($tag[0]=~/\#include virtual=(\S+)/){
            $incl=$1;
            $incl=~s/^['"]//;
            $incl=~s/['"]$//;
            if ($incl){
                $outfh->print("<!-- tr_staticssi include virtual -->\n"); 
                readssifiles($incl,$outfh,$count,$firstfile);
            }else{
                $outfh->print("<pre>\n tr_staticssi include error: no file\n</pre>\n");
            }
        }else{
            if ($tag[0]=~/\#exec cmd="([^"]+)"/){
                $incl=$1;
            }elsif ($tag[0]=~/\#exec cmd='([^']+)'/){
                $incl=$1;
            }else{
                $incl=0;
            }
            if ($incl){
                $outfh->print("<!-- tr_staticssi exec cmd -->\n");
                my $txt=`$incl`;
                if ($?){
                    $outfh->print("<pre>\n tr_staticssi exec error: $@ \n</pre>\n");
                }else{
                    $outfh->print("$txt");
                }
            }else{
                $outfh->print($tag[0]);
            }
        }
    }
}
#
sub help(){
print "tr_staticssi -- expand SSI directives #include virtual and #exec cmd
USAGE: tr_staticssi[-h] -d doc-root-directory file.shtml

OPTIONS: 
   -h this help
   -d the path to webserver document root directory

tr_staticssi reads a file below doc-root-directory and expands SSI
directives (#include virtual and #exec cmd). Nested directives up to
level 3 are supported.  The expanded document is printed to stdout.

This program sets the environment variables DOCUMENT_URI, REQUEST_URI,
DOCUMENT_NAME.

The SSI must look like this:
<!--#include virtual=\"filename\" -->
<!--#exec cmd=\"command\" -->

The program is useful if you want to generate static html pages
from dynamic html.

EXAMPLE: 
tr_staticssi -d /home/httpd/html index.shtml > expand.html

tr_staticssi is part of the HTML::TagReader package.

\n";
exit;
}
__END__ 

=head1 NAME

tr_staticssi -- expand SSI directives #include virtual and #exec cmd

=head1 SYNOPSIS

    tr_staticssi[-h] -d doc-root-directory file.shtml

=head1 DESCRIPTION

tr_staticssi reads a file below doc-root-directory and expands SSI
directives (#include virtual and #exec cmd). Nested directives up to
level 3 are supported.  The expanded document is printed to stdout.

This program sets the environment variables DOCUMENT_URI, REQUEST_URI,
DOCUMENT_NAME.

The SSI must look like this:

<!--#include virtual="filename" -->

<!--#exec cmd="command" -->

The program is useful if you want to generate static html pages
from dynamic html.

=head1 OPTIONS

B<-h> short  help

B<-d> the path to webserver document root directory

=head1 EXAMPLE

cd /home/httpd/html

tr_staticssi -d /home/httpd/html index.shtml > expand.html

This will expand include and exec directives in index.shtml.

=head1 AUTHOR

tr_staticssi is part of the HTML::TagReader package and was written by
Guido Socher [guido(at)linuxfocus.org]

=cut
!NO!SUBS!

