#!/usr/bin/perl

# Simple program to create an ePub eBook version of Modern Perl.
# The basic structure is copied from build_html with some additional
# code from pod2epub.
#
# perltidy -nse -gnu

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
my %entries;

sub Pod::PseudoPod::HTML::begin_X
{
    my $self = shift;
    $self->emit();
}

sub Pod::PseudoPod::HTML::end_X
{
    my $self    = shift;
    my $scratch = delete $self->{scratch};
    my $anchor  = get_anchor_for_index($self->{file}, $scratch);

    $self->{scratch} = qq|<div id="$anchor" />|;
    $self->emit();
}

sub get_anchor_for_index
{
    my ($file, $index) = @_;

    $index =~ s/^(<[pa][^>]*>)+//g;
    $index =~ s/^\s+//g;

    my @paths = split /; /, $index;

    return get_index_entry( $file, @paths );
}

sub get_index_entry
{
    my ($file, $name) = splice @_, 0, 2;
    my $key           = clean_name( $name );
    my $entry         = $entries{$key} ||= IndexEntry->new( name => $name );

    if (@_)
    {
        my $subname    = shift;
        my $subkey     = clean_name( $subname );
        my $subentries = $entry->subentries();
        $entry         = $subentries->{$subkey}
                     ||= IndexEntry->new( name => $subname );

        $key .= '__' . $subkey;
    }

    my $locations = $entry->locations();
    (my $anchor   = $key . '_' . @$locations) =~ tr/ //d;

    push @$locations, [ $file, $anchor ];

    return $anchor;
}

sub clean_name
{
    my $name = shift;
    $name    =~ s/<[^>]+>//g;
    $name    =~ tr/ \\/_/;
    $name    =~ s/([^A-Za-z0-9_])/ord($1)/eg;
    return 'i' . $name;
}

