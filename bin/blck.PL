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
# Copyright: GPL, Author: Guido Socher
#
use strict;
use vars qw($opt_a $opt_r $opt_W $opt_A $opt_h);
use Getopt::Std;
use HTML::TagReader;
#
sub help();
sub checkonefile($$);
sub checkonefile_nameonly($);
sub dirname($);
sub linktype($);
#
getopts("aAhr:W")||die "ERROR: No such option. -h for help.\n";
help() if ($opt_h);
help() unless ($ARGV[0]);

my %count=('rel'=>0,'abs'=>0);
my @checklater=();
my %named_anchors;
my %checkedfiles;
my $later=1;
if ($opt_A || $opt_a){
    $later=0;
}
for my $f (@ARGV){
    if ( -r "$f" ){
        checkonefile($f,$later);
    }else{
        warn "ERROR: can not read $f\n";
    }
}
if ($later){
    my $file;
    for my $anchorpath (@checklater){
        $file=$anchorpath->[0];
        $file=~s/\#.*//; # strip after '#'
        if ($checkedfiles{$file}){
            unless($named_anchors{$anchorpath->[0]}){
                print $anchorpath->[1]; # print error message
            }
        }else{
            # we have not read this file yet
            checkonefile_nameonly($file);
            unless($named_anchors{$anchorpath->[0]}){
                print $anchorpath->[1]; # print error message
            }
        }
    }
}
#
# check one file but add only named anchors to
# the %named_anchors
#
sub checkonefile_nameonly($){
    my $file=shift;
    my @tag;
    my ($path,$line);

    my $p=new HTML::TagReader "$file";
    $checkedfiles{"$file"}=1;
    while(@tag = $p->gettag(!$opt_W)){
        # read out the tags, note something like: 
        # <a name="xxxx" href="...."> .... </a>
        # is valid
        #
        # we search for " name": 
        next unless($tag[0]=~/ name/i); 
        # remove optional space before the equal sign:
        $tag[0]=~s/ ?= ?/=/g;
        $tag[0]=~s/^<//;
        $tag[0]=~s/>$//;
        $tag[0]=~s/[\"\']//g;
        $line=$tag[1];
        if ($tag[0]=~/ name=(\S+)/i){
            $path=$1;
            $named_anchors{$file."#".$path}=$line;
        }
    }
}
# 
# check exactly one file 
#
sub checkonefile($$){
    my $file=shift;
    my $later=shift; # whether or not to fill the checklater array
    my @tag;
    my $tagtype; # one of: name href src background
    my ($ckpath,$path,$ltype,$dir,$line,$origpath);

    my $p=new HTML::TagReader "$file";
    $checkedfiles{"$file"}=1;
    while(@tag = $p->gettag(!$opt_W)){
        # read out the tags, note something like: 
        # <a name="xxxx" href="...."> .... </a>
        # is valid
        #
        # we search for " name", " href", " src", " background": 
        next unless($tag[0]=~/ name| href| src| background/i); 
        # remove optional space before the equal sign:
        $tag[0]=~s/ ?= ?/=/g;
        $tag[0]=~s/^<//;
        $tag[0]=~s/>$//;
        $tag[0]=~s/[\"\']//g;
        $line=$tag[1];
        if ($tag[0]=~/ href=(\S+)/i){
            $tagtype='href';
            $path=$1;
            $ltype=linktype($path);
        }elsif ($tag[0]=~/ name=(\S+)/i){
            $path=$1;
            $named_anchors{$file."#".$path}=$line;
            next;
        }elsif ($tag[0]=~/ src=(\S+)/i){
            $tagtype='src';
            $path=$1;
            $ltype=linktype($path);
        }elsif ($tag[0]=~/ background=(\S+)/i){
            $tagtype='background';
            $path=$1;
            $ltype=linktype($path);
        }else{
            print "$file:$tag[1]: ERROR, invalid link $tag[0]\n" unless($opt_W);
        }
        $origpath=$path;
        #---
        if ($ltype eq 'rel' || $ltype eq 'anchor' ){
            $count{'rel'}++;
        }else{
            $count{'abs'}++;
        }
        if ($opt_r && $ltype eq "proto://"){
            if ($path=~/$opt_r/io){
                print "$file:$line: warning abs link to \"$path\"\n";
            }
        }
        if ($opt_a){
            if ($ltype eq "proto://" || $ltype eq "/absfile"){
                print "$file:$line: $tagtype=\"$path\"\n";
            }
            #
            # !! here we ignore the rest of this function
            #
            next;
        }
        #---
        if ($ltype eq 'anchor'){
            # add path (with file name) and possible error message:
            push(@checklater,[$file.$path,"$file:$line: reference to non existing anchor $tagtype=\"$path\"\n"]) if ($later);
            next;
        }
        if ($ltype eq 'absanchor'){
            next;
        }
        $dir=dirname($file);
        if ($path=~/^(.+)#/){
            $ckpath=$1;
            next if ($ltype ne 'rel');
            if ( -f "$dir/$ckpath" ){
                # ./index.html should be index.html
                $path=~s/\.\///;
                # add path and possible error message:
                push(@checklater,["$dir/$path","$file:$line: reference to non existing anchor $tagtype=\"$path\"\n"]) if ($later);
            }else{
                print "$file:$line: reference to non existing file $tagtype=\"$path\"\n";
            }
            next;
        }
        if ($ltype eq 'file:'){
            print "$file:$line: warning link with \"file:$path\"\n" unless($opt_W);
            next;
        }
        # handle cgi's:
        $ckpath=$path;
        $ckpath=~s/\?.*//;
        if ($ltype eq 'rel'){
            unless ( -f "$dir/$ckpath" || -d "$dir/$ckpath" ){
                print "$file:$line: broken link $tagtype=\"$path\"\n";
            }
        }
    }
}
#----------------------------------
# get the directory name from file name
sub dirname($){
    my $f=shift;
    if ($f=~m=/=){
        $f=~s=/[^/]*$==;
        return("$f");
    }else{
        return(".");
    }
}
#----------------------------------
# find out if this is an abs link (proto://, file:, rel, /absfile)
sub linktype($){
    my $pathstr=shift; # no quotes must be arround the path
    if ($pathstr=~ m=^/=){
        return('/absfile');
    }elsif ($pathstr=~ m=^\.=){
        return('rel'); # may still contain a ref to named anchor
    }elsif ($pathstr=~ m=^\#=){
        return('anchor'); # relative anchor in the same file!
    }elsif ($pathstr=~ m=^file:=i){
        return('file:');
    }elsif ($pathstr=~ m=^\w+://=i){
        return('proto://');
    }elsif ($pathstr=~ m=^\w+:=i){
        return('proto:'); # mailto: or javascript:
    }else{
        return('rel');
    }
}
#----------------------------------
sub help(){
print "blck -- check for broken relative links in html pages

USAGE: blck [-AhW] [-r regexp] html-files

blck searches html files for broken links. I searches
only the relative links and does not need a web-server. As
it does not need web-access it is very fast. The output of
blck  is of the same format as gcc error messages and
can therefore be interpreted by many common  editors  (e.g
emacs  or  vim).   After editing a some html pages you can
just type:
blck page1.html ../somewhere/page2.html
and blck will check that the links in these pages are
correct.

blck checks the relative filesystem links.  These are
links of the form:
href=\"index.html\"
href=\"../somepage.html#anchor1\"
etc...

but not
href=\"/notchecked.html\"
href=\"http://server.somewhere/something.html\"
href=\"javascript:history.back();\"

All tags containg relative links with  href=...,  src=...,
and background=...  are checked.

OPTIONS: -h this help
         -a print all links that were not checked (proto:// and
         absolute file system links starting with \'/\') and
         do not check for any broken links. This output can be
         processed further with httpcheck.
         -A do not open any other files than the files given on the
         -r warn about absolut links matching the given perl regexp
         E.g: -w \'www.linuxfocus.org|chem.pitt.edu\'
         This match is not case sensitive and only applied to links
         starting with proto:// (=absolut links).
         -W do not print warnings about html errors (not terminated
         tags etc ...).

EXAMPLE
       Check links in html files in the web server root directory
       (/home/httpd/html) and in all directories one level down:
       (cd /home/httpd/html; blck *.html */*.html)

       Check links in all html files on the server:
       (cd  /home/httpd/html;  blck  `find  . -name '*.htm*'
       -print` | sort)

       You  can  use  the  vim  editor  Quickfix  mode   or   the
       emacs/xemacs M-x compile to parse the output of blck.
       This gives you the possibility to open the  concerned  web
       page  and  jump directly to the line where the broken link
       is.  To do this you can write a Makefile that looks e.g as
       follows:

       all:
            blck `find . -name '*.htm*' -print` | sort


version $VERSION
         \n";
exit(0);
}
__END__ 

=head1 NAME

blck -- check for broken relative links in html pages

=head1 SYNOPSIS

    blck [-AhW] [-r regexp] html-files

=head1 DESCRIPTION

blck searches html files for broken links. I searches
only the relative links and does not need a web-server. As
it does not need web-access it is very fast. The output of
blck  is of the same format as gcc error messages and
can therefore be interpreted by many common  editors  (e.g
emacs  or  vim).   After editing a some html pages you can
just type:
blck page1.html ../somewhere/page2.html
and blck will check that the links in these pages are
correct.

blck checks the relative filesystem links.  These are
links of the form:
href="index.html"
href="../somepage.html#anchor1"
etc...

but not
href="/notchecked.html"
href="http://server.somewhere/something.html"
href="javascript:history.back();"

All tags containg relative links with  href=...,  src=...,
and background=...  are checked.

=head1 OPTIONS

-h short help message

-a print all links that were not checked (proto:// and
absolute file system links starting with \'/\') and
do not check for any broken links. This output can be
processed further with httpcheck.

-A do not open any other files than the files given on the

-r warn about absolut links matching the given perl regexp
E.g: -w \'www.linuxfocus.org|chem.pitt.edu\'
This match is not case sensitive and only applied to links
starting with proto:// (=absolut links).

-W do not print warnings about html errors (not terminated
tags etc ...).

=head1 EXAMPLE

Check links in html files in the web server root directory
(/home/httpd/html) and in all directories one level down:
(cd /home/httpd/html; blck *.html */*.html)

Check links in all html files on the server:
(cd  /home/httpd/html;  blck  `find  . -name '*.htm*'
-print` | sort)

You  can  use  the  vim  editor  Quickfix  mode   or   the
emacs/xemacs M-x compile to parse the output of blck.
This gives you the possibility to open the  concerned  web
page  and  jump directly to the line where the broken link
is.  To do this you can write a Makefile that looks e.g as
follows:

all:
    blck `find . -name '*.htm*' -print` | sort

=head1 AUTHOR

xlnk is part of the HTML::TagReader package and was written by
Guido Socher [guido(at)linuxfocus.org]


!NO!SUBS!

