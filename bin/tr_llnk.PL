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
use vars qw($opt_l $opt_a $opt_h $opt_A $opt_W $opt_i);
use Getopt::Std;
use HTML::TagReader;
#
sub help();
sub showonefile($);
sub linktype($);
sub dirname($);
sub flattenpath($);
#
my @possibilities= qw(index.html index.htm index.shtml default.htm index.php3 index.php index.wml);
my %killduplicate;
#
getopts("haAlWi:")||die "ERROR: No such option. -h for help.\n";
help() if ($opt_h);
help() unless ($ARGV[0]);
if ($opt_a){
    $opt_l=1;
}
if ($opt_i){
    @possibilities=split(/,/,$opt_i);
}
for my $f (@ARGV){
    if ( -r "$f" ){
        showonefile($f);
    }else{
        warn "ERROR: can not read $f\n";
    }
}
# 
# list tags in exactly one file 
#
sub showonefile($){
    my $infile=shift;
    my @tag;
    my $linktype; # one of: name href src background
    my ($waitclosetag,$origtag,$aline,$atag,$path,$tmp,$ltype,$line,$waitcount,$dir,$ckpath);

    my $p=new HTML::TagReader "$infile";
    print "$infile\n" unless($opt_l);
    $waitclosetag=0;
    $waitcount=0;
    $atag="";
    while(@tag = $p->getbytoken(!$opt_W)){
        # read out the tags, note something like: 
        # <a name="xxxx" href="...."> .... </a>
        # is valid
        #
        $origtag=$tag[0];
        if($tag[1] eq "" || $tag[1] eq "!--"){ # not a tag, but text or a comment
            if ($waitclosetag && $opt_a){
                $atag.=$tag[0];
            }
            next;
        } 
        if ($waitclosetag){
            $tag[0]=~s/\s+/ /g; # kill newline and double space
            $atag.=$tag[0];
            $waitcount++;
            if ($tag[1] eq "/a"){
                $waitclosetag=0;
                print "$infile:$aline: $atag\n";
                $atag="";
                next;
            }
            if ($waitcount > 10){
                print STDERR "$infile:$aline: Warning \"<a ...\" starting not terminated\n" unless($opt_W);
                $waitclosetag=0;
                $waitcount=0;
                if ($opt_l){
                    print "$infile:$aline: $atag\n";
                }else{
                    print "$atag\n";
                }
                $atag="";
            }
        }
        # we search for " href", " src", " background": 
        unless($tag[0]=~/\ssrc|\shref|\sbackground/i){
            next;
        } 
        $line=$tag[2];
        $tag[0]=~s/\s+/ /g; # kill newline and double space
        next unless ($tag[0]=~/ (href|src|background) ?=/i);
        #
        if ($tag[0]=~/ (href|src|background) ?= ?([^ >]+)/i){
            $linktype=$1;
            $path=$2;
            $path=~s/[\'\"]//g;
            $ltype=linktype($path);
            if (! $opt_A ){
                next if ($ltype ne "rel");
            }
            if ($tag[1] eq "a" && $opt_a ){
                if ($waitclosetag){
                    print STDERR "Warning: $infile:$line: \"<a ...\" starting at line $aline not terminated\n" unless($opt_W);
                    print "$infile:$aline: $atag\n";
                }
                # wait for closing "</a>"
                $waitcount=0;
                $aline=$line;
                $waitclosetag=1;
                $atag=$tag[0];
            }else{
                # print now
                if ($opt_l){
                    print "$infile:$line: $tag[0]\n";
                }else{
                    # chop off the anchors unless -l was given:
                    # index.html#chapter1 should be index.html otherwise
                    # we can not use it with tar:
                    $path=~s/\#.*$//;
                    # now try to expand links on directories with
                    # the appropriate index file:
                    $dir=dirname($infile);
                    $ckpath="$dir/$path";
                    if ( -f "$ckpath"){
                        $ckpath=flattenpath($ckpath);
                        print "$ckpath\n" unless($killduplicate{$ckpath});
                        $killduplicate{$ckpath}=1;
                        next;
                    }
                    my $found =0;
                    if ( -d "$ckpath"){
                        # remove optional '/'
                        $path=~s/\/$//;
                        if ($path eq "."){ # remove single '.'
                            $ckpath=$dir;
                            $path="";
                        }else{
                            $ckpath="$dir/$path";
                        }
                        for my $i (@possibilities){
                            if ( -f "$ckpath/$i"){
                                # found:
                                $ckpath="$ckpath/$i";
                                $ckpath=flattenpath($ckpath);
                                print "$ckpath\n" unless($killduplicate{$ckpath});
                                $killduplicate{$ckpath}=1;
                                $found=1;
                                last;
                            }
                        }
                    }
                    if(!$found){
                        if ($ltype eq 'rel'){
                            $ckpath="$dir/$path";
                            $ckpath=flattenpath($ckpath);
                            print "$ckpath\n" unless($killduplicate{"$ckpath"});
                            $killduplicate{"$ckpath"}=1;
                        }else{
                            $path=flattenpath($path);
                            print "$path\n" unless($killduplicate{$path});
                            $killduplicate{$path}=1;
                        }
                    }
                }
            }
        }else{
            print STDERR "$infile:$line: Warning, broken link $tag[0]\n" unless($opt_W);
        }
    }
}
#----------------------------------
#  remove .. in a path, by compensating it with previous path components. 
# /zz/../xx becomes /xx
# /zz/../../xx becomes ../xx
# /yy/zz/vv/../../xx becomes /yy/xx
sub flattenpath($){
    my $p=shift;
    if ($p=~/^\w+:\/\//){
        # something like http://...
        return($p);
    }
    # change x/./y to x/y
    $p=~s!/\./!/!g;
    # change ./yy/a -> yy/a
    $p=~s!^\./!!g;
    my @marker; # in this 1 means keep 0 means del
    my @components=split(/\//,$p);
    # now go through components and when you find a ".." then
    # kill the previous component unless it is empty:
    if (scalar @components < 3){
        # too short nothing to do
        return($p);
    }
    my $i=-1;
    my ($found,$j,$cc);
    for my $c (@components){
        $i++;
        $marker[$i]=1;
        if ($i==0){
            # skip first
            next;
        }
        if ($c && $c eq ".."){
            # now seach back 
            $j=$i;
            $found=0;
            while($j && $found==0){
                $j--;
                $cc=$components[$j];
                if ($cc && $marker[$j] && $cc ne "."){
                    $found=1;
                    if ($cc eq ".."){
                        # don't remove this, don't go further back
                        next;
                    }
                    $marker[$j]=0; #kill this component
                    $marker[$i]=0; #kill this component
                }
            }
        }
    }
    # now build a new array with the right components
    my @nc;
    $i=0;
    for my $c (@components){
        if ($marker[$i]){
            push(@nc,$c);
        }
        $i++;
    }
    $p=join("/",@nc);
    # kill //
    $p=~s!//+!/!g;
    return($p);
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
print "tr_llnk -- list links in html files

USAGE: tr_llnk [-h] [-AalW] [-i fname-list] html-files

Without option -A tr_llnk will list only relative links.
The idea of this program is that you run 
tar cvf pages.tar `tr_llnk index.html something.html`
in order to include files that are referenced by index.html and
something.html. 

With the option -A you can use tr_llnk to inspect the links in
html files.

OPTIONS: 
         -h this help

         -a list for <a href=...> tags everything until </a>
         This option implies (-l). You can not use this option
         in combination with tar to pack files together. This is 
         more to look at the links of a webpage.

         -A list all href=...,  src=..., and background=... tags
         whether they are relative or not.

         -i index list. tr_llnk expands links on directories when possible
         by adding the default index file. E.g \"href=../\" becomes
         \"href=../index.html\". This option specifies the search order
         for the index file. It is a comma seperated list of files.
         Default (without this option):
         index.html,index.htm,index.shtml,default.htm,index.php3,
         index.php,index.wml
         Note that this option is not relevant if -l or -a was specified.

         -l print with filename, line number and entire tag. Note that errors
         and warnings are always printed with filename and line numbers.
         If -l is given then the file names from the command line are
         not included unless they appear in one of the files as
         links. You can not use this in combination with tar to pack 
         files together.

         -W do not print warnings about html errors (not terminated
         tags etc ...).

EXAMPLE:
 pack a tar file:
 tar cvf pages.tar `tr_llnk index.html something.html`

 inspect a html file:
 tr_llnk -Al something.html

tr_llnk is part of the HTML::TagReader package.

version $VERSION
         \n";
exit(0);
}
__END__ 

=head1 NAME

tr_llnk -- list links in html files

=head1 SYNOPSIS

USAGE: tr_llnk [-h] [-AalW] [-i fname-list] html-files

=head1 DESCRIPTION

Without option -A tr_llnk will list only relative links.
The idea of this program is that you run 
tar cvf pages.tar `tr_llnk index.html something.html`
in order to include files that are referenced by index.html and
something.html. 

With the option -A you can use tr_llnk to inspect the links in
html files.

=head1 OPTIONS

-h this help

-a list for <a href=...> tags everything until </a>
This option implies (-l). You can not use this option
in combination with tar to pack files together. This is 
more to look at the links of a web page.

-A list all href=...,  src=..., and background=... tags
whether they are relative or not.

-i index list. tr_llnk expands links on directories when possible
by adding the default index file. E.g "href=../" becomes
"href=../index.html". This option specifies the search order
for the index file. It is a comma seperated list of files.
Default (without this option):
index.html,index.htm,index.shtml,default.htm,index.php3,
index.php,index.wml
Note that this option is not relevant if -l or -a was specified.

-l print with filename, line number and entire tag. Note that errors
and warnings are always printed with filename and line numbers.
If -l is given then the file names from the command line are
not included unless they appear in one of the files as
links. You can not use this in combination with tar to pack 
files together.

-W do not print warnings about html errors (not terminated
tags etc ...).

=head1 EXAMPLE

pack a tar file:
tar cvf pages.tar `tr_llnk index.html something.html`

inspect a html file:
tr_llnk -Al something.html

=head1 AUTHOR

tr_llnk is part of the HTML::TagReader package and was written by
Guido Socher [guido(at)linuxfocus.org]

=cut
!NO!SUBS!
