#!/usr/bin/perl

# Simple program to create an ePub eBook version of Modern Perl.
# The basic structure is copied from build_html.

use strict;
use warnings;

use Pod::PseudoPod::HTML;
use File::Spec::Functions qw( catfile catdir splitpath );
use EBook::EPUB;

# P::PP::H uses Text::Wrap which breaks HTML tags
local *Text::Wrap::wrap;
*Text::Wrap::wrap = sub { $_[2] };

my @chapters          = get_chapter_list();
my $anchors           = get_anchors(@chapters);
my $table_of_contents = [];


sub Pod::PseudoPod::HTML::end_L
{
    my $self = shift;
    if ($self->{scratch} =~ s/\b(\w+)$//)
    {
        my $link = $1;
        die "Unknown link $link\n" unless exists $anchors->{$link};
        $self->{scratch} .= '<a href="' . $anchors->{$link}[0] . "#$link\">"
          . $anchors->{$link}[1] . '</a>';
    }
}

for my $chapter (@chapters)
{

    my $out_fh = get_output_fh($chapter);
    my $parser = Pod::PseudoPod::HTML->new();

    # Set a default heading id for <h?> headings.
    # TODO. Starts at 2 for debugging. Change later.
    $parser->{heading_id} = 2;

    $parser->output_fh($out_fh);

    # output a complete html document
    $parser->add_body_tags(1);

    # add css tags for cleaner display
    $parser->add_css_tags(1);

    $parser->no_errata_section(1);
    $parser->complain_stderr(1);

    $parser->parse_file($chapter);

    push @$table_of_contents, @{$parser->{to_index}};
}


generate_ebook();

exit;

sub get_anchors
{
    my %anchors;

    for my $chapter (@_)
    {
        my ($file) = $chapter =~ /(chapter_\d+)./;
        my $contents = slurp($chapter);

        while ($contents =~ /^=head\d (.*?)\n\nZ<(.*?)>/mg)
        {
            $anchors{$2} = [$file . '.xhtml', $1];
        }
    }

    return \%anchors;
}

sub slurp
{
    return do { local @ARGV = @_; local $/ = <>; };
}

sub get_chapter_list
{
    my $glob_path = catfile(qw( build chapters chapter_??.pod ));
    return glob $glob_path;
}

sub get_output_fh
{
    my $chapter  = shift;
    my $name     = (splitpath $chapter )[-1];
    my $xhtmldir = catdir(qw( build xhtml ));

    $name =~ s/\.pod/\.xhtml/;
    $name = catfile($xhtmldir, $name);

    open my $fh, '>', $name
      or die "Cannot write to '$name': $!\n";

    return $fh;
}


##############################################################################
#
# generate_ebook()
#
# Assemble the XHTML pages into an ePub eBook.
#
sub generate_ebook
{

    # Create EPUB object
    my $epub = EBook::EPUB->new();

    # Set the ePub metadata.
    $epub->add_title('Modern Perl');
    $epub->add_author('chromatic');
    $epub->add_language('en');

    # Add some other metadata to the OPF file.
    $epub->add_meta_item('EBook::EPUB version', $EBook::EPUB::VERSION);

    # Add package content: stylesheet, font, xhtml
    $epub->copy_stylesheet('./build/html/style.css', 'styles/style.css');


    for my $chapter (@chapters)
    {
        my $name = (splitpath $chapter )[-1];
        $name =~ s/\.pod/\.xhtml/;

        $epub->copy_xhtml('./build/xhtml/' . $name, 'text/' . $name,
                          linear => 'no');
    }

    # Add Pod headings to table of contents.
    set_table_of_contents($epub, $table_of_contents);

    # Make the directory if it doesn't exist.
    my $dir = catdir(qw(build epub));
    mkdir $dir unless -e $dir;

    # Generate the ePub eBook.
    my $filename = catfile(qw(build epub modern_perl.epub));
    $epub->pack_zip($filename);
}


##############################################################################
#
# set_table_of_contents()
#
# Add the Pod headings to the NCX <navMap> table of contents.
#
sub set_table_of_contents
{

    my $epub         = shift;
    my $pod_headings = shift;

    my $play_order = 1;
    my @navpoints  = ($epub) x 5;
    my @navpoint_obj;


    for my $heading (@$pod_headings)
    {

        my $heading_level = $heading->[0];
        my $section       = $heading->[1];
        my $label         = $heading->[2];
        my $content       = 'text/' . $heading->[3] . '.xhtml';


        # Add the pod section to the NCX data, Except for the root heading.
        $content .= '#' . $section if $section ne 'heading_id_2';

        my %options = (
                       content    => $content,
                       id         => 'navPoint-' . $play_order,
                       play_order => $play_order,
                       label      => $label,
                      );

        $play_order++;

        # Add the navpoints at the correct nested level.
        my $navpoint_obj = $navpoints[$heading_level - 1];

        $navpoint_obj = $navpoint_obj->add_navpoint(%options);

        # The returned navpoint object is used for the next nested level.
        $navpoints[$heading_level] = $navpoint_obj;

        # This is a workaround for non-contigous heading levels.
        $navpoints[$heading_level + 1] = $navpoint_obj;

    }
}


##############################################################################
#
# Monkey patch Pod::PseudoPod::HTML to make it generate XHTML.
#
# Add the Pod headings to the NCX <navMap> table of contents.
#
package Pod::PseudoPod::HTML;

no warnings 'redefine';

# Override Pod::PseudoPod::HTML to add XML and XHTML headers.
sub start_Document
{
    my ($self) = @_;

    my $xhtml_headers =
        qq{<?xml version="1.0" encoding="UTF-8"?>\n}
      . qq{<!DOCTYPE html\n}
      . qq{     PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"\n}
      . qq{    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">\n} . qq{\n}
      . qq{<html xmlns="http://www.w3.org/1999/xhtml">\n}
      . qq{<head>\n}
      . qq{<title></title>\n}
      . qq{<meta http-equiv="Content-Type" }
      . qq{content="text/html; charset=iso-8859-1"/>\n}
      . qq{<link rel="stylesheet" href="../styles/style.css" }
      . qq{type="text/css"/>\n}
      . qq{</head>\n} . qq{\n}
      . qq{<body>\n};


    $self->{'scratch'} .= $xhtml_headers;
    $self->emit('nowrap');
}

# Override Pod::PseudoPod::HTML close Z<> generated <a> tags.
sub end_Z { $_[0]{'scratch'} .= '"/>' }

# Override Pod::PseudoPod::HTML to escape all XML entities.
sub handle_text{ $_[0]{'scratch'} .= encode_entities($_[1]); }

# Override Pod::PseudoPod::HTML to close list items.
sub end_item_text { $_[0]{'scratch'} .= '</li>'; $_[0]->emit() }

# Override Pod::PseudoPod::HTML to add id tags to <h?> levels. This is required for
# the table of contents. This code is copied mainly from Pod::Simple::XHTML.
sub start_head0 { $_[0]{'in_head'} = 0 }
sub start_head1 { $_[0]{'in_head'} = 1 }
sub start_head2 { $_[0]{'in_head'} = 2 }
sub start_head3 { $_[0]{'in_head'} = 3 }
sub start_head4 { $_[0]{'in_head'} = 4 }

sub end_head0 { shift->_end_head(@_); }
sub end_head1 { shift->_end_head(@_); }
sub end_head2 { shift->_end_head(@_); }
sub end_head3 { shift->_end_head(@_); }
sub end_head4 { shift->_end_head(@_); }

sub _end_head
{
    my $h = delete $_[0]{in_head};
    $h++;

    my $id   = 'heading_id_' . $_[0]{heading_id}++;
    my $text = $_[0]{scratch};
    $_[0]{'scratch'} = qq{<h$h id="$id">$text</h$h>};
    $_[0]->emit;

    (my $chapter = $_[0]{source_filename}) =~ s/^.*chapter_(\d+).*$/chapter_$1/;

    push @{$_[0]{'to_index'}}, [$h, $id, $text, $chapter];
}

__END__
