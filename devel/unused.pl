#!/usr/bin/perl

# Copyright 2007, 2008, 2009, 2010 Kevin Ryde
#
# This file is part of RSS2Leafnode.
#
# RSS2Leafnode is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation; either version 3, or (at your option) any later
# version.
#
# RSS2Leafnode is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with RSS2Leafnode.  If not, see <http://www.gnu.org/licenses/>.


__END__

#------------------------------------------------------------------------------
# xml_charset()

ok (App::RSS2Leafnode::xml_charset('<?xml version="1.0" encoding="UTF-8"?>'), 'UTF-8');

# $xml is a string of bytes comprising an xml document, return the encoding
# attribute in the initial <?xml...> tag if it has one, or false if not
sub xml_charset {
  my ($xml) = @_;
  $xml =~ /<\?xml[^>]*encoding="?([^">]+)/
    && $1;
}

#-----------------------------------------------------------------------------
# HTTP::Response ->title is enough
          // html_title_treebuilder($resp)
sub html_title_treebuilder {
  my ($resp) = @_;
  # WWW::GetPageTitle does a similar <title> extract with just a regexp.
  $resp->content_type eq 'text/html' or return;
  eval { require HTML::TreeBuilder } or return;
  my $content = $resp->decoded_content;
  my $tree = HTML::TreeBuilder->new_from_content ($content);
  my $elem = $tree->find_by_tag_name('title');
  my $title = (defined $elem ? $elem->as_text : undef);
  $tree->delete;
  return $title;
}

#------------------------------------------------------------------------------
# html_title_treebuilder()

diag "html_title_treebuilder()";
SKIP: {
  eval { require HTML::TreeBuilder } or
    skip 'due to no HTML::TreeBuilder', 1;

  require HTTP::Response;
  my $resp = HTTP::Response->new;
  $resp->content_type('text/html');
  $resp->content(<<'HERE');
<html><head><title>A Page</title></head>
<body> Hello </body> </html>
HERE
  my $str = App::RSS2Leafnode::html_title_treebuilder ($resp);
  is ($str, 'A Page', 'html_title_treebuilder()');
}

             fetch_html_title_builder
             => { description => 'A slightly better Subject for fetch_html() messages using HTML::TreeBuilder.',
                  requires => { 'HTML::TreeBuilder' => 0 },
                },


# $html is a string of html content, as perl wide chars.
# Return rendered text, likewise as perl wide chars.
#
# The docs for HTML::FormatText suggest it only supports latin1, but wide
# chars seem to pass through unmolested.  Certain hard-coded bits in it like
# \x{A0} for non-breaking space and \x{A9} soft hyphen should be ok with
# unicode.  The default for HTML::TreeBuilder, as used by FormatText, in
# fact is to expand entities like "&hearts;" to wide chars.
#
# sub render_html_to_text {
#   my ($self, $html) = @_;
#   require HTML::TreeBuilder;
#   require HTML::FormatText;
# 
#   my $tree = HTML::TreeBuilder->new->parse($html);
#   $tree->eof;
#   my $formatter = HTML::FormatText->format_string ($html,
#                                                    leftmargin => 0,
#                                                    rightmargin => $self->{'render_width'});
#   return $formatter->format($tree);
# }