sub Pod::PseudoPod::HTML::end_L
{
    my $self = shift;
    if ($self->{scratch} =~ s/\b(\w+)$//)
    {
        my $link = $1;
        die "Unknown link $link\n" unless exists $anchors->{$link};
        $self->{scratch} .=
            '<a href="'
          . $anchors->{$link}[0]
          . '#' . $link . '">'
          . $anchors->{$link}[1] . "</a>($link)";
    }
}

for my $chapter (@chapters)
{
    my $out_fh = get_output_fh($chapter);
    my $parser = Pod::PseudoPod::HTML->new();

    $parser->nix_X_codes(0);

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

    my ($file) = $chapter =~ /(chapter_\d+)./;
    $parser->{file} = $file . '.xhtml';

    $parser->parse_file($chapter);

    push @$table_of_contents, @{$parser->{to_index}};
}

generate_index(\%entries);
generate_ebook();

exit;

sub get_anchors
{
    my %anchors;

    for my $chapter (@_)
    {
        my ($file)   = $chapter =~ /(chapter_\d+)./;
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

    open my $fh, '>:utf8', $name
      or die "Cannot write to '$name': $!\n";

    return $fh;
}

sub generate_index
{
    my $entries = shift;
    my $fh      = get_output_fh( 'index.pod' );
    my @sorted  = sort { $a cmp $b } keys %$entries;

print $fh <<'END_HEADER';
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html
     PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Index</title>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1"/>
<link rel="stylesheet" href="../styles/style.css" type="text/css"/>
</head>

<body>
END_HEADER

    print_index( $fh, \%entries, \@sorted );

print $fh <<'END_FOOTER';
</body>
</html>
END_FOOTER

}

sub print_index
{
    my ($fh, $entries, $sorted) = @_;

    print $fh "<ul>\n";
    for my $top (@$sorted)
    {
        my $entry = $entries->{$top};

        my $i    = 1;
        my $name = $entry->name;
        my $locs = join ",\n",
            map { my ($f, $l)= @$_; qq|<a href="$f#$l">| . $i++ . '</a>' }
            @{ $entry->locations };

        print $fh "<li>$name\n$locs\n";

        my $subentries = $entry->subentries;
        if (%$subentries)
        {
            my @subkeys = sort { $a cmp $b } keys %$subentries;

            print_index( $fh, $subentries, \@subkeys );
        }
        print $fh "</li>\n";
    }

    print $fh "</ul>\n";
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

    # Add the book cover.
    add_cover($epub, './images/mp_cover_full.png');

    # Add some other metadata to the OPF file.
    $epub->add_meta_item('EBook::EPUB version', $EBook::EPUB::VERSION);

    # Add package content: stylesheet, font, xhtml
    $epub->copy_stylesheet('./build/html/style.css', 'styles/style.css');

    for my $chapter (@chapters)
    {
        my $name = (splitpath $chapter )[-1];
        $name =~ s/\.pod/\.xhtml/;
        my $file = "./build/xhtml/$name";

        system( qw( tidy -q -m -utf8 -asxhtml -wrap 0 ), $file );

        $epub->copy_xhtml('./build/xhtml/' . $name,
                          'text/' . $name );
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

        # This is a workaround for non-contiguous heading levels.
        $navpoints[$heading_level + 1] = $navpoint_obj;

    }
}


###############################################################################
#
# add_cover()
#
# Add a cover image to the eBook. Add cover metadata for iBooks and add an
# additional cover page for other eBook readers.
#
sub add_cover
{

    my $epub        = shift;
    my $cover_image = shift;


    # Check if the cover image exists.
    if (!-e $cover_image)
    {
        warn "Cover image $cover_image not found.\n";
        return undef;
    }

    # Add cover metadata for iBooks.
    my $cover_id = $epub->copy_image($cover_image, 'images/cover.png');
    $epub->add_meta_item('cover', $cover_id);

    # Add an additional cover page for other eBook readers.
    my $cover_xhtml =
        qq[<?xml version="1.0" encoding="UTF-8"?>\n]
      . qq[<!DOCTYPE html\n]
      . qq[     PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"\n]
      . qq[    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">\n\n]
      . qq[<html xmlns="http://www.w3.org/1999/xhtml">\n]
      . qq[<head>\n]
      . qq[<title></title>\n]
      . qq[<meta http-equiv="Content-Type" ]
      . qq[content="text/html; charset=iso-8859-1"/>\n]
      . qq[<style type="text/css"> img { max-width: 100%; }</style>\n]
      . qq[</head>\n]
      . qq[<body>\n]
      . qq[    <p><img alt="Modern Perl" src="../images/cover.png" /></p>\n]
      . qq[</body>\n]
      . qq[</html>\n\n];

    # Crete a the cover xhtml file.
    my $cover_filename = './build/xhtml/cover.xhtml';
    open my $cover_fh, '>:utf8', $cover_filename
      or die "Cannot write to '$cover_filename': $!\n";

    print $cover_fh $cover_xhtml;
    close $cover_fh;

    # Add the cover page to the ePub doc.
    $epub->copy_xhtml($cover_filename, 'text/cover.xhtml' );

    # Add the cover to the OPF guide.
    my $guide_options = {
                         type  => 'cover',
                         href  => 'text/cover.xhtml',
                         title => 'Cover',
                        };

    $epub->guide->add_reference($guide_options);

    return $cover_id;
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
sub start_Z { $_[0]{'scratch'} .= '<div id="' }
sub end_Z   { $_[0]{'scratch'} .= '"/>'; $_[0]->emit() }

# Override Pod::PseudoPod::HTML U<> to prevent deprecated <font> tag.
sub start_U { $_[0]{'scratch'} .= '<span class="url">' if $_[0]{'css_tags'} }
sub end_U   { $_[0]{'scratch'} .= '</span>' if $_[0]{'css_tags'} }

# Override Pod::PseudoPod::HTML N<> to prevent deprecated <font> tag.
sub start_N {
  my ($self) = @_;
  $self->{'scratch'} .= '<span class="footnote">' if ($self->{'css_tags'});
  $self->{'scratch'} .= ' (footnote: ';
}

sub end_N {
  my ($self) = @_;
  $self->{'scratch'} .= ')';
  $self->{'scratch'} .= '</span>' if $self->{'css_tags'};
}

# Override Pod::PseudoPod::HTML to escape all XML entities.
sub handle_text { $_[0]{'scratch'} .= encode_entities($_[1]); }

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

package IndexEntry;

sub new
{
    my ($class, %args) = @_;
    bless { locations => [], subentries => {}, %args }, $class;
}

sub name       { $_[0]{name}       }
sub locations  { $_[0]{locations}  }
sub subentries { $_[0]{subentries} }


__END__
