#!/usr/bin/env perl 
use strict;
use warnings;
use Cwd;
use File::Spec;

my $dir = getcwd;
die "I need to be run from the modern_perl_book root rather then $dir" unless $dir =~ m/modern_perl_book$/; # TODO this could be more specific

my $cmd = join ' && '
        , map{ File::Spec->catfile($dir,qw{build tools}, "build_$_.pl") } 'chapters', @ARGV
        ; 

system $cmd;
