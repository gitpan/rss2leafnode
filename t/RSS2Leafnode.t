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

use strict;
use warnings;
use Test::More tests => 84;

SKIP: { eval 'use Test::NoWarnings; 1'
          or skip 'Test::NoWarnings not available', 1; }

require App::RSS2Leafnode;


#------------------------------------------------------------------------------
# VERSION

{
  my $want_version = 18;
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
# isodate_to_rfc822()

foreach my $data (['Sun, 29 Jan 2006 17:17:44 GMT',
                   'Sun, 29 Jan 2006 17:17:44 GMT'],
                  ['2000-01-01T12:00+00:00',
                   'Sat, 01 Jan 2000 12:00:00 +0000'],
                  ['2000-01-01T12:00Z',
                   'Sat, 01 Jan 2000 12:00:00 +0000']) {
  my ($isodate, $want) = @$data;

  is (App::RSS2Leafnode::isodate_to_rfc822($isodate),
      $want,
      "isodate_to_rfc822() $isodate");
}


#------------------------------------------------------------------------------
# item_dc_date_to_pubdate()

{ my $dc = 'http://purl.org/dc/elements/1.1/';

  { my $item = { pubDate => 'Sun, 13 Apr 2008 13:58:33 +1000' };
    App::RSS2Leafnode::item_dc_date_to_pubdate($item);
    is ($item->{'pubDate'}, 'Sun, 13 Apr 2008 13:58:33 +1000');
  }
  { my $item = { $dc => { date => '2000-01-01T00:00+00:00' } };
    App::RSS2Leafnode::item_dc_date_to_pubdate($item);
    is ($item->{'pubDate'}, 'Sat, 01 Jan 2000 00:00:00 +0000');
  }
  { my $item = { $dc => { date => '2000-01-01T00:00-06:00' } };
    App::RSS2Leafnode::item_dc_date_to_pubdate($item);
    is ($item->{'pubDate'}, 'Sat, 01 Jan 2000 00:00:00 -0600');
  }
}

#------------------------------------------------------------------------------
# mailto_parens_to_angles()

# is (App::RSS2Leafnode::mailto_parens_to_angles('foo@bar.com'),
#     'foo@bar.com');
# is (App::RSS2Leafnode::mailto_parens_to_angles('Foo Bar'),
#     'Foo Bar');
# is (App::RSS2Leafnode::mailto_parens_to_angles('Foo Bar (mailto:foo@bar.com)'),
#     'Foo Bar <foo@bar.com>');


#------------------------------------------------------------------------------
# atom_person_to_email()

my $have_xml_atom_person = eval { require XML::Atom::Person; 1 };
if (! $have_xml_atom_person) {
  diag "XML::Atom::Person not available -- $@";
}

SKIP: {
  $have_xml_atom_person
    or skip 'XML::Atom::Person not available', 7;

  foreach my $data (['Foo Bar', 'foo@bar.com', 'Foo Bar <foo@bar.com>'],
                    ['00',      'foo@bar.com', '00 <foo@bar.com>'],
                    ['',        'foo@bar.com', 'foo@bar.com'],
                    [undef,     'foo@bar.com', 'foo@bar.com'],

                    ['Foo Bar', undef, 'Foo Bar'],
                    ['Foo Bar', '',    'Foo Bar'],
                    ['00',      '0',   '00 <0>'],
                   ) {
    my ($name, $email, $want) = @$data;

    my $person = XML::Atom::Person->new;
    if (defined $name)  { $person->name  ($name); }
    if (defined $email) { $person->email ($email); }

    is (App::RSS2Leafnode::atom_person_to_email($person),
        $want,
        ("atom_person_to_email() name=" . (defined $name ? "'$name'" : 'undef')
         . " email=" . (defined $email ? "'$email'" : 'undef')));
  }
}


#------------------------------------------------------------------------------
# uri_to_host()

{
  require URI;
  my $r2l = App::RSS2Leafnode->new;
  $r2l->{'uri'} = URI->new('http://feedhost.com');
  is ($r2l->uri_to_host, 'feedhost.com');

  $r2l->{'uri'} = URI->new('file://host.name/some/file.txt');
  is ($r2l->uri_to_host, 'host.name');

  $r2l->{'uri'} = URI->new('file:///some/file.txt');
  is ($r2l->uri_to_host, 'localhost');

  $r2l->{'uri'} = URI->new('data:,Foo');
  is ($r2l->uri_to_host, 'localhost');
}


#------------------------------------------------------------------------------
# item_to_from()

foreach my $xml_rss_class ('XML::RSS', 'XML::RSS::LibXML') {
 SKIP: {
    eval "require $xml_rss_class; 1"
      or skip "$xml_rss_class not available", 3;

    my $r2l = App::RSS2Leafnode->new;
    $r2l->{'uri'} = URI->new('http://feedhost.com');
    my $host = $r2l->{'uri'}->host;

    foreach my $data (['<author>foo@bar.com (Foo)</author>',
                       'foo@bar.com (Foo)'],
                      ["<author>\t\nfoo\@bar.com\n\t(Foo)   </author>",
                       'foo@bar.com (Foo)'],
                      ['',
                       'nobody@'.$host]) {
      my ($author, $want) = @$data;

      # Crib: XML::RSS::LibXML 0.3004 won't show an item with just an
      # <author>, there has to be a <title> too, or something like that
      my $xml = <<"HERE";
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item><title>Item One</title>
        $author</item>
 </channel>
</rss>
HERE
      my $feed = $xml_rss_class->new;
      $feed->parse($xml);
      my $items = $feed->{'items'};
      my $item = $items->[0];

      is ($r2l->item_to_from ($feed, $item),
          $want,
          "item_to_from() $xml_rss_class '$author'");
    }
  }
}

my $have_xml_atom_feed = eval { require XML::Atom::Feed };
if (! $have_xml_atom_feed) {
  diag "XML::Atom::Feed not available -- $@";
}

SKIP: {
  $have_xml_atom_feed
    or skip 'XML::Atom::Feed not available', 5;

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
    my ($author, $want) = @$data;

    my $xml = <<"HERE";
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry><title>Item One</title>
         $author</entry>
</feed>
HERE
    my $feed = XML::Atom::Feed->new (\$xml);
    my ($item) = $feed->entries;

    is ($r2l->item_to_from ($feed, $item),
        $want,
        "item_to_from() atom $author");
  }
}


