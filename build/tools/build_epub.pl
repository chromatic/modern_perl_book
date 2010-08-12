#!/usr/bin/perl

use strict;
use warnings;

use EBook::EPUB;
use File::Path 'make_path';
use File::Spec::Functions qw( catfile catdir );
use POSIX 'strftime';

my $credits   = 'CREDITS';
my $readme    = 'README';
my $style     = catfile(qw( build html style.css ));
my $html      = catfile(qw( build html ));
my $epub_dir  = catdir(qw( build epub ));
my $epub_file = catfile( $epub_dir, 'modernperlbooks.epub' );

my $epub = EBook::EPUB->new;
$epub->add_title( 'Modern Perl' );
$epub->add_identifier( 'http://www.modernperlbooks.com');
$epub->add_author( 'chromatic' );
$epub->add_date( strftime( '%Y-%m-%d', localtime ), 'Created by epub build tool' );
$epub->add_language( 'en' );
$epub->copy_stylesheet( $style, 'style.css' );

{ # Loop through CREDITS and add them as collaborators

  open my $C, '<', $credits or die "Unable to open CREDITS: $!\n";

  local $/ = "\n\n";

  for my $rec ( <$C> ) {

    my ( $name, $email ) = $rec =~ /^N:\s(.*?)\nE:\s(.*?)\n/s;

    next if $name =~ /^(?:<name>|chromatic)?$/;

    $epub->add_contributor( $name, 'role' => 'clb' );

  }
};

{ # Grab the copyright from the README

  open my $R, '<', $readme or die "Unable to open README: $!\n";

  local $/ = "\n\n\n";

  my ( $copyright ) = reverse <$R>;

  $epub->add_rights( $copyright );

}

$epub->copy_xhtml( catfile( $html, "chapter_$_.html" ), "chapter_$_.xhtml" ) for map { sprintf '%02d', $_ } 0 .. 12;

make_path( $epub_dir );

$epub->pack_zip( $epub_file );
