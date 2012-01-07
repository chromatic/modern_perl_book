#!/usr/bin/perl

use strict;
use warnings;

use File::Spec::Functions qw( catfile catdir splitpath );
use File::Which;

# getting chapter list
my @chapters = get_chapter_list();

# Check if pod2pdf is available
require App::pod2pdf
    or die "pod2pdf is not present in your PATH; please install App::pod2pdf\n";

my $outpath = catdir( qw( build pdf ) );

for my $chapter ( @chapters ){
    my @filename = split( /\./ , $chapter );
    print "Converting $chapter to pdf\n";
    system( 'pod2pdf', '--noheader', $chapter, '--output-file',
        catfile(qw( build pdf ), (splitpath($filename[0]))[-1] . '.pdf' ) );
}

my $pdftk = which('pdftk');

if ($pdftk) {
    my @c = glob catfile( $outpath, qw ( chapter_??.pdf ));
    system( $pdftk, @c, 'cat', 'output', catfile($outpath, 'modern_perl.pdf'));
}

print "PDFs have been generated in build/pdf\n";

sub get_chapter_list
{
    my $glob_path = catfile( qw( build chapters chapter_??.pod ) );
    return glob $glob_path;
}