#------------------------------------------------------------------------------
# item_to_subject()

foreach my $xml_rss_class ('XML::RSS', 'XML::RSS::LibXML') {
 SKIP: {
    eval "require $xml_rss_class; 1"
      or skip "$xml_rss_class not available", 4;

    foreach my $data (['<title>Item One</title>',
                       'Item One'],
                      ['<title></title>',
                       'no subject'],
                      ['<title>000</title>',
                       '000'],
                      ['',
                       'no subject']) {
      my ($title, $want) = @$data;

      my $xml = <<"HERE";
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <item>$title</item>
 </channel>
</rss>
HERE
      my $feed = $xml_rss_class->new;
      $feed->parse($xml);

      my $r2l = App::RSS2Leafnode->new;
      my $items = $feed->{'items'};
      my $item = $items->[0];

      is ($r2l->item_to_subject ($item),
          $want,
          "item_to_subject() $xml_rss_class $title");
    }
  }
}

SKIP: {
  $have_xml_atom_feed
    or skip 'XML::Atom::Feed not available', 4;

  my $r2l = App::RSS2Leafnode->new;
  my $host = 'some.where.com';

  foreach my $data (['<title>Item One</title>',
                     'Item One'],
                    ['<title></title>',
                     'no subject'],
                    ['<title>000</title>',
                     '000'],
                    ['',
                     'no subject']) {
    my ($title, $want) = @$data;

    my $xml = <<"HERE";
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#">
  <entry>$title</entry>
</feed>
HERE
    my $feed = XML::Atom::Feed->new (\$xml);
    my ($item) = $feed->entries;

    is ($r2l->item_to_subject ($item),
        $want,
        "item_to_subject() atom $title");
  }
}


#------------------------------------------------------------------------------
# item_to_language()

SKIP: {
  $have_xml_atom_feed
    or skip 'XML::Atom::Feed not available', 2;

  my $r2l = App::RSS2Leafnode->new;
  $r2l->{'resp'} = HTTP::Response->new;

  foreach my $data ([' xml:lang="en"', 'en'],
                    ['', undef]) {
    my ($lang, $want) = @$data;

    my $xml = <<"HERE";
<?xml version="1.0"?>
<feed version="0.3" xmlns="http://purl.org/atom/ns#" $lang>
  <entry><title>Item One</title></entry>
</feed>
HERE
    my $feed = XML::Atom::Feed->new (\$xml);
    my ($item) = $feed->entries;

    is ($r2l->item_to_language ($feed, $item),
        $want,
        "item_to_language() atom '$lang'");
  }
}


