#!/usr/bin/perl

# Copyright 2007, 2008, 2009, 2010 Kevin Ryde

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
# You can get a copy of the GNU General Public License online at
# http://www.gnu.org/licenses.

use 5.010;
use strict;
use warnings;
use Test::More tests => 165;
use Locale::TextDomain ('App-RSS2Leafnode');

# version 2.04 provokes warnings from perl 5.11, load before NoWarnings
use HTML::Formatter;

SKIP: { eval 'use Test::NoWarnings; 1'
          or skip 'Test::NoWarnings not available', 1; }

require App::RSS2Leafnode;
require POSIX;
POSIX::setlocale(POSIX::LC_ALL(), 'C'); # no message translations


#------------------------------------------------------------------------------
# VERSION

{
  my $want_version = 24;
  is ($App::RSS2Leafnode::VERSION, $want_version, 'VERSION variable');
  is (App::RSS2Leafnode->VERSION,  $want_version, 'VERSION class method');

  ok (eval { App::RSS2Leafnode->VERSION($want_version); 1 },
      "VERSION class check $want_version");
  my $check_version = $want_version + 1000;
  ok (! eval { App::RSS2Leafnode->VERSION($check_version); 1 },
      "VERSION class check $check_version");

  my $r2l = App::RSS2Leafnode->new;
  is ($r2l->VERSION,  $want_version, 'VERSION object method');

  ok (eval { $r2l->VERSION($want_version); 1 },
      "VERSION object check $want_version");
  ok (! eval { $r2l->VERSION($check_version); 1 },
      "VERSION object check $check_version");
}


#------------------------------------------------------------------------------
# rss_newest_cmp()

