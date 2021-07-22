#!/usr/bin/env perl

use Modern::Perl '2019';
use Pod::PseudoPod::Book;
use Path::Tiny;

exit main( @ARGV );

sub main {
    my $app = Pod::PseudoPod::Book->new;

    my ($cmd, $opt, @args) = $app->get_command( 'buildhtml' );

    for my $build_path ( 'build/chapters', 'build/html' ) {
        path($build_path)->mkpath;
    }

    for my $command (qw( buildcredits buildchapters ), $cmd ) {
        $app->execute_command( $app->plugin_for( $command ), $opt, @args );
    }

    fixup_html_chapters( 'build/html' );

    return 0;
}

sub fixup_html_chapters {
    my $output_dir = path(shift);

    for my $child_file ($output_dir->children( qr/\.html$/ ) ) {
        $child_file->edit( sub {
            s/<body>/<body><div class="container">/;
            s/<\/body>/<\/div><\/body>/;
        });
    }
}