#------------------------------------------------------------------------------
# new()

{
  my $r2l = App::RSS2Leafnode->new;
  is ($r2l->{'verbose'}, 0, "new() verbose default value");
}
{
  my $r2l = App::RSS2Leafnode->new (verbose => 123);
  is ($r2l->{'verbose'}, 123, "new() verbose specified");
}


#------------------------------------------------------------------------------
# item_yahoo_permalink()

{
  my $item = { link => 'http://au.rd.yahoo.com/finance/news/rss/financenews/*http://au.biz.yahoo.com/071003/30/1fdvx.html' };
  is (App::RSS2Leafnode::item_yahoo_permalink($item),
      'http://au.biz.yahoo.com/071003/30/1fdvx.html');
}
{
  my $item = { link => 'http://something.else.com/*http://foo.com/blah.html' };
  is (App::RSS2Leafnode::item_yahoo_permalink($item),
      undef);
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
      '<?xml encoding="UTF-8" version="1.0"?>',
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
      "<?xml encoding=\"utf-8\"?>\n$xml",
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
  is ($r2l->enforce_rss_charset_override($xml),
      Encode::encode ('utf-32', '<?xml encoding="UTF-32" version="1.0"?>'),
      'rss_charset_override UTF-32, insert');
}

#------------------------------------------------------------------------------
# msgid_chars()

is (App::RSS2Leafnode::msgid_chars('abc'), 'abc');
is (App::RSS2Leafnode::msgid_chars('a/b-c!d~e.:'), 'a/b-c!d~e.:');
is (App::RSS2Leafnode::msgid_chars('a<b>%c'), 'a%3Cb%3E%25c');


#------------------------------------------------------------------------------
# url_to_msgid()

{
  my $r2l = App::RSS2Leafnode->new;

  my $hostname;
  {
    my $got = $r2l->url_to_msgid('http://localhost','XX');
    require Sys::Hostname;
    $hostname = Sys::Hostname::hostname();
    is ($got, "<rss2leafnode.http:/.XX\@$hostname>");
  }
  is ($r2l->url_to_msgid('file:///foo/bar.html','Z'),
      "<rss2leafnode.file:/foo/bar.html.Z\@$hostname>");
  is ($r2l->url_to_msgid('http://foo.com/index.html',''),
      "<rss2leafnode.http:/index.html\@foo.com>");
}


#------------------------------------------------------------------------------
# item_to_msgid()

foreach my $xml_rss_class ('XML::RSS', 'XML::RSS::LibXML') {
 SKIP: {
    eval "require $xml_rss_class; 1"
      or skip "$xml_rss_class not available", 3;

    foreach my $data
      (['<guid isPermaLink="false">1234</guid>',
        '<rss2leafnode.http:/feed.rss.1234@foo.com>'],

       ['<guid isPermaLink="true">http://foo.com/page.html</guid>',
        '<rss2leafnode.http:/page.html@foo.com>'],

       # XML::RSS 1.47 wrongly takes the default false
       # ['<guid>http://foo.com/page.html</guid>', # default true
       #  '<rss2leafnode.http:/page.html@foo.com>'],

       ['', # some MD5
        '<rss2leafnode.http:/feed.rss.Yd8/ilmPOF2/2ZA%2BcNG16Q@foo.com>'],

      ) {
      my ($guid, $want) = @$data;

      my $xml = <<"HERE";
<?xml version="1.0"?>
<rss version="2.0">
 <channel>
  <title>Some Title</title>
  <item><title>Item One</title>
        <description>Some thing</description>
        $guid</item>
 </channel>
</rss>
HERE
      my $r2l = App::RSS2Leafnode->new;
      $r2l->{'uri'} = 'http://foo.com/feed.rss';

      my $feed = $xml_rss_class->new;
      $feed->parse($xml);
      my $items = $feed->{'items'};
      my $item = $items->[0];

      is ($r2l->item_to_msgid ($item),
          $want,
          "item_to_msgid() $xml_rss_class $guid");
    }
  }
}


exit 0;

__END__

{
  my $top = MIME::Entity->build(Type           => $body_type,
                                Encoding       => '-SUGGEST',
                                Charset        => 'us-ascii',
                                Data           => "hello");
  mime_body_append ($top->bodyhandle, "world");
  ok ($top->bodyhandle->as_string, "hello\nworld\n");
}