diag "rss_newest_cmp()";
{
  foreach my $data (
                    [ undef, undef, 0 ],
                    [     0, undef, 0 ],
                    [ undef,     0, 0 ],
                    [     0,     0, 0 ],

                    [ undef,     5, 1 ],
                    [     0,     5, 1 ],

                    [     5, undef, -1 ],
                    [     5,     0, -1 ],

                    [     5,     5,  0 ],
                    [     4,     5, -1 ],
                    [     5,     4,  1 ],

                    [     2,     2,  0 ],
                    [     1,     2, -1 ],
                    [     2,     1,  1 ],
                   ) {
    my ($x, $y, $want) = @$data;
    my $got = App::RSS2Leafnode::rss_newest_cmp({rss_newest_only => $x},
                                                {rss_newest_only => $y});
    $got ||= 0;
    is ($got, $want,
        "rss_newest_cmp() ".($x//'undef')." ".($y//'undef'));
  }
}


#------------------------------------------------------------------------------
# enforce_html_charset_from_content()

diag "enforce_html_charset_from_content()";
{
  my $r2l = App::RSS2Leafnode->new (html_charset_from_content => 1);
  foreach my $data (
                    [ 'UTF-8',
                      [ 'Content-Type' => 'text/html; charset=ISO-8859-1' ],
                      <<'HERE' ],
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
</head>
<body>Hello</body>
</html>
HERE
                    # This one might be slightly dependent on what LWP
                    # thinks of nothing in the content.
                    [ 'US-ASCII',
                      [ 'Content-Type' => 'text/html; charset=ISO-8859-1' ],
                      '<html><body>Hello</body></html>' ],

                    [ 'ISO-8859-1',
                      [ 'Content-Type' => 'text/html; charset=ISO-8859-1' ],
                      <<'HERE' ],
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=ISO-8859-1">
</head>
<body>Hello</body>
</html>
HERE
                   ) {
    my ($want, $headers, $content) = @$data;
    require HTTP::Response;
    my $resp = HTTP::Response->new (200, 'OK', $headers, $content);
    $r2l->enforce_html_charset_from_content($resp);
    diag "resp headers:\n", $resp->headers->as_string;
    is ($resp->content_charset,
        $want,
        "enforce_html_charset_from_content() $want html: $content");
  }
}


#------------------------------------------------------------------------------
# new()

{
  my $r2l = App::RSS2Leafnode->new;
  is ($r2l->{'verbose'}, 0,
      "new() verbose default value");
}
{
  my $r2l = App::RSS2Leafnode->new (verbose => 123);
  is ($r2l->{'verbose'}, 123,
      "new() verbose specified");
}


#------------------------------------------------------------------------------
# mime_mailer()

{
  my $r2l = App::RSS2Leafnode->new;
  ok ($r2l->mime_mailer,
      "mime_mailer() not empty");
}


#------------------------------------------------------------------------------
# elt_content_type()

{
  my $r2l = App::RSS2Leafnode->new;
  foreach my $data (
                    ['text', <<'HERE'],  # Atom default 'text'
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry>
   <content>Hello</content>
  </entry>
</feed>
HERE
                    ['text', <<'HERE'],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry>
   <content type="text">Hello</content>
  </entry>
</feed>
HERE
                    ['xhtml', <<'HERE'],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry>
   <content type="application/xhtml+xml"></content>
  </entry>
</feed>
HERE
                    ['html', <<'HERE'],  # RSS <description> 'html'
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item><description></description></item>
 </channel>
</rss>
HERE
                    ['text', <<'HERE'],  # RSS <title> 'text'
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item><title>Item One</title></item>
 </channel>
</rss>
HERE
                   ) {
    my ($want, $xml) = @$data;
    my ($twig, $err) = $r2l->twig_parse ($xml);

    my $elt = ($twig->root->first_descendant('content')
               || $twig->root->first_descendant('description')
               || $twig->root->first_descendant('title')
               || die);

    is (App::RSS2Leafnode::elt_content_type($elt),
        $want,
        "elt_content_type() $xml");
  }
}


#------------------------------------------------------------------------------
# trim_whitespace()

{
  foreach my $data (["ab c",                   'ab c'],
                    [" ab c  ",                'ab c'],
                    ["\r\n\f\t ab c \r\n\f\t", 'ab c'],
                   ) {
    my ($str, $want) = @$data;
    is (App::RSS2Leafnode::trim_whitespace($str),
        $want,
        "trim_whitespace() '$str'");
  }
}


#------------------------------------------------------------------------------
# item_to_subject()

{
  my $r2l = App::RSS2Leafnode->new;

  foreach my $data (
                    ['Item One', <<'HERE'],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry>
   <title type="xhtml" xmlns:xh="http://www.w3.org/1999/xhtml">
     <xh:div>
       Item <xh:b>One</xh:b>
     </xh:div>
   </title>
  </entry>
</feed>
HERE
                    ['Item One', <<'HERE'],
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item><title>Item One</title></item>
 </channel>
</rss>
HERE
                    [__('no subject'), <<'HERE'],
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item><title></title></item>
 </channel>
</rss>
HERE
                    ['000', <<'HERE'],
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item><title>000</title></item>
 </channel>
</rss>
HERE
                    [__('no subject'), <<'HERE'],
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item></item>
 </channel>
</rss>
HERE
                    ['Item One', <<'HERE'],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry>
    <title type="text">Item One</title>
  </entry>
</feed>
HERE
                    ['Item One', <<'HERE'],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry>
    <title type="html">Item &lt;b&gt;One&lt;/b&gt;</title>
  </entry>
</feed>
HERE
                   ) {
    my ($want, $xml) = @$data;
    my ($twig, $err) = $r2l->twig_parse ($xml);

    my $item = ($twig->root->first_descendant('item')
                || $twig->root->first_descendant('entry')
                || die);

    is ($r2l->item_to_subject ($item),
        $want,
        "item_to_subject() $xml");
  }
}


#------------------------------------------------------------------------------
# item_to_links()

{
  my $r2l = App::RSS2Leafnode->new;
  my $name_foo = __x('{linkrel}:', linkrel => 'foo');

  foreach my $data (
                    [[{ name     => $name_foo,
                        uri      => 'http://foo.com/itemone.html',
                        download => 1,
                        hreflang => undef,
                        title    => undef,
                        type     => undef,
                      }
                     ],
                     <<'HERE'],
<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>Item One</title>
    <content type="text">Hello</content>
    <link rel="foo" href="http://foo.com/itemone.html"/>
  </entry>
</feed>
HERE
                    [[{ name     => 'foo(2K):',
                        uri      => 'http://foo.com/itemone.html',
                        download => 1,
                        hreflang => undef,
                        title    => undef,
                        type     => undef,
                      }
                     ],
                     <<'HERE'],
<?xml version="1.0"?>
<at:feed xmlns:at="http://www.w3.org/2005/Atom">
  <at:entry>
    <at:title>Item One</at:title>
    <at:link rel="foo" href="http://foo.com/itemone.html" length="2000"/>
  </at:entry>
</at:feed>
HERE
                    [[{ name     => __('Link:'),
                        uri      => 'http://foo.com/itemone.html',
                        download => 1,
                        hreflang => undef,
                        title    => undef,
                        type     => undef,
                      }
                     ],
                     <<'HERE'],
<?xml version="1.0"?>
<at:feed xmlns:at="http://www.w3.org/2005/Atom">
  <at:entry>
    <at:title>Item One</at:title>
    <at:link href="http://foo.com/itemone.html"/>
    <at:link href="http://foo.com/itemone.html"/>
  </at:entry>
</at:feed>
HERE
                    [[{ name     => __x('Comments({count}):', count => 123),
                        uri      => 'http://foo.com/itemone.html',
                        download => 0,
                        hreflang => undef,
                        title    => undef,
                        type     => undef,
                      }
                     ],
                     <<'HERE'],
<?xml version="1.0"?>
<feed xmlns:myslash="http://purl.org/rss/1.0/modules/slash/">
  <item>
    <title>Item One</title>
    <comments>http://foo.com/itemone.html</comments>
    <myslash:comments>123</myslash:comments>
  </item>
</feed>
HERE

                    [[{ name     => __('Diff:'),
                        uri      => 'http://foo.com/itemone.html',
                        download => 1,
                        hreflang => undef,
                        title    => undef,
                        type     => undef,
                      }
                     ],
                     <<'HERE'],
<?xml version="1.0"?>
<feed xmlns:wiki="http://purl.org/rss/1.0/modules/wiki/">
  <item>
    <title>Item One</title>
    <wiki:diff>http://foo.com/itemone.html</wiki:diff>
  </item>
</feed>
HERE
                    [[{ name     => __('Link:'),
                        uri      => 'http://foo.com/itemone.html',
                        download => 1,
                        hreflang => undef,
                        title    => undef,
                        type     => undef,
                      }
                     ],
                     <<'HERE'],
<?xml version="1.0"?>
<at:feed xmlns:at="http://www.w3.org/2005/Atom">
  <at:entry>
    <at:title>Item One</at:title>
    <at:content src="http://foo.com/itemone.html"/>
  </at:entry>
</at:feed>
HERE

                    [[{ name     => __('Link:'),
                        uri      => 'http://foo.com/itemone.html',
                        download => 1,
                        hreflang => undef,
                        title    => undef,
                        type     => undef,
                      }
                     ],
                     <<'HERE'],
<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>Item One</title>
    <content src="http://foo.com/itemone.html"/>
  </entry>
</feed>
HERE
                    #
                    [[{ name     => __x('Replies({count}):', count => 123),
                        uri      => 'http://foo.com/itemone.html',
                        download => 0,
                        hreflang => 'en',
                        title    => 'some thing',
                        type     => 'text/html',
                      }
                     ],
                     <<'HERE'],
<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:thr="http://purl.org/syndication/thread/1.0">
  <entry>
    <title>Item One</title>
    <link rel="replies" thr:count="123"
          type="text/html" hreflang="en" title="some thing"
          href="http://foo.com/itemone.html"/>
  </entry>
</feed>
HERE
                   ) {
    my ($want, $xml) = @$data;

    my ($twig, $err) = $r2l->twig_parse ($xml);
    if ($err) { diag $err; }
    my $item = ($twig->root->first_descendant('item')
                || $twig->root->first_descendant('entry')
                || die);

    is_deeply ([$r2l->item_to_links ($item)],
               $want,
               "item_to_links() xml=$xml");
  }
}


#------------------------------------------------------------------------------
# item_to_generator()

{
  my $r2l = App::RSS2Leafnode->new;

  foreach my $data (
                    [<<'HERE', 'SomeProg'],
<?xml version="1.0"?>
<feed>
  <generator>SomeProg</generator>
  <entry><title>Item One</title></entry>
</feed>
HERE
                    [<<'HERE', 'SomeProg 2.0'],
<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <generator version="2.0">SomeProg</generator>
  <entry><title>Item One</title></entry>
</feed>
HERE
                    [<<'HERE', 'SomeProg http://some.where.com'],
<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <generator uri="http://some.where.com">
    SomeProg
  </generator>
  <entry><title>Item One</title></entry>
</feed>
HERE
                    [<<'HERE', 'SomeProg 2.0 http://some.where.com'],
<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <generator version="2.0" uri="http://some.where.com">SomeProg</generator>
  <entry><title>Item One</title></entry>
</feed>
HERE
                   ) {
    my ($xml, $want) = @$data;

    my ($twig, $err) = $r2l->twig_parse ($xml);
    if ($err) { diag $err; }
    my $item = ($twig->root->first_descendant('item')
                || $twig->root->first_descendant('entry')
                || die);

    is ($r2l->item_to_generator ($item),
        $want,
        "item_to_generator() xml=$xml");
  }
}


#------------------------------------------------------------------------------
# item_to_in_reply_to()

{
  my $r2l = App::RSS2Leafnode->new;

  foreach my $data
    (['<rss2leafnode.tag:%2C2010-02-09:something@foo.com>', <<'HERE'],
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:thr="http://purl.org/syndication/thread/1.0">
  <entry>
    <title>Item One</title>
    <updated>2006-03-01T12:12:12Z</updated>
    <thr:in-reply-to ref="tag:foo.com,2010-02-09:something" />
  </entry>
</feed>
HERE
                   ) {
    my ($want, $xml) = @$data;

    my ($twig, $err) = $r2l->twig_parse ($xml);
    if ($err) { diag $err; }
    my $item = ($twig->root->first_descendant('item')
                || $twig->root->first_descendant('entry')
                || die);

    is ($r2l->item_to_in_reply_to ($item),
        $want,
        "item_to_in_reply_to() xml=$xml");
  }
}


#------------------------------------------------------------------------------
# elt_xml_base()

{
  my $r2l = App::RSS2Leafnode->new;

  foreach my $data
    ([<<'HERE',
<?xml version="1.0"?>
<rss version="2.0" xml:base="http://foo.com/">
 <channel>
  <item/>
 </channel>
</rss>
HERE
      'http://foo.com/'],

     [<<'HERE',
<?xml version="1.0"?>
<rss version="2.0" xml:base="http://foo.com/">
 <channel>
  <item xml:base="/bar/"/>
 </channel>
</rss>
HERE
      'http://foo.com/bar/'],

     [<<'HERE',
<?xml version="1.0"?>
<rss version="2.0" xml:base="http://foo.com/subone">
 <channel>
  <item xml:base="/fromtop/"/>
 </channel>
</rss>
HERE
      'http://foo.com/fromtop/'],

     [<<'HERE',
<?xml version="1.0"?>
<rss version="2.0" xml:base="http://foo.com/subone/">
 <channel>
  <item xml:base="http://newhost.com/"/>
 </channel>
</rss>
HERE
      'http://newhost.com/'],

     [<<'HERE',
<?xml version="1.0"?>
<rss version="2.0" xml:base="/oops/relative/">
 <channel>
  <item xml:base="subdir/"/>
 </channel>
</rss>
HERE
      undef],  # '/oops/relative/subdir/'

     [<<'HERE',
<?xml version="1.0"?>
<rss version="2.0" xml:base="http://foo.com/dir/">
 <channel xml:base="subdir/">
  <item xml:base="../an/other/"/>
 </channel>
</rss>
HERE
      'http://foo.com/dir/an/other/'],

     [<<'HERE',
<?xml version="1.0"?>
<rss version="2.0" xml:base="http://foo.com/dir/">
 <channel xml:base="0/">
  <item xml:base="0.0/"/>
 </channel>
</rss>
HERE
      'http://foo.com/dir/0/0.0/'],

     [<<'HERE',
<?xml version="1.0"?>
<a:feed xmlns:a="http://www.w3.org/2005/Atom" xml:base="http://foo.com/dir/">
  <a:item a:foo="123" xml:base="0.0/"></a:item>
</a:feed>
HERE
      'http://foo.com/dir/0.0/']) {

    my ($xml, $want) = @$data;

    my ($twig, $err) = $r2l->twig_parse ($xml);
    my $item = ($twig->root->first_descendant('item')
                || $twig->root->first_descendant('entry')
                || die);

    my $got = App::RSS2Leafnode::elt_xml_base($item);
    is ($got, $want, "elt_xml_base() $xml");
  }
}


#------------------------------------------------------------------------------
# elt_xml_based_uri()

{
  my $r2l = App::RSS2Leafnode->new;

  foreach my $data
    ([<<'HERE',
<?xml version="1.0"?>
<rss version="2.0" xml:base="http://foo.com/">
 <channel>
  <link>index.html</link>
 </channel>
</rss>
HERE
      'http://foo.com/index.html'],

     [<<'HERE',
<?xml version="1.0"?>
<rss version="2.0" xml:base="http://foo.com/">
 <channel>
  <link xml:base="/bar/">index.html</link>
 </channel>
</rss>
HERE
      'http://foo.com/bar/index.html']) {

    my ($xml, $want) = @$data;

    my ($twig, $err) = $r2l->twig_parse ($xml);
    my $elt = $twig->root->first_descendant('link') // die;
    my $url = $elt->text;

    my $got = App::RSS2Leafnode::elt_xml_based_uri($elt, $url);
    is ($got, $want, "elt_xml_based_uri() $xml");
  }
}


#------------------------------------------------------------------------------
# twig_parse()

{
  my $r2l = App::RSS2Leafnode->new;
  my $xml = <<'HERE';
<?xml version="1.0"?>
<a:feed xmlns:a="http://www.w3.org/2005/Atom">
  <a:item a:foo="123"></a:item>
</a:feed>
HERE
  my ($twig, $err) = $r2l->twig_parse ($xml);
  {
    my $elt = $twig->root;
    is ($elt->tag, 'feed', 'twig_parse() <a:feed> stripped to <feed>');
  }
  {
    my $elt = $twig->root->first_descendant(qr/item/);
    is ($elt->tag, 'item',
        'twig_parse() <a:item> stripped to <item>');
    is_deeply ([$elt->att_names], ['atom:foo'],
               'twig_parse() a:foo="" left as atom:foo="" for now');
  }
}


#------------------------------------------------------------------------------
# elt_subtext()

{
  my $r2l = App::RSS2Leafnode->new;
  require URI;
  $r2l->{'uri'} = URI->new('http://feedhost.com');

  foreach my $data
    (# Atom
     [<<'HERE',
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item>
   <description>
    <p>This bit subelem.</p><br/>
    <![CDATA[This bit cdata.]]>
    <b><a href="page.html">This bit more subelem</a></b><br/>
   </description>
  </item>
 </channel>
</rss>
HERE
      '<p>This bit subelem.</p><br/>
    This bit cdata.
    <b><a href="page.html">This bit more subelem</a></b><br/>'],

    ) {
    my ($xml, $want) = @$data;

    my ($twig, $err) = $r2l->twig_parse ($xml);
    my $elt = $twig->root->first_descendant('description');

    my $got = App::RSS2Leafnode::elt_subtext($elt);
    foreach ($got, $want) {
      s/\s+/ /g;   # ignore different whitespace
      s/>\s+/>/g;
      s/\s+</</g;
    }

    is ($got, $want, "elt_subtext() $xml");
  }
}


#------------------------------------------------------------------------------
# uri_to_nntp_host()

{
  require URI;
  foreach my $data (['r2l.test', 'localhost:119'],
                    ['news:r2l.test', 'localhost:119'],
                    ['nntp:r2l.test', 'localhost:119'],

                    # default port
                    ['news://foo.com/r2l.test', 'foo.com:119'],
                    ['news://localhost/r2l.test', 'localhost:119'],
                    ['news:///r2l.test', 'localhost:119'],

                    # is this bogus ?
                    # ['news://foo.com:/r2l.test', 'foo.com:119'],

                    # explicit port
                    ['news://foo.com:8119/r2l.test', 'foo.com:8119'],
                    ['news://localhost:8119/r2l.test', 'localhost:8119'],
                    ['news://:8119/r2l.test', 'localhost:8119'],

                   ) {
    my ($uri_str, $want) = @$data;
    my $uri = URI->new ($uri_str, 'news');

    is (App::RSS2Leafnode::uri_to_nntp_host($uri),
        $want,
        "uri_to_nntp_host() $uri_str -> $uri");
  }
}

#------------------------------------------------------------------------------
# isodate_to_rfc822()

foreach my $data (['Sun, 29 Jan 2006 17:17:44 GMT',
                   'Sun, 29 Jan 2006 17:17:44 GMT'],
                  ['2000-01-01T12:00+00:00',
                   'Sat, 01 Jan 2000 12:00:00 +0000'],
                  ['2000-01-01T12:00Z',
                   'Sat, 01 Jan 2000 12:00:00 +0000'],
                  ['2000-01-01',
                   'Sat, 01 Jan 2000 00:00:00']) {
  my ($isodate, $want) = @$data;

  is (App::RSS2Leafnode::isodate_to_rfc822($isodate),
      $want,
      "isodate_to_rfc822() $isodate");
}


#------------------------------------------------------------------------------
# item_to_copyright()

{
  my $r2l = App::RSS2Leafnode->new;

  foreach my $data (
                    [<<'HERE', 'some thing'],
<?xml version="1.0"?>
<feed xmlns:dcterms="http://purl.org/dc/terms/">
  <entry><title>Item One</title>
         <dcterms:license>some thing</dcterms:license>
  </entry>
</feed>
HERE

                    [<<'HERE', 'some thing'],
<?xml version="1.0"?>
<feed xmlns:dc="http://purl.org/dc/elements/1.1/">
  <entry><title>Item One</title>
         <dc:rights>some thing</dc:rights>
  </entry>
</feed>
HERE

                    [<<'HERE', 'some thing'],
<?xml version="1.0"?>
<feed>
  <entry><title>Item One</title>
         <rights>some thing</rights>
  </entry>
</feed>
HERE

                    [<<'HERE', 'some thing'],
<?xml version="1.0"?>
<feed>
  <entry>
    <title>Item One</title>
    <source>
      <rights>some thing</rights>
    </source>
  </entry>
</feed>
HERE
                   ) {
    my ($xml, $want) = @$data;

    my ($twig, $err) = $r2l->twig_parse ($xml);
    if ($err) { diag $err; }
    my $item = ($twig->root->first_descendant('item')
                || $twig->root->first_descendant('entry')
                || die);

    is ($r2l->item_to_copyright ($item),
        $want,
        "item_to_copyright() xml=$xml");
  }
}


#------------------------------------------------------------------------------
# item_to_language()

{
  my $r2l = App::RSS2Leafnode->new;
  require HTTP::Response;

  foreach my $data (
                    # nothing
                    [<<'HERE', [], undef],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry><title>Item One</title></entry>
</feed>
HERE

                    # item <language>
                    [<<'HERE', [], 'de'],
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item><title>Item One</title>
        <language>de</language></item>
 </channel>
</rss>
HERE

                    # channel <language>
                    [<<'HERE', [], 'de'],
<?xml version="1.0"?>
<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <language>de</language>
  <item><title>Item One</title></item>
</rdf:RDF>
HERE

                    # <feed xml:lang="">
                    [<<'HERE', [], 'de'],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#" xml:lang="de">
  <entry><title>Item One</title></entry>
</feed>
HERE

                    # <item xml:lang="">
                    [<<'HERE', [], 'de'],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#" xml:lang="ja">
  <entry xml:lang="de"><title>Item One</title></entry>
</feed>
HERE

                    # <content xml:lang="">
                    [<<'HERE', [], 'de'],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#" xml:lang="ja">
  <entry xml:lang="ja">
    <title>Item One</title>
    <content xml:lang="de">Hello</content>
  </entry>
</feed>
HERE

                    # headers
                    [<<'HERE', ['Content-Language','ja'], 'ja'],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry><title>Item One</title></entry>
</feed>
HERE

                    # doubled header
                    [<<'HERE', ['Content-Language','ja','Content-Language','de'], 'ja'],
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry><title>Item One</title></entry>
</feed>
HERE
                   ) {
    my ($xml, $headers, $want) = @$data;

    my $resp = $r2l->{'resp'} = HTTP::Response->new (200, 'Ok', $headers);
    my ($twig, $err) = $r2l->twig_parse ($xml);
    if ($err) { diag $err; }
    my $item = ($twig->root->first_descendant('item')
                || $twig->root->first_descendant('entry')
                || die);

    is ($r2l->item_to_language ($item),
        $want,
        "item_to_language() xml=$xml headers=".$resp->headers->as_string);
  }
}


#------------------------------------------------------------------------------
# uri_to_host()

{
  my $r2l = App::RSS2Leafnode->new;
  require URI;

  foreach my $data ([ 'http://feedhost.com',            'feedhost.com'],
                    [ 'file://host.name/some/file.txt', 'host.name' ],
                    [ 'file:///some/file.txt',          'localhost' ],

                    # URI.pm object without host() method
                    [ 'data:,Foo',                      'localhost' ],
                   ) {
    my ($url, $want) = @$data;
    $r2l->{'uri'} = URI->new($url);

    is ($r2l->uri_to_host, $want,
        "uri_to_host() $url");
  }
}


#------------------------------------------------------------------------------
# elt_to_email()

{
  my $r2l = App::RSS2Leafnode->new;
  require URI;
  $r2l->{'uri'} = URI->new('http://feedhost.com');

  foreach my $data
    (# Atom
     ['<author><name>Foo Bar</name><email>foo@bar.com</email></author>',
      'Foo Bar <foo@bar.com>'],
     ['<author><name>00</name><email>foo@bar.com</email></author>',
      '00 <foo@bar.com>'],
     ['<author><name></name><email>foo@bar.com</email></author>',
      'foo@bar.com'],
     ['<author><email>foo@bar.com</email></author>',
      'foo@bar.com'],
     ['<author><email>00</email></author>',
      '00'],

     # Atom
     ['<author><name>Foo Bar</name><email></email></author>',
      'Foo Bar'],
     ['<author><name>Foo Bar</name></author>',
      'Foo Bar'],
     ["<author><name>Foo</name><email>
\t  foo\@bar.com\t
</email></author>",
      'Foo <foo@bar.com>'],

     # RSS
     ['<author>foo@bar.com (Foo)</author>',
      'foo@bar.com (Foo)'],
     ["<author>\t\nfoo\@bar.com\n\t(Foo)   </author>",
      'foo@bar.com (Foo)'],
     ['',
      undef],
    ) {
    my ($fragment, $want) = @$data;

    my $xml = <<"HERE";
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item><title>Item One</title> $fragment </item>
 </channel>
</rss>
HERE
    my ($twig, $err) = $r2l->twig_parse ($xml);
    my $elt = $twig->root->first_descendant('author');

    is (App::RSS2Leafnode::elt_to_email($elt),
        $want,
        "elt_to_email() $fragment");
  }
}


#------------------------------------------------------------------------------
# item_to_from()

{
  my $r2l = App::RSS2Leafnode->new;
  require URI;
  $r2l->{'uri'} = URI->new('http://feedhost.com');
  my $host = $r2l->{'uri'}->host;

  foreach my $data (['<author><name>Foo Bar</name><email>foo@bar.com</email></author>',
                     'Foo Bar <foo@bar.com>'],
                    ['<author><name>Foo Bar</name></author>',
                     'Foo Bar'],
                    ['<author><email>foo@bar.com</email></author>',
                     'foo@bar.com'],
                    ['<author></author>',
                     'nobody@'.$host],
                    ['',
                     'nobody@'.$host]) {
    my ($fragment, $want) = @$data;

    my $xml = <<"HERE";
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry><title>Item One</title> $fragment </entry>
</feed>
HERE
    my ($twig, $err) = $r2l->twig_parse ($xml);
    my $item = $twig->root->first_descendant('entry');

    is ($r2l->item_to_from ($item),
        $want,
        "item_to_from() $fragment");
  }
}


#------------------------------------------------------------------------------
# item_yahoo_permalink()

{
  my $r2l = App::RSS2Leafnode->new;

  foreach my $data
    ([ '<link>http://au.rd.yahoo.com/finance/news/rss/financenews/*http://au.biz.yahoo.com/071003/30/1fdvx.html</link>',
       'http://au.biz.yahoo.com/071003/30/1fdvx.html' ],
     [ '<link>http://something.else.com/*http://foo.com/blah.html</link>',
       undef ]) {
    my ($fragment, $want) = @$data;

    my $xml = <<"HERE";
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item>$fragment</item>
 </channel>
</rss>
HERE
    my ($twig, $err) = $r2l->twig_parse ($xml);
    my $item = ($twig->root->first_descendant('item')
                || $twig->root->first_descendant('entry')
                || die);

    is (App::RSS2Leafnode::item_yahoo_permalink($item),
        $want,
        "item_to_language() xml=$xml");
  }
}


#------------------------------------------------------------------------------
# html_title()

diag "html_title()";
{
  require HTTP::Response;
  require HTTP::Request;
  my $resp = HTTP::Response->new (200, 'OK', undef, <<'HERE');
<html><head></head>
<body> Hello </body> </html>
HERE
  $resp->request (HTTP::Request->new (GET => 'http://foobar.com/index.html'));
  $resp->content_type('text/html');
  my $str = App::RSS2Leafnode::html_title ($resp);
  is ($str, undef, 'html_title() no <title>');
}

#------------------------------------------------------------------------------
# html_title_urititle()

diag "html_title_urititle()";
SKIP: {
  eval { require URI::Title } or
    skip 'due to no URI::Title', 2;

  require HTTP::Response;
  require HTTP::Request;
  {
    my $resp = HTTP::Response->new (200, 'OK', undef, <<'HERE');
<html><head><title>A Page</title></head>
<body>Hello</body></html>
HERE
    $resp->request (HTTP::Request->new (GET=>'http://foobar.com/index.html'));
    $resp->content_type('text/html');
    my $str = App::RSS2Leafnode::html_title_urititle ($resp);
    is ($str, 'A Page', 'html_title_urititle() with <title>');
  }
  {
    my $resp = HTTP::Response->new (200, 'OK', undef, <<'HERE');
<html><head></head><body>Hello</body></html>
HERE
    $resp->request (HTTP::Request->new (GET=>'http://foobar.com/index.html'));
    $resp->content_type('text/html');
    my $str = App::RSS2Leafnode::html_title_urititle ($resp);
    is ($str, undef, 'html_title_urititle() no <title>');
  }
}

#------------------------------------------------------------------------------
# str_ensure_newline()

is (App::RSS2Leafnode::str_ensure_newline("foo"),     "foo\n");
is (App::RSS2Leafnode::str_ensure_newline("foo\n"),   "foo\n");
is (App::RSS2Leafnode::str_ensure_newline("foo\nbar"), "foo\nbar\n");
is (App::RSS2Leafnode::str_ensure_newline(""),     "\n");
is (App::RSS2Leafnode::str_ensure_newline("\n"),   "\n");
is (App::RSS2Leafnode::str_ensure_newline("\n\n"), "\n\n");


#------------------------------------------------------------------------------
# enforce_rss_charset_override()

diag "enforce_rss_charset_override()";
{
  my $r2l = App::RSS2Leafnode->new;
  my $xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>';
  is ($r2l->enforce_rss_charset_override($xml),
      $xml,
      'rss_charset_override not set, unchanged');

  $r2l->{'rss_charset_override'} = 'UTF-8';
  is ($r2l->enforce_rss_charset_override($xml),
      $xml,
      'rss_charset_override same UTF-8, unchanged');

  $r2l->{'rss_charset_override'} = 'iso-8859-1';
  is ($r2l->enforce_rss_charset_override($xml),
      '<?xml version="1.0" encoding="iso-8859-1" standalone="yes" ?>',
      'rss_charset_override change to iso-8859-1');
}
{
  my $r2l = App::RSS2Leafnode->new;
  my $xml = '<?xml version="1.0"?>';
  is ($r2l->enforce_rss_charset_override($xml),
      $xml,
      'rss_charset_override not set, unchanged');

  $r2l->{'rss_charset_override'} = 'UTF-8';
  is ($r2l->enforce_rss_charset_override($xml),
      '<?xml version="1.0" encoding="UTF-8"?>',
      'rss_charset_override UTF-8, insert');
}
{
  my $r2l = App::RSS2Leafnode->new;
  my $xml = '<rss version="2.0">';
  is ($r2l->enforce_rss_charset_override($xml),
      $xml,
      'rss_charset_override not set, unchanged');

  $r2l->{'rss_charset_override'} = 'utf-8';
  is ($r2l->enforce_rss_charset_override($xml),
      "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n$xml",
      'rss_charset_override utf-8, <?xml>');
}
{
  my $r2l = App::RSS2Leafnode->new;
  require Encode;
  my $xml = Encode::encode ('utf-32', '<?xml version="1.0"?>');
  is ($r2l->enforce_rss_charset_override($xml),
      $xml,
      'rss_charset_override on UTF-32 not set, unchanged');

  $r2l->{'rss_charset_override'} = 'UTF-32';
  my $got = $r2l->enforce_rss_charset_override($xml);
  my $want = Encode::encode ('utf-32',
                             '<?xml version="1.0" encoding="UTF-32"?>');
  is ($got, $want, 'rss_charset_override UTF-32, insert');
}

#------------------------------------------------------------------------------
# msgid_chars()

is (App::RSS2Leafnode::msgid_chars('abc'), 'abc');
is (App::RSS2Leafnode::msgid_chars('a/b-c!d~e.:'), 'a/b-c!d~e.:');
is (App::RSS2Leafnode::msgid_chars('a<b>%c'), 'a%3Cb%3E%25c');


#------------------------------------------------------------------------------
# url_to_msgid()

{
  require Sys::Hostname;
  foreach my $hostname_func (\&Sys::Hostname::hostname,
                             sub { "some.where.org" },
                             sub { "undotted" }) {
    no warnings 'redefine';
    local *Sys::Hostname::hostname = $hostname_func;
    use warnings;

    my $hostname = (eval { Sys::Hostname::hostname() }
                    // 'rss2leafnode.invalid');
    unless ($hostname =~ /\./) { $hostname .= '.withadot'; }

    my $r2l = App::RSS2Leafnode->new;

    foreach my $data
      (['http://foo.com/index.html','',
        '<rss2leafnode.http:///index.html@foo.com>'],
       ['http://FOO.COM/index.html','',
        '<rss2leafnode.http:///index.html@foo.com>'],

       ['http://1.2.3.4/index.html','',
        '<rss2leafnode.http:///index.html@1.2.3.4>'],
       ['http://[1080:0:0:0:8:800:200C:417A]/index.html','',
        '<rss2leafnode.http:///index.html@1080.0.0.0.8.800.200c.417a.ipv6>'],

       ['file:///foo/bar.html','Z',
        sub { "<rss2leafnode.file:///foo/bar.html.Z\@$hostname>" }],
       ['http://localhost','XX',
        sub { "<rss2leafnode.http:///.XX\@$hostname>" }],

       ['tag:foo.com,2010-02-09:something','',
        '<rss2leafnode.tag:%2C2010-02-09:something@foo.com>'],

      ) {
      my ($url, $extra, $want) = @$data;
      my $got = $r2l->url_to_msgid($url, $extra);
      if (ref $want) { $want = $want->(); }
      is ($got, $want,
          "url_to_msgid() url=$url extra=$extra");
    }
  }
}


#------------------------------------------------------------------------------
# item_to_msgid()

{
  my $r2l = App::RSS2Leafnode->new;
  require URI;
  $r2l->{'uri'} = URI->new('http://foo.com/feed.rss');

  foreach my $data
    (
     # explicit "false"
     ['<guid isPermaLink="false">1234</guid>',
      '<rss2leafnode.http:///feed.rss.1234@foo.com>'],
     # trimmed whitespace
     ["<guid isPermaLink=\"false\">  1234  \n</guid>",
      '<rss2leafnode.http:///feed.rss.1234@foo.com>'],

     # explicit "true"
     ['<guid isPermaLink="true">http://foo.com/page.html</guid>',
      '<rss2leafnode.http:///page.html@foo.com>'],

     # default "true"
     # (this one not for XML::RSS 1.47 as it wrongly takes the default false)
     ['<guid>http://foo.com/page.html</guid>',
      '<rss2leafnode.http:///page.html@foo.com>'],

     # using some MD5
     ['',
      '<rss2leafnode.http:///feed.rss.Yd8/ilmPOF2/2ZA%2BcNG16Q@foo.com>'],

     ['<id>urn:uuid:123456789</id>',
      '<rss2leafnode.urn:uuid:123456789@rss2leafnode.invalid>'],

    ) {
    my ($fragment, $want) = @$data;

    my $xml = <<"HERE";
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <title>Some Title</title>
  <item><title>Item One</title>
        <description>Some thing</description>
        $fragment</item>
 </channel>
</rss>
HERE
    my ($twig, $err) = $r2l->twig_parse ($xml);
    my $item = ($twig->root->first_descendant('item')
                || $twig->root->first_descendant('entry')
                || die);

    is ($r2l->item_to_msgid ($item),
        $want,
        "item_to_msgid() $xml");
  }
}

exit 0;

__END__

# {
#   my $top = MIME::Entity->build(Type           => $body_type,
#                                 Encoding       => '-SUGGEST',
#                                 Charset        => 'us-ascii',
#                                 Data           => "hello");
#   mime_body_append ($top->bodyhandle, "world");
#   ok ($top->bodyhandle->as_string, "hello\nworld\n");
# }
