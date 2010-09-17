#!/usr/bin/perl

use strict;
use warnings;

use File::Path 'mkpath';
use File::Spec::Functions qw( catfile catdir splitpath );

my $sections_href = get_section_list();

for my $chapter (get_chapter_list())
{
    my $text = process_chapter( $chapter, $sections_href );
    write_chapter( $chapter, $text );
}

die( "Scenes missing from chapters:", join "\n\t", '', keys %$sections_href )
    if keys %$sections_href;

exit;

sub get_chapter_list
{
    my $glob_path = catfile( 'sections', 'chapter_??.pod' );
    return glob( $glob_path );
}

sub get_section_list
{
    my %sections;
    my $sections_path = catfile( 'sections', '*.pod' );

    for my $section (glob( $sections_path ))
    {
        next if $section =~ /\bchapter_??/;
        my $anchor = get_anchor( $section );
        $sections{ $anchor } = $section;
    }

    return \%sections;
}

sub get_anchor
{
    my $path = shift;

    open my $fh, '<:utf8', $path or die "Can't read '$path': $!\n";
    while (<$fh>) {
        next unless /Z<(\w*)>/;
        return $1;
    }

    die "No anchor for file '$path'\n";
}

sub process_chapter
{
    my ($path, $sections_href) = @_;
    my $text                 = read_file( $path );

    $text =~ s/^L<(\w+)>/insert_section( $sections_href, $1, $path )/emg;

    $text =~ s/(=head1 .*)\n\n=head2 \*{3}/$1/g;
    return $text;
}

sub read_file
{
    my $path = shift;
    open my $fh, '<:utf8', $path or die "Can't read '$path': $!\n";
    return scalar do { local $/; <$fh>; };
}

sub insert_section
{
    my ($sections_href, $name, $chapter) = @_;

    die "Unknown section '$name' in '$chapter'\n"
        unless exists $sections_href->{ $1 };

    my $text = read_file( $sections_href->{ $1 } );
    delete $sections_href->{ $1 };
    return $text;
}

sub write_chapter
{
    my ($path, $text) = @_;
    my $name          = ( splitpath $path )[-1];
    my $chapter_dir   = catdir( 'build', 'chapters' );
    my $chapter_path  = catfile( $chapter_dir, $name );

    mkpath( $chapter_dir ) unless -e $chapter_dir;

    open my $fh, '>:utf8', $chapter_path
        or die "Cannot write '$chapter_path': $!\n";

    print {$fh} $text;

    warn "Writing '$path'\n";
}
