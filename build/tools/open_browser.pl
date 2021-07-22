#!/usr/bin/env perl

use Modern::Perl '2019';
use Browser::Open;
use Path::Tiny;
use feature 'signatures';
no warnings 'experimental::signatures';

exit main( @ARGV );

sub main($chapter = undef) {
    return Browser::Open::open_browser('file://' . get_chapter($chapter), 1 );
}

sub get_chapter($chapter_number) {
    return get_file(shift)->absolute;
}

sub get_file($chapter_number) {
    my $index = path('build/html/index.html');
    return $index unless $chapter_number;
    return $index unless $chapter_number =~ /\A\d+\Z/;

    for my $num ($chapter_number, '0' . $chapter_number) {
        my $chapter_path = path('build/html/chapter_' . $num . '.html');
        return $chapter_path if $chapter_path->exists;
    }

    return $index;
}
