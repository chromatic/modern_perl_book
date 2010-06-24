#! perl

use strict;
use warnings;

use Pod::PseudoPod::HTML;

# P::PP::H uses Text::Wrap which breaks HTML tags
local *Text::Wrap::wrap;
*Text::Wrap::wrap = sub { $_[2] };

use File::Spec::Functions qw( catfile catdir splitpath );

for my $chapter (get_chapter_list())
{
    my $out_fh = get_output_fh($chapter);
    my $parser = Pod::PseudoPod::HTML->new();

    $parser->output_fh($out_fh);

    # output a complete html document
    $parser->add_body_tags(1);

    # add css tags for cleaner display
    $parser->add_css_tags(1);

    $parser->no_errata_section(1);
    $parser->complain_stderr(1);

    $parser->parse_file($chapter);
}

exit;

sub get_chapter_list
{
    my $glob_path = catfile( qw( build chapters chapter_??.pod ) );
    return glob $glob_path;
}

sub get_output_fh
{
    my $chapter = shift;
    my $name    = ( splitpath $chapter )[-1];
    my $htmldir = catdir( qw( build html ) );

    $name       =~ s/\.pod/\.html/;
    $name       = catfile( $htmldir, $name );

    open my $fh, '>', $name
        or die "Cannot write to '$name': $!\n";

    return $fh;
}
