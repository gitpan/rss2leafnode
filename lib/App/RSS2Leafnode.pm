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

package App::RSS2Leafnode;
use 5.010;
use strict;
use warnings;
use Carp;
use Digest::MD5;
use Encode;
use List::Util;
use Scalar::Util;
use POSIX (); # ENOENT, etc
use URI;
use HTML::Entities::Interpolate;

our $VERSION = 23;

use Locale::TextDomain 1.16; # version 1.16 for turn_utf_8_on()
use Locale::TextDomain ('App-RSS2Leafnode');
BEGIN {
  use Locale::Messages;
  Locale::Messages::bind_textdomain_codeset ('App-RSS2Leafnode','UTF-8');
  Locale::Messages::bind_textdomain_filter ('App-RSS2Leafnode',
                                            \&Locale::Messages::turn_utf_8_on);
}

# Cribs:
#
# RSS
#   http://my.netscape.com/publish/help/
#       RSS 0.9 spec.
#   http://my.netscape.com/publish/help/mnn20/quickstart.html
#       RSS 0.91 spec.
#   http://purl.org/rss/1.0/
#       RSS 1.0 spec.
#
#   http://www.rssboard.org/rss-specification
#   http://www.rssboard.org/files/rss-2.0-sample.xml
#       RSS 2.0 spec and sample.
#
#   http://www.rssboard.org/rss-profile
#       "Best practices."
#   http://www.meatballwiki.org/wiki/ModWiki -- wiki
#   http://web.resource.org/rss/1.0/modules/slash/
#       
#
# Dublin Core
#   RFC 5013 -- summary
#   http://dublincore.org/documents/dcmi-terms/ -- dc/terms
#
# Atom
#   RFC 4287 -- Atom spec
#   RFC 3339 -- ISO timestamps as used in Atom
#   RFC 4685 -- "thr" threading extensions
#   http://diveintomark.org/archives/2004/05/28/howto-atom-id
#      Making an <id>
#
# URIs
#   RFC 1738, RFC 2396, RFC 3986 -- URI formats (news/nntp in 1738)
#   draft-ellermann-news-nntp-uri-11.txt -- news/nntp update
#   RFC 2732 -- ipv6 "[]" hostnames
#   RFC 2141 -- urn:
#   RFC 4122 -- uuid format (as under urn:uuid:)
#   RFC 4151 -- tag:
#
# XML
#   http://www.w3.org/TR/xmlbase/ -- xml:base
#
# Mail Messages
#   RFC 850, RFC 1036 -- News message format, inc headers and rnews format
#   RFC 2076, RFC 4021 -- headers summary.
#   RFC 1327 -- X.400 to RFC822 introducing Language header
#   RFC 2557 -- MHTML Content-Location
#   RFC 1864 -- Content-MD5 header
#   RFC 3282 -- Content-Language header
#   RFC 2369 -- List-Post header and friends
#   http://www3.ietf.org/proceedings/98dec/I-D/draft-ietf-drums-mail-followup-to-00.txt
#       Draft "Mail-Followup-To" header.
#
# RFC 977 -- NNTP
# RFC 2616 -- HTTP/1.1 Accept-Encoding header
# RFC 4642 -- NNTP with SSL
#
#
# For XML in Perl there's a few too many ways to do it!
#   - XML::Parser looks likely for stream/event processing, but its builtin
#     tree mode is very basic.
#   - XML::Twig extends XML::Parser to quite a good tree, though the docs
#     could be polished a bit.  It only does a subset of "XPath" but the
#     functions/regexps are more perl-like for matching, and there's various
#     handy shortcuts for common operations.
#   - XML::LibXML is the full blown libxml and is rather a lot to learn.
#     Because it's mainly C it's not easy to find where or how you're going
#     wrong when your code doesn't work.  libxml also seems stricter about
#     namespace matters than XML::Parser/XML::Twig.
#   - XML::RSS uses XML::Parser to build its own style tree of RSS,
#     including unifying differences among RSS/RDF 0.91, 1.0 and 2.0.
#     Nested elements seem to need specific handling in its code, which can
#     make it tricky for sub-element oddities.  A fair amount of it is about
#     writing RSS too.
#   - XML::RSS::LibXML uses libxml for XML::RSS compatible reading and
#     writing.  It seems to do better on unrecognised sub-elements.
#   - XML::Atom offers the basic Atom elements but doesn't seem to give
#     access to extra stuff that might be in a feed.
#   - XML::Feed tries to unify XML::RSS and XML::Atom but again doesn't seem
#     to go much beyond the basics.  It too is geared towards writing as
#     well as reading.
# So the choice of XML::Twig is based on wanting both RSS and Atom, but
# XML::Feed not going far enough.  Tree processing is easier than stream,
# and an RSS isn't meant to be huge.  A tree may help if channel fields
# follow items or something equally unnatural.  Then between the tree styles
# XML::LibXML is harder to get into than Twig.
#

#------------------------------------------------------------------------------
# generic

# return $str with a newline at the end, if it doesn't already have one
sub str_ensure_newline {
  my ($str) = @_;
  if ($str !~ /\n$/) { $str .= "\n" }
  return $str;
}

sub md5_of_utf8 {
  my ($str) = @_;
  return Digest::MD5::md5_base64 (Encode::encode_utf8 ($str));
}

sub launder {
  my ($str) = @_;
  my %laundry = ($str=>1);
  return keys %laundry;
}

sub is_empty {
  my ($str) = @_;
  return (! defined $str || $str =~ /^\s*$/);
}
sub is_non_empty {
  my ($str) = @_;
  return ! is_empty($str);
}
sub non_empty {
  my ($str) = @_;
  return (is_non_empty($str) ? $str : ());
}

sub join_non_empty {
  my $sep = shift;
  return non_empty (join($sep, map {non_empty($_)} @_));
}

sub trim_whitespace {
  my ($str) = @_;
  defined $str or return;
  $str =~ s/^\s+//; # leading whitespace
  $str =~ s/\s+$//; # trailing whitespace
  return $str;
}

sub collapse_whitespace {
  my ($str) = @_;
  $str =~ s/(\s+)/($1 eq '  ' ? $1 : ' ')/ge;
  return trim_whitespace($str);
}

sub _choose {
  my @choices = @_;
  # require Data::Dumper;
  # print Data::Dumper->new([\@choices],['choices'])->Dump;
  foreach my $str (@choices) {
    is_non_empty($str) or next;
    $str = trim_whitespace($str);
    next if $str eq '';
    return $str;
  }
  return;
}

#------------------------------------------------------------------------------

sub new {
  my $class = shift;
  return bless {
                # config variables
                verbose         => 0,
                render          => 0,
                render_width    => 60,
                rss_get_links   => 0,
                rss_newest_only => 0,
                html_charset_from_content => 0,

                # secret variables
                msgidextra      => '',

                @_
               }, $class;
}

sub command_line {
  my ($self) = @_;

  my $done_version;
  require Getopt::Long;
  Getopt::Long::GetOptions
      ('config=s'   => \$self->{'config_filename'},
       'verbose:1'  => \$self->{'verbose'},
       'version'    => sub {
         print __x("RSS2Leafnode version {version}\n",
                   version => $VERSION);
         $done_version = 1;
       },
       'bareversion'  => sub {
         print "$VERSION\n";
         $done_version = 1;
       },
       'msgid=s'      => \$self->{'msgidextra'},
       'help|?' => sub {
         print "rss2leafnode [--options]\n";
         print "   --config=filename   configuration file (default ~/.rss2leafnode.conf)\n";
         print "   --help       print this help\n";
         print "   --verbose    describe what's done\n";
         print "   --verbose=2  show technical details of what's done\n";
         print "   --version    print program version number\n";
         exit 0;
       })or return 1;
  if (! $done_version) {
    $self->do_config_file;
    $self->nntp_close;
  }
  return 0;
}

sub homedir {
  my ($self) = @_;
  require File::HomeDir;
  return File::HomeDir->my_home
    // croak 'File::HomeDir says you have no home directory';
}
sub config_filename {
  my ($self) = @_;
  return $self->{'config_filename'} // do {
    require File::Spec;
    File::Spec->catfile ($self->homedir, '.rss2leafnode.conf');
  };
}
sub status_filename {
  my ($self) = @_;
  return $self->{'status_filename'} // do {
    require File::Spec;
    File::Spec->catfile ($self->homedir, '.rss2leafnode.status');
  };
}

sub do_config_file {
  my ($self) = @_;
  my @guards;

  open STDERR, '>&STDOUT' or die "Oops, can't join STDERR to STDOUT";

  if ($self->{'verbose'} >= 2) {
    require Scope::Guard;
    {
      # File::Temp::DEBUG for possible temp files used by HTML::FormatExternal
      require File::Temp;
      my $old = $File::Temp::DEBUG;
      push @guards, Scope::Guard->new (sub { $File::Temp::DEBUG = $old });
      $File::Temp::DEBUG = 1;
    }
    {
      require MIME::Tools;
      my $old = MIME::Tools->debugging;
      push @guards, Scope::Guard->new (sub { MIME::Tools->debugging($old) });
      MIME::Tools->debugging(1);
    }
    # require LWP::Debug;
    # LWP::Debug::level('+trace');
    # LWP::Debug::level('+debug');
  }

  my $config_filename = $self->config_filename;
  if ($self->{'verbose'}) { print "config: $config_filename\n"; }

  require App::RSS2Leafnode::Conf;
  local $App::RSS2Leafnode::Conf::r2l = $self;
  if (! defined (do { package App::RSS2Leafnode::Conf;
                      do $config_filename;
                    })) {
    if (! -e $config_filename) {
      croak "rss2leafnode: config file $config_filename doesn't exist\n";
    } else {
      croak $@;
    }
  }
}

#------------------------------------------------------------------------------
# UserAgent

sub ua {
  my ($self) = @_;
  return ($self->{'ua'} ||= do {
    require LWP::UserAgent;
    LWP::UserAgent->VERSION(5.832);  # 5.832 for content_charset()

    # one connection kept alive
    my $ua = LWP::UserAgent->new (keep_alive => 1);
    $ua->agent('RSS2leafnode/' . $self->VERSION . ' ');
    $ua->add_handler
      (request_send => sub {
         my ($req, $ua, $h) = @_;
         if ($self->{'verbose'} >= 2) { print "request_send:\n"; $req->dump; }
         return;
       });

    # ask for everything decoded_content() can cope with, in particular "gzip"
    # and "deflate" compression if Compress::Zlib or whatever is available
    #
    require HTTP::Message;
    my $decodable = HTTP::Message::decodable();
    if ($self->{'verbose'} >= 2) { print "HTTP decodable: $decodable\n"; }
    $ua->default_header ('Accept-Encoding' => $decodable);

    $ua
  });
}


#------------------------------------------------------------------------------
# dates

use constant RFC822_STRFTIME_FORMAT => '%a, %d %b %Y %H:%M:%S %z';

# return a string which is current time in RFC 822 format
sub rfc822_time_now {
  return POSIX::strftime (RFC822_STRFTIME_FORMAT, localtime(time()));
}

sub isodate_to_rfc822 {
  my ($isodate) = @_;
  my $date = $isodate // return;  # the original goes through if unrecognised

  if ($isodate =~ /\dT\d/ || $isodate =~ /^\d{4}-\d{2}-\d{2}$/) {
    # eg. "2000-01-01T12:00+00:00"
    #     "2000-01-01T12:00:00Z"
    #     "2000-01-01"
    my $zonestr = ($isodate =~ s/([+-][0-9][0-9]):([0-9][0-9])$// ? " $1$2"
                   : $isodate =~ s/Z$// ? ' +0000'
                   : '');
    require Date::Parse;
    my $time_t = Date::Parse::str2time($isodate);
    if (defined $time_t) {
      $date = POSIX::strftime ("%a, %d %b %Y %H:%M:%S$zonestr",
                               localtime ($time_t));
    }
  }
  return $date;
}

# $a and $b are XML::Twig::Elt items
# Return the one with the greatest date, or $a if they're equal or don't
# both have a pubDate.
#
sub item_date_max {
  my ($self, $a_item, $b_item) = @_;

  # prefer $a_item if both undef so as to get first in feed
  my $b_time = $self->item_to_timet($b_item) // return $a_item;
  my $a_time = $self->item_to_timet($a_item) // return $b_item;

  if ($b_time > $a_time) {
    return $b_item;
  } else {
    return $a_item;
  }
}
sub item_to_timet {
  my ($self, $item) = @_;
  my $str = $self->item_to_date($item) // return;
  require Date::Parse;
  my $timet = Date::Parse::str2time($str) // do {
    print __x("Ignoring unrecognised date \"{date}\" from {url}\n",
              date => $str,
              url => $self->{'uri'});
    return;
  };
  return $timet;
}

# Return an RFC822 date string, or undef if nothing known.
# This gets a sensible sort-by-date in the newsreader.
sub item_to_date {
  my ($self, $item) = @_;
  my $date;
  foreach my $elt ($item, item_to_channel($item)) {
    $date = (non_empty    ($elt->first_child_text('pubDate'))
             // non_empty ($elt->first_child_text('dc:date'))
             # Atom
             // non_empty ($elt->first_child_text('modified'))
             // non_empty ($elt->first_child_text('updated'))
             // non_empty ($elt->first_child_text('issued'))
             // non_empty ($elt->first_child_text('created'))
             # channel
             // non_empty ($elt->first_child_text('lastBuildDate')));
    last if defined $date;
  }
  return isodate_to_rfc822($date);
}

#-----------------------------------------------------------------------------
# Message-ID

# Return a message ID for something at $uri, optionally uniquified by $str.
# $uri is either a URI object or a url string.
# Weird chars in $uri or $str are escaped as necessary.
# Secret $self->{'msgidextra'} can make different message ids for the same
# content when testing.
#
# The path from $uri is incorporated in the result.  fetch_html() needs this
# since the ETag identifier is only per-url, not globally unique.  Suspect
# fetch_rss() needs it for a guid too (a non-permaLink one), as think the
# guid is only unique within the particular $uri feed, not globally and not
# even across multiple feeds on the same server.
#
sub url_to_msgid {
  my ($self, $url, $str) = @_;

  my $host;
  my $pathbit = $url;

  if (my $uri = eval { URI->new($url) }) {
    $uri = $uri->canonical;
    if ($uri->can('host')) {
      $host = $uri->host;
      $uri->host('');
      $pathbit = $uri->as_string;

      # If the $uri schema has a host part but it's empty or "localhost"
      # then try expanding that to hostname().
      #
      # $uri schemas without a host part, like "urn:" in an Atom <id> don't
      # get hostname(), since want the generated msgid to come out the same
      # if such a urn: appears from different downloaded locations.
      #
      if (is_empty($host) || $host eq 'localhost') {
        require Sys::Hostname;
        eval { $host = Sys::Hostname::hostname() };
      }

    } elsif ($uri->can('authority')) {
      # the "authority" part of a "tag:" schema
      $host = $uri->authority;
      $uri->authority('');
      $pathbit = $uri->as_string;
    }
  }

  # $host can be empty if running from a file:///
  # "localhost" is a bit bogus and in particular leafnode won't accept it.
  if (is_empty($host) || $host eq 'localhost') {
    $host = 'rss2leafnode.invalid';
  }

  # ipv6 dotted hostname "[1234:5678::0000]" -> "1234.5678.0000..ipv6",
  # because [ and : are not allowed (RFC 2822 "Atom" atext)
  # $uri->canonical above lower cases any hex, for consistency
  if (($host =~ s/^\[|\]$//g) | ($host =~ tr/:/./)) {
    $host .= '.ipv6';
  }

  # leafnode 2.0.0.alpha20070602a seems to insist on a "." in the host name
  unless ($host =~ /\./) {
    $host .= '.withadot';
  }

  return ('<'
          . msgid_chars(join_non_empty('.',
                                       "rss2leafnode" . $self->{'msgidextra'},
                                       $pathbit,
                                       $str))
          . '@'
          . msgid_chars($host)
          . '>');
}
# msgid_chars($str) returns $str with invalid Message-ID characters munged.
# Per RFC850 must be printing ascii and not < > or whitespace, but for
# safety reduce that a bit, in particular excluding ' and ".
sub msgid_chars {
  my ($str) = @_;
  require URI::Escape;
  return URI::Escape::uri_escape_utf8 ($str, "^A-Za-z0-9\\-_.!~*/:");
}

#------------------------------------------------------------------------------
# news posting
#
# This used to run the "rnews" program, which in leafnode 2 does some direct
# writing to the spool.  But that requires user "news" perms, and as of the
# June 2007 leafnode beta it tends to be a good deal slower because it reads
# the whole groupinfo file.  It has the advantage of not being picky about
# message ID hostnames, and allowing read-only groups to be filled.  But
# apart from that plain POST seems much easier for being "server neutral".
#
# IHAVE instead of POST would be a possibility, when available, though POST
# is probably more accurate in the sense it's a new article coming into the
# news system.
#
# Net::NNTP looks at $ENV{NNTPSERVER}, $ENV{NEWSHOST} and Net::Config
# nntp_hosts list for the news server.  Maybe could have that here too,
# instead of always defaulting to localhost (in $self->{'nntp_host'}).
# Would want to find out the name chosen to show in diagnostics though.

# return a string "host:port", suitable for the Host arg to Net::NNTP->new
sub uri_to_nntp_host {
  my ($uri) = @_;
  return _choose ($uri->host, 'localhost') . ':' . $uri->port;
}

sub nntp {
  my ($self) = @_;
  # reopen if different 'nntp_host'
  if (! $self->{'nntp'}
      || $self->{'nntp'}->host ne $self->{'nntp_host'}) {
    my $host = $self->{'nntp_host'};
    if ($self->{'verbose'} >= 1) {
      print __x("nntp: {host}\n", host => $host);
    }
    require Net::NNTP;
    my $nntp = $self->{'nntp'}
      = Net::NNTP->new ($host, ($self->{'verbose'} >= 2
                                ? (Debug => 1)
                                : ()));
    if (! $nntp) {
      croak __x("Cannot connect to NNTP on \"{host}\"\n", host => $host);
    }
    if ($self->{'verbose'} >= 1) {
      if (! $nntp->postok) {
        print "Hmm, ", $nntp->host, " doesn't say \"posting ok\" ...\n";
      }
    }
  }
  return $self->{'nntp'};
}

sub nntp_close {
  my ($self) = @_;
  if (my $nntp = delete $self->{'nntp'}) {
    if (! $nntp->quit) {
      print "Error closing nntp: ",$self->{'nntp'}->message,"\n";
    }
  }
}

# check that $group exists in the NNTP, return 1 if so, or 0 if not
sub nntp_group_check {
  my ($self, $group) = @_;
  my $nntp = $self->nntp;
  if (! $nntp->group($group)) {
    print __x("rss2leafnode: no group \"{group}\" on host \"{host}\"
You must create it as a local newsgroup.  For leafnode 2 this means
adding a line to /etc/news/leafnode/local.groups like

{group}\ty

Note it must be a tab character between the name and the \"y\".
See \"LOCAL NEWSGROUPS\" in the leafnode README file for more information.
",
  host => $nntp->host,
  group => $group);
    return 0;
  }

  return 1;
}

sub nntp_message_id_exists {
  my ($self, $msgid) = @_;
  my $ret = $self->nntp->nntpstat($msgid);
  if ($self->{'verbose'} >= 2) {
    print "'$msgid' ", ($ret ? "exists already\n" : "new\n");
  } elsif ($self->{'verbose'} >= 1) {
    if ($ret) { print __("  exists already\n"); }
  }
  return $ret;
}

# post $msg to NNTP, return true if successful
sub nntp_post {
  my ($self, $msg) = @_;
  my $nntp = $self->nntp;
  if (! $nntp->post ($msg->as_string)) {
    print __x("Cannot post: {message}\n",
              message => $nntp->message);
    return 0;
  }
  return 1;
}


#------------------------------------------------------------------------------
# HTML title

# $resp is a HTTP::Response, return title per URI::Title or $resp->title.
# The latter is either the obsolete "Title" header or parsed from <title>.
# In both cases entities &foo; are undone so the return is plain.
# Return undef if nothing known.
#
sub html_title {
  my ($resp) = @_;
  return (html_title_urititle($resp) // $resp->title);
}
sub html_title_urititle {
  my ($resp) = @_;
  eval { require URI::Title }
    or return;

  # suppress some dodginess in URI::Title 1.82
  local $SIG{'__WARN__'} = sub {
    my ($msg) = @_;
    $msg =~ /Use of uninitialized value/ or warn @_;
  };
  return URI::Title::title
    ({ url  => ($resp->request->uri // ''),
       data => $resp->decoded_content (charset => 'none')});
}


#------------------------------------------------------------------------------
# mime

# $body is a MIME::Body object, append $str to it
sub mime_body_append {
  my ($body, $str) = @_;
  $str = $body->as_string . "\n" . str_ensure_newline ($str);
  my $IO = $body->open('w')
    or die "rss2leafnode: body I/O open: $!";
  $IO->print ($str);
  $IO->close
    or die "rss2leafnode: body I/O close: $!";
}

# $top is a MIME::Entity object, add RSS2Leafnode to the X-Mailer field
sub mime_mailer_rss2leafnode {
  my ($self, $top) = @_;
  $top->head->replace('X-Mailer',
                      "RSS2Leafnode " . $self->VERSION
                      . ", " . $top->head->get('X-Mailer'));
}

sub mime_build {
  my ($self, $headers, @args) = @_;

  my $now822 = rfc822_time_now();
  $headers->{'Date'} //= $now822;

  # Headers in utf-8, the same as other text.  The docs of
  # encode_mimewords() isn't clear, but seems to expect bytes of the
  # specified charset.
  require MIME::Words;
  foreach my $key (sort keys %$headers) {
    if (defined (my $value = $headers->{$key})) {
      if ($value =~ /[^[:ascii:]]|[[:cntrl:]]/) {
        # non-ascii or control char present
        $value = MIME::Words::encode_mimewords (Encode::encode_utf8($value),
                                                Charset => 'UTF-8');
      }
      push @args, $key, $value;
    }
  }

  require MIME::Entity;
  my $top = MIME::Entity->build ('Date-Received:' => $now822,
                                 Encoding         => '-SUGGEST',
                                 @args);
  $self->mime_mailer_rss2leafnode ($top);
  return $top;
}

#------------------------------------------------------------------------------
# LWP stuff

# $resp is a HTTP::Response object.  Modify its headers to apply our
# $html_charset_from_content option, which means if it's set then prefer the
# document's Content-Type over what the server says.
#
# The LWP::UserAgent parse_head option appends the document <META> bits to
# the message headers.  If the server and the document both offer a
# Content-Type then there's two, with the document one last, so all we have
# to do is change to make the last one the only one.
#
sub enforce_html_charset_from_content {
  my ($self, $resp) = @_;
  if ($self->{'html_charset_from_content'}
      && $resp->content_type eq 'text/html') {
    my @cts = $resp->header('Content-Type');
    if ($#cts >= 1) {                         # if 2 or more,
      $resp->header('Content-Type',$cts[-1]); # then use the last
      if ($self->{'verbose'} >= 2) {
        require Data::Dumper;
        print "html_charset_from_content enforce last among ",
          Data::Dumper->new([\@cts],['content_types'])->Dump;
      }
    }
  }
}


#------------------------------------------------------------------------------
# XML::Twig stuff

# Return a URI object for string $url.
# If $url is relative then it's resolved against xml:base, if available, to
# make it absolute.
# If $url is undef then return undef, which is handy if passing a possibly
# attribute like $elt->att('href').
#
sub elt_xml_based_uri {
  my ($elt, $url) = @_;
  if (! defined $url) { return undef; }
  $url = URI->new ($url);
  if (my $base = elt_xml_base ($elt)) {
    return $url->abs ($base);
  } else {
    return $url;
  }
}

# Return a URI object for the xml:base applying to $elt, or undef.
sub elt_xml_base {
  my ($elt) = @_;
  my @relative;
  for ( ; $elt; $elt = $elt->parent) {
    next if ! defined (my $base = $elt->att('xml:base'));
    $base = URI->new($base);
    if (defined $base->scheme) {
      # an absolute URL
      while (@relative) {
        $base = (pop @relative)->abs($base);
      }
      return $base;
    } else {
      # a relative path
      push @relative, $base;
    }
  }
  # oops, no base, only relative paths
  return undef;
}

# Return the text of $elt, but with the whole xml of any child elements.
#
# This helps html sub-elements like <description>.  They're supposed to be
# just html text, with <p> etc escaped as &lt;p&gt;, but have seen
# sub-elements for instance Feb 2010 http://www.drweil.com/drw/ecs/rss.xml,
# though maybe with sub-entites still doubled like &amp;nbsp;.
#
# FIXME: Any need to watch out for <rdf:value> types?
#
sub elt_subtext {
  my ($elt) = @_;
  defined $elt or return;
  if ($elt->is_text) { return $elt->text; }
  return join ('',
               map {$_->is_text ? $_->text : $_->sprint} $elt->children);
}

# $elt is an XML::Twig::Elt of an RSS or Atom text element.
# Atom has a type="" attribute, RSS is html.  Html or xhtml are rendered to
# a single long line of plain text.
#
sub elt_to_rendered_line {
  my ($elt) = @_;
  defined $elt or return;

  my $str;
  my $type = elt_text_type ($elt);
  if ($type eq 'html' || $type eq 'xhtml') {
    if ($type eq 'xhtml') {
      $str = elt_xhtml_to_html ($elt);
    } else {
      # default to html if no type specified
      $str = elt_subtext($elt);
    }
    require HTML::FormatText;
    $str = HTML::FormatText->format_string ($str,
                                            leftmargin => 0,
                                            rightmargin => 999);
  } else {
    # plain text
    $str = elt_subtext($elt); # just in case unescaped stuff
  }
  return non_empty(collapse_whitespace($str));
}

sub elt_text_type {
  my ($elt) = @_;
  my $type = ($elt->att('atom:type')
              // $elt->att('type')
              # Atom <feed> default text, RSS default html
              // ($elt->root->tag eq 'feed' ? 'text' : 'html'));
  # saw type="application/xhtml+xml" at http://xmltwig.com/blog/index.atom,
  # dunno if it should be just "xhtml", but allow it anyway
  given ($type) {
    when ('application/xhtml+xml') { $type = 'xhtml'; }
  }
  return $type;
}

# $elt contains xhtml <div> etc sub-elements, return a plain html string.
# Can have prefixes like <xhtml:b>Bold</xhtml:b>, strip them to plain <b>.
# This relies on map_xmlns mapping to prefix "xhtml:"
#
sub elt_xhtml_to_html {
  my ($elt) = @_;
  $elt = $elt->copy;
  foreach my $child ($elt->descendants) {
    if ($child->ns_prefix eq 'xhtml') {
      $child->set_tag ($child->local_name);
    }
    # something fishy ups "href" to "xhtml:href", drop it down again to "href"
    foreach my $attname ($child->att_names) {
      if ($attname =~ /^xhtml:(.*)/) {
        $child->change_att_name($attname, $1);
      }
    }
  }
  return $elt->xml_string;
}


#------------------------------------------------------------------------------
# XML::RSS::Timing

sub channel_to_timingfields {
  my ($self, $twig) = @_;
  return if ! defined $twig;
  my $root = $twig->root;
  my %timingfields;

  if (my $ttl = $root->first_descendant('ttl')) {
    $timingfields{'ttl'} = $ttl->text;
  }
  if (my $skipHours = $root->first_descendant('skipHours')) {
    $timingfields{'skipHours'} = [map {$_->text} $skipHours->children('hour')];
  }
  if (my $skipDays = $root->first_descendant('skipDays')) {
    $timingfields{'skipDays'} = [map {$_->text} $skipDays->children('day')];
  }

  # "syn:updatePeriod" etc
  foreach my $key (qw(updatePeriod updateFrequency updateBase)) {
    if (my $update = $root->first_descendant("syn:$key")) {
      $timingfields{$key} = $update->text;
    }
  }
  if ($self->{'verbose'} >= 2) {
    require Data::Dumper;
    print Data::Dumper->new([\%timingfields],['timingfields'])
      ->Indent(1)->Sortkeys(1)->Dump;
  }

  # if XML::RSS::Timing doesn't like the values then don't record them
  return unless $self->timingfields_to_timing(\%timingfields);

  return \%timingfields;
}

# return an XML::RSS::Timing object, or undef
sub timingfields_to_timing {
  my ($self, $timingfields) = @_;
  eval { require XML::RSS::Timing } || return undef;
  my $timing = XML::RSS::Timing->new;
  $timing->use_exceptions(0);
  while (my ($key, $value) = each %$timingfields) {
    if (ref $value) {
      $timing->$key (@$value);
    } else {
      $timing->$key ($value);
    }
  }
  if (my @complaints = $timing->complaints) {
    print __x("XML::RSS::Timing complains on {url}\n",
              url => $self->{'uri'});
    foreach my $complaint (@complaints) {
      print "  $complaint\n";
    }
    return undef;
  }
  return $timing;
}


#------------------------------------------------------------------------------
# rss2leafnode.status file

# $self->{'global_status'} is a hashref containing entries URL => STATUS,
# where URL is a string and STATUS is a sub-hashref of information

# read $status_filename into $self->{'global_status'}
sub status_read {
  my ($self) = @_;
  $self->{'global_status'} = {};
  my $status_filename = $self->status_filename;
  if ($self->{'verbose'} >= 2) { print "read status: $status_filename\n"; }

  if (! defined (do $status_filename)) {
    if ($! == POSIX::ENOENT()) {
      if ($self->{'verbose'} >= 2) { print "status file doesn't exist\n"; }
    } else {
      print "rss2leafnode: error in $status_filename\n$@\n";
      print "ignoring that file\n";
    }
    $self->{'global_status'} = {};
  }
}

# save $self->{'global_status'} into the $status_filename
sub status_save {
  my ($self, $status) = @_;
  $status->{'status-time'} = $status->{'timingfields'}->{'lastPolled'} =time();

  require Data::Dumper;
  my $str = Data::Dumper->new([$self->{'global_status'}],['global_status'])
    ->Indent(1)->Sortkeys(1)->Useqq(1)->Dump;
  $str = <<"HERE";
# rss2leafnode status file -- automatically generated -- DO NOT EDIT
#
# (If there seems to be something very wrong then you can delete this file
# and it'll be started afresh on the next run.)

$str


# Local variables:
# mode: perl-mode
# End:
HERE

  my $status_filename = $self->status_filename;
  my $out;
  (open $out, '>', $status_filename
   and print $out $str
   and close $out)
    or croak "rss2leafnode: cannot write to $status_filename: $!\n";
}

# return a hashref which has status information about $url, or undef if
# nothing recorded about $url
sub status_geturl {
  my ($self, $url) = @_;
  $self->status_read if ! $self->{'global_status'};
  if (! $self->{'global_status'}->{$url}) {
    $self->{'global_status'}->{$url} = { 'status-time' => time() };
  }
  return $self->{'global_status'}->{$url};
}

# $resp is a HTTP::Response object from retrieving $url.
# Optional $channel is an XML::Twig.
# Record against $url any ETag, Last-Modified and ttl from $resp and $twig.
# If $resp is an error return, or is undef, then do nothing.
sub status_etagmod_resp {
  my ($self, $url, $resp, $twig) = @_;
  if ($resp && $resp->is_success) {
    my $status = $self->status_geturl ($url);
    $status->{'Last-Modified'} = $resp->header('Last-Modified');
    $status->{'ETag'}          = $resp->header('ETag');
    $status->{'timingfields'}  = $self->channel_to_timingfields ($twig);
    $self->status_save($status);
  }
}

# update recorded status for a $url with unchanged contents
sub status_unchanged {
  my ($self, $url) = @_;
  if ($self->{'verbose'} >= 1) { print __("  unchanged\n"); }
  $self->status_save ($self->status_geturl ($url));
}

# $req is a HTTP::Request object.
# Add "If-None-Match" and/or "If-Modified-Since" headers to it based on what
# the status file has recorded from when we last fetched the url in $req.
# Return 1 to download, 0 if nothing expected yet by RSS timing fields
#
sub status_etagmod_req {
  my ($self, $req) = @_;
  $self->{'global_status'} or $self->status_read;

  my $url = $req->uri;
  my $status = $self->{'global_status'}->{$url}
    or return 1; # no information about $url, download it

  if (my $timing = $self->timingfields_to_timing ($status->{'timingfields'})) {
    my $next = $timing->nextUpdate;
    my $now = time();
    if ($next > $now) {
      if ($self->{'verbose'} >= 1) {
        print __x(" timing: next update {time} (local time)\n",
                  time => POSIX::strftime ("%H:%M:%S %a %d %b %Y",
                                           localtime($next)));
        if (eval 'use Time::Duration::Locale; 1'
            || eval 'use Time::Duration; 1') {
          print "         which is ",duration($next-$now)," from now\n";
        }
      }
      return 0; # no update yet
    }
  }
  if (my $lastmod = $status->{'Last-Modified'}) {
    $req->header('If-Modified-Since' => $lastmod);
  }
  if (my $etag = $status->{'ETag'}) {
    $req->header('If-None-Match' => $etag);
  }
  return 1;
}


#------------------------------------------------------------------------------
# render html

# $content_type is a string like "text/html" or "text/plain".
# $content is data as raw bytes.
# $charset is the character set of those bytes, eg. "utf-8".
#
# If the $render option is set, and $content_type is 'text/html', then
# render $content down to 'text/plain', using either HTML::FormatText or
# Lynx.
# The return is a new triplet ($content, $content_type, $charset).
#
sub render_maybe {
  my ($self, $content, $content_type, $charset) = @_;
  if ($self->{'render'} && $content_type eq 'text/html') {

    my $class = $self->{'render'};
    if ($class !~ /^HTML::/) { $class = "HTML::FormatText::\u$class"; }
    $class =~ s/::1$//;  # "::1" is $render=1 for plain HTML::FormatText
    require Module::Load;
    Module::Load::load ($class);

    if ($class =~ /^HTML::FormatText($|::WithLinks)/) {
      # trickery putting wide chars through HTML::FormatText, WithLinks or
      # WithLinks::AndTable
      $content = Encode::decode ($charset, $content);
      $content = $class->format_string
        ($content,
         leftmargin => 0,
         rightmargin => $self->{'render_width'});
      $content = Encode::encode_utf8 ($content);

    } else {
      # HTML::FormatExternal style charset specs
      $content = $class->format_string ($content,
                                        leftmargin => 0,
                                        rightmargin => $self->{'render_width'},
                                        input_charset => $charset,
                                        output_charset => 'utf-8');
    }
    $charset = 'utf-8';
    $content_type = 'text/plain';
  }
  return ($content, $content_type, $charset);
}


#------------------------------------------------------------------------------
# error as news message

sub error_message {
  my ($self, $subject, $message) = @_;

  require Encode;
  my $charset = 'utf-8';
  $message = str_ensure_newline ($message);
  $message = Encode::encode ($charset, $message, Encode::FB_DEFAULT());

  my $date = rfc822_time_now();
  my $msgid = $self->url_to_msgid
    ('http://localhost',
     Digest::MD5::md5_base64 ($date.$subject.$message));

  my $top = $self->mime_build
    ({
      'Path:'       => 'localhost',
      'Newsgroups:' => $self->{'nntp_group'},
      From          => 'RSS2Leafnode <nobody@localhost>',
      Subject       => $subject,
      Date          => $date,
      'Message-ID'  => $msgid,
     },
     Type          => 'text/plain',
     Charset       => $charset,
     Data          => $message);

  $self->nntp_post($top) || return;
  print __x("{group} 1 new article\n", group => $self->{'nntp_group'});
}


#------------------------------------------------------------------------------
# fetch HTML

sub fetch_html {
  my ($self, $group, $url) = @_;
  if ($self->{'verbose'} >= 1) { print "page: $url\n"; }

  my $group_uri = URI->new($group,'news');
  local $self->{'nntp_host'} = uri_to_nntp_host ($group_uri);
  local $self->{'nntp_group'} = $group = $group_uri->group;
  $self->nntp_group_check($group) or return;

  require HTTP::Request;
  my $req = HTTP::Request->new (GET => $url);
  $self->status_etagmod_req ($req);
  my $resp = $self->ua->request($req);
  if ($resp->code == 304) {
    $self->status_unchanged ($url);
    return;
  }
  if (! $resp->is_success) {
    print __x("rss2leafnode: {url}\n {status}\n",
              url => $url,
              status => $resp->status_line);
    return;
  }
  $self->enforce_html_charset_from_content ($resp);

  my $content_type = $resp->content_type;                 # should be text/html
  if ($self->{'verbose'} >= 2) { print "content-type: $content_type\n"; }
  my $content = $resp->decoded_content(charset=>'none');  # the bytes
  my $charset = $resp->content_charset ($resp);           # and their charset

  # message id is either the etag if present, or an md5 of the content if not
  my $msgid = $self->url_to_msgid
    ($url, $resp->header('ETag') // Digest::MD5::md5_base64($content));
  return 0 if $self->nntp_message_id_exists ($msgid);

  my $host = URI->new($url)->host
    || 'localhost'; # in case file:// schema during testing
  my $from = 'nobody@'.$host;

  require File::Basename;
  my $subject = html_title($resp) // File::Basename::basename($url);

  ($content, $content_type, $charset)
    = $self->render_maybe ($content, $content_type, $charset);

  my $top = $self->mime_build
    ({ 'Path:'             => $host,
       'Newsgroups:'       => $group,
       From                => $from,
       Subject             => $subject,
       Date                => scalar ($resp->header('Last-Modified')),
       'Message-ID'        => $msgid,
       'Content-Language:' => scalar ($resp->header('Content-Language')),
       'Content-Location:' => $url,
     },
     Type                => $content_type,
     Charset             => $charset,
     Data                => $content);

  $self->nntp_post($top) || return;
  $self->status_etagmod_resp ($url, $resp);
  print __x("{group} 1 new article\n", group => $group);
}


#------------------------------------------------------------------------------
# RSS hacks

# This is a hack for Yahoo Finance feed uniqification.
# $item is a feed hashref.  If it has 'link' field with a yahoo.com
# redirection like
#
#   http://au.rd.yahoo.com/finance/news/rss/financenews/*http://au.biz.yahoo.com/071003/30/1fdvx.html
#
# then return the last target url part.  Otherwise return false.
#
# This allows the item to be identified by its final target link, so as to
# avoid duplication when the item appears in multiple yahoo feeds with a
# different leading part.  (There's no guid in yahoo feeds, as of Oct 2007.)
#
sub item_yahoo_permalink {
  my ($item) = @_;
  my $url = $item->first_child_text('link') // return;
  $url =~ m{^http://[^/]*yahoo\.com/.*\*(http://.*yahoo\.com.*)$} or return;
  return $1;
}

# This is a special case for Google Groups RSS feeds.
# The arguments are link elements [$name,$uri].  If there's a google groups
# like "http://groups.google.com/group/cfcdev/msg/445d4ccfdabf086b" then
# return a mailing list address like "cfcdev@googlegroups.com".  If not in
# that form then return undef.
#
sub googlegroups_link_email {
  foreach my $l (@_) {
    $l->{'uri'}->canonical =~ m{^http://groups\.google\.com/group/([^/]+)/}
      or next;
    return ($1 . '@googlegroups.com');
  }
  return undef;
}

# This is a nasty hack for http://www.aireview.com.au/rss.php
# $url is a link url string just fetched, $resp is a HTTP::Response.  The
# return is a possibly new HTTP::Response object.
#
# The first fetch of an item link from aireview gives back content like
#
#   <META HTTP-EQUIV="Refresh" CONTENT="0; URL=?zz=1&&checkForCookies=1">
#
# plus some cookies in the headers.  The URL "zz=1" in that line seems very
# dodgy, it ends up going to the home page with mozilla.  In any case a
# fresh fetch of the link url with the cookies provided is enough to get the
# actual content.
#
# The LWP::UserAgent::FramesReady module on cpan has a similar match of a
# Refresh, for use with frames.  It works by turning the response into a
# "302 Moved temporarily" for LWP to follow.  urlcheck.pl at
# http://www.cpan.org/authors/id/P/PH/PHILMI/urlcheck-1.00.pl likewise
# follows.  But alas both obey the URL given in the <META>, which is no good
# here.
#
sub aireview_follow {
  my ($self, $url, $resp) = @_;

  if ($resp->is_success) {
    my $content = $resp->decoded_content (charset=>'none');
    if ($content =~ /<META[^>]*Refresh[^>]*checkForCookies/i) {
      if ($self->{'verbose'}) {
        print "  following aireview META Refresh with cookies\n";
      }
      require HTTP::Request;
      my $req = HTTP::Request->new (GET => $url);
      $resp = $self->ua->request($req);
    }
  }
  return $resp;
}


#------------------------------------------------------------------------------
# fetch RSS

my $map_xmlns
  = {
     'http://www.w3.org/2005/Atom'                  => 'atom',
     'http://www.w3.org/1999/02/22-rdf-syntax-ns#'  => 'rdf',
     'http://purl.org/rss/1.0/modules/slash/'       => 'slash',
     'http://purl.org/rss/1.0/modules/syndication/' => 'syn',
     'http://purl.org/syndication/thread/1.0'       => 'thr',
     'http://wellformedweb.org/CommentAPI/'         => 'wfw',
     'http://www.w3.org/1999/xhtml'                 => 'xhtml',

     # don't need to distinguish dcterms from plain dc as yet
     'http://purl.org/dc/elements/1.1/'             => 'dc',
     'http://purl.org/dc/terms/'                    => 'dc',

     # purl.org might be supposed to be the home for wiki:, but it's a 404
     # and usemod.com suggests its page instead
     'http://purl.org/rss/1.0/modules/wiki/'        => 'wiki',
     'http://www.usemod.com/cgi-bin/mb.pl?ModWiki'  => 'wiki',

     # not sure if this is supposed to be necessary, but without it
     # "xml:lang" attributes are turned into "lang"
     'http://www.w3.org/XML/1998/namespace' => 'xml',
    };

sub twig_parse {
  my ($self, $xml) = @_;

  # default "discard_spaces" chucks leading and trailing space on content,
  # which is usually a good thing
  #
  require XML::Twig;
  XML::Twig->VERSION('3.34'); # for att_exists()
  my $twig = XML::Twig->new (map_xmlns => $map_xmlns);
  $twig->safe_parse ($xml);
  my $err = $@;

  # Zap bad non-ascii chars by putting it through Encode::from_to().
  # Encode::FB_DEFAULT substitutes U+FFFD for unicode, or question mark "?"
  # for non-unicode.  Mozilla does some sort of similar liberal byte
  # interpretation so as to at least display something from a dodgy feed.
  #
  if ($err && $err =~ /not well-formed \(invalid token\) at (line \d+, column \d+, byte (\d+))/) {
    my $where = $1;
    my $byte = ord(substr($xml,$2,1));
    if ($byte >= 128) {
      my $charset = $twig->encoding // 'utf-8';
      if ($self->{'verbose'}) {
        printf "parse error, attempt re-code $charset for byte 0x%02X\n",
          $byte;
      }
      require Encode;
      Encode::from_to($xml, $charset, $charset, Encode::FB_DEFAULT());

      $twig = XML::Twig->new (map_xmlns => $map_xmlns);
      if ($twig->safe_parse ($xml)) {
        undef $err;
        print __x("Warning, recoded {charset} to parse {url}\n  expect substitutions for bad non-ascii ({where})\n",
                  charset => $charset,
                  url     => $self->{'uri'},
                  where   => $where);
        $twig->root->set_att('rss2leafnode:recode',$charset);
      }
    }
  }

  if ($err) {
    # XML::Parser seems to stick some spurious leading whitespace on the error
    $err = trim_whitespace($err);

    if ($self->{'verbose'} >= 1) {
      print __x("Parse error on URL {url}\n{error}",
                url => $self->{'uri'},
                error => $err);
    }
    return (undef, $err);
  }

  # Strip any explicit "atom:" namespace down to bare part.  Should be
  # unambiguous and is easier than giving tag names both with and without
  # the namespace.  Undocumented set_ns_as_default() might do this ... or
  # might not.
  #
  my $root = $twig->root;
  foreach my $child ($root->descendants_or_self) {
    if ($child->ns_prefix eq 'atom') {
      $child->set_tag ($child->local_name);
    }
    #     foreach my $attname ($child->att_names) {
    #       if ($attname =~ /^atom:(.*)/) {
    #         $child->change_att_name($attname, $1);
    #       }
    #     }
  }

  if (defined $self->{'uri'} && ! $root->att_exists('xml:base')) {
    $root->set_att ('xml:base', $self->{'uri'});
  }

  return ($twig, undef);
}

sub item_to_channel {
  my ($item) = @_;
  # parent for RSS or Atom, but sibling "channel" for RDF
  my $channel = $item->parent;
  return ($channel->first_child('channel')
          // $channel);
}

# return a Message-ID string for this $item coming from $self->{'uri'}
#
sub item_to_msgid {
  my ($self, $item) = @_;

  if (is_non_empty (my $id = $item->first_child_text('id'))) {
    # Atom <id> is supposed to be a url
    return $self->url_to_msgid ($id, $item->first_child_text('updated'));
  }

  my $guid = $item->first_child('guid');
  my $isPermaLink = 0;
  if (defined $guid) {
    $isPermaLink = (lc($guid->att('isPermaLink') // 'true') eq 'true');
    $guid = collapse_whitespace ($guid->text);
  }

  if ($isPermaLink) {   # <guid isPermaLink="true">
    return $self->url_to_msgid ($guid);
  }
  if (my $link = item_yahoo_permalink ($item)) {
    return $self->url_to_msgid ($link);
  }
  if (defined $guid) {  # <guid isPermaLink="false">
    return $self->url_to_msgid ($self->{'uri'}, $guid);
  }

  # nothing in the item, use the feed url and MD5 of some fields which
  # will hopefully distinguish it from other items at this url
  if ($self->{'verbose'} >= 2) { print "msgid from MD5\n"; }
  return $self->url_to_msgid
    ($self->{'uri'},
     md5_of_utf8 (join_non_empty ('',
                                  map {$item->first_child_text($_)}
                                  qw(title
                                     author dc:creator
                                     description content
                                     link
                                     pubDate published updated
                                   ))));
}

# Return a Message-ID string (including angles <>) for $item, or empty list.
# This matches up to an Atom <id> element, dunno if it's much used.
# Supposedly there should be only one thr:in-reply-to, no equivalent to
# the "References" header giving all parents.
#
sub item_to_in_reply_to {
  my ($self, $item) = @_;
  my $inrep = $item->first_child('thr:in-reply-to') // return;
  my $ref = ($inrep->att('thr:ref')
             // $inrep->att('ref')
             // $inrep->att('atom:ref') # comes out atom: under map_xmlns ...
             // return);
  $ref = elt_xml_based_uri ($inrep, $ref); # probably shouldn't be relative ...
  return $self->url_to_msgid ($ref);
}

# return the host part of $self->{'uri'}, or "localhost" if none
sub uri_to_host {
  my ($self) = @_;
  my $uri = $self->{'uri'};
  return (non_empty ($uri->can('host') && $uri->host)
          // 'localhost');
}

# $elt is an XML::Twig::Elt
# return an email address, either just the text part of $elt or Atom style
# <name> and <email> sub-elements
#
sub elt_to_email {
  my ($elt) = @_;
  return unless defined $elt;
  my $email   = elt_to_rendered_line ($elt->first_child('email')); # Atom
  my $rdfdesc = $elt->first_child('rdf:Description');

  my $ret = join
    (' ',
     non_empty ($elt->text_only),
     non_empty (elt_to_rendered_line ($elt->first_child('name'))), # Atom
     non_empty ($rdfdesc && $rdfdesc->first_child_text('rdf:value')));

  if (is_non_empty($email)) {
    if (is_non_empty ($ret)) {
      $ret = "$ret <$email>";
    } else {
      $ret = $email;
    }
  }
  return unless is_non_empty($ret);

  # eg.     "Rael Dornfest (mailto:rael@oreilly.com)"
  # becomes "Rael Dornfest <rael@oreilly.com>"
  $ret =~ s/\(mailto:(.*)\)/<$1>/;

  # Collapse whitespace against possible tabs and newlines in a <author> as
  # from googlegroups for instance.  MIME::Entity seems to collapse
  # newlines, but not tabs.
  return collapse_whitespace($ret);
}

# return email addr string
sub item_to_from {
  my ($self, $item) = @_;
  my $channel = item_to_channel($item);

  # "author" is supposed to be an email address whereas "dc:creator" is
  # looser.  The RSS recommendation is to use author when revealing an email
  # and dc:creator when hiding it.
  #
  # <dc:contributor> in wiki: feeds
  #
  return (elt_to_email ($item->first_child('author'))
          // elt_to_email ($item   ->first_child('dc:creator'))
          // elt_to_email ($item   ->first_child('dc:contributor'))
          // non_empty ($item->first_child_text('wiki:username'))

          // elt_to_email ($channel->first_child('dc:creator'))
          // elt_to_email ($channel->first_child('author'))
          // elt_to_email ($channel->first_child('managingEditor'))
          // elt_to_email ($channel->first_child('webMaster'))

          // elt_to_email ($item   ->first_child('dc:publisher'))
          // elt_to_email ($channel->first_child('dc:publisher'))

          // non_empty ($channel->first_child_text('title'))

          # RFC822
          // 'nobody@'.$self->uri_to_host
         );
}

sub item_to_subject {
  my ($self, $item) = @_;

  # RSS http://www.debian.org/News/weekly/dwn.en.rdf circa Feb 2010 had
  # some html in its <title>, like <description> can have.
  # Atom <title> can have type="html" etc in the usual way.
  return
    (elt_to_rendered_line    ($item->first_child('title'))
     // elt_to_rendered_line ($item->first_child('dc:subject'))
     // __('no subject'));
}

# return list of hashrefs
#
sub item_to_links {
  my ($self, $item) = @_;

  my @elts = ($item->children(qr/^link$
                               |^content$
                               |^wiki:diff$
                               |^comments$
                               |^wfw:comment$
                                /x));

  my (@links, @others);
  my %seen;
  foreach my $elt (@elts) {
    if ($self->{'verbose'} >= 2) { print "link ",$elt->sprint,"\n"; }

    my $l = { download => 1,
              hreflang => ($elt->att('atom:hreflang')
                           // $elt->att('hreflang')),
              type     => ($elt->att('atom:type')
                           // $elt->att('type')),
            };

    # Atom type="application/atom+xml" is another feed, not a html page
    given ($elt->att('atom:type') // $elt->att('type')) {
      when (! defined) {}
      when ('application/atom+xml') {
        if ($self->{'verbose'} >= 2) { print "  skip link type \"$_\"\n"; }
        next;
      }
    }

    given (non_empty ($elt->att('atom:rel') // $elt->att('rel'))) {
      when (!defined) {
        given ($elt->tag) {
          when (/diff/) {
            $l->{'name'} = __('Diff:');
          }
          when (/comment/) {
            if (defined (my $count = non_empty
                         ($item->first_child_text('slash:comments')))) {
              $l->{'name'} = __x('Comment({count}):', count => $count);
            } else {
              $l->{'name'} = __('Comment:');
            }
            $l->{'download'} = 0;
          }
        }
      }

      when (['self',         # the feed itself (in the channel normally)
             'edit',         # to edit the item, maybe
             'service.edit', # to edit the item
             'license',      # probably only in the channel part normally
            ]) {
        if ($self->{'verbose'} >= 1) { print "skip link \"$_\"\n"; }
        next;
      }

      when ('alternate') {
        # "alternate" is supposed to be the content as the entry, but in a
        # web page or something.  Not sure that's always quite true, so show
        # it as a plain link.  If no <content> then an "alternate" is
        # supposed to be mandatory.
      }

      # when ('next') ... # not sure about "next" link

      when ('service.post') { $l->{'name'} = __('Comment:');
                              $l->{'download'} = 0 }
      when ('via')          { $l->{'name'} = __('Via:');
                              $l->{'download'} = 0 }
      when ('replies') {
        # rel="replies" per RFC 4685 "thr:"
        my $count = ($elt->att('thr:count')
                     // $elt->att('count')
                     // $elt->att('atom:count')
                     // non_empty ($item->first_child_text('thr:total')));
        $l->{'name'} = (defined $count
                        ? __x('Replies({count}):', count => $count)
                        : __('Replies:'));
        $l->{'download'} = 0;
      }
      when ('enclosure') { $l->{'name'} = __('Enclosure:') }
      when ('related')   { $l->{'name'} = __('Related:') }
      default { $l->{'name'} = __x('{linkrel}:', linkrel => $_) }
    }

    # <atom:content src=""> is a link to content, <content> without src=""
    # is body part itself
    my $uri = ($elt->att('atom:src') // $elt->att('src'));
    next if ($elt->tag eq 'content' && ! defined $uri);

    # Atom <link href="http:.."/> or RSS <link>http:..</link>
    $uri //= (non_empty ($elt->att('atom:href'))
              // non_empty ($elt->att('href'))
              // non_empty ($elt->trimmed_text)
              // next);
    $l->{'uri'} = $uri = elt_xml_based_uri ($elt, $uri);

    # have seen same url under <link> and <comments> from sourceforge
    # http://sourceforge.net/export/rss2_keepsake.php?group_id=203650
    # so dedup
    if ($seen{$uri->canonical}++) {
      if ($self->{'verbose'} >= 1) { print "skip duplicate link \"$uri\"\n"; }
      next;
    }

    if (defined $l->{'name'}) {
      push @others, $l;
    } else {
      $l->{'name'} = __('Link:');
      push @links, $l;
    }

    # show length if biggish, but suspect this is rarely provided
    if (defined (my $length = ($elt->att('atom:length')
                               // $elt->att('length')))) {
      if ($length >= 2000) {
        if ($length >= 100_000) {
          $length = sprintf (__('%.1fM'), $length / 1_000_000);
        } else {
          $length = sprintf (__('%.0fk'), $length / 1_000);
        }
        $l->{'name'} =~ s/:/($length):/;
      }
    }
  }

  return (@links, @others);
}

# return language code string or undef
sub item_to_language {
  my ($self, $item) = @_;
  my $lang;
  if (my $elt = $item->first_child('content')) {
    $lang = non_empty ($elt->att('xml:lang'));
  }

  # Either <language> sub-element or xml:lang="" tag, in the item itself or
  # in channel, and maybe xml:lang in toplevel <feed>.
  # $elt->inherit_att() is close, but looks only at xml:lang, not a
  # <language> subelement.
  for ( ; $item; $item = $item->parent) {
    $lang //= (non_empty    ($item->first_child_text('language'))
               // non_empty ($item->att('xml:lang'))
               // next);
  }

  return ($lang
          // $self->{'resp'}->content_language);
}

# return copyright string or undef
sub item_to_copyright {
  my ($self, $item) = @_;
  my $channel = item_to_channel($item);

  # <dcterms:license> supposedly supercedes <dc:rights>, so check it first,
  # appearing here just as dc: due to combining in the "map_xmlns"
  #
  # Atom <rights> can be type="html" etc in its usual way, but think RSS is
  # always plain text
  #
  return (non_empty ($item->first_child_text('dc:license'))
          // non_empty ($item->first_child_text('dc:rights'))
          // elt_to_rendered_line ($item->first_child('rights'))   # Atom

          # Atom sub-elem <source><rights>...</rights> when from another feed
          // non_empty (elt_to_rendered_line
                        (($item->get_xpath('source/rights'))[0]))

          // non_empty ($channel->first_child_text('dc:license'))
          // non_empty ($channel->first_child_text('dc:rights'))

          # RSS <copyright>, don't think entity-encoded html is allowed there
          // non_empty ($channel->first_child_text('copyright'))

          // non_empty (elt_to_rendered_line
                        ($channel->first_child('rights'))));  # Atom
}
# return copyright string or undef
sub item_to_generator {
  my ($self, $item) = @_;
  my $channel = item_to_channel($item);

  # both RSS and Atom use <generator>
  # Atom can include version="" and uri=""
  my $generator = $channel->first_child('generator') // return;
  return collapse_whitespace (join_non_empty (' ',
                                              $generator->text,
                                              $generator->att('atom:version'),
                                              $generator->att('version'),
                                              $generator->att('atom:uri'),
                                              $generator->att('uri')));
}

# $self->{'rss_charset_override'}, if set, means the bytes are actually in
# that charset.  Enforce this by replacing the "<?xml encoding=" in the
# bytes.  Do a decode() and re-encode() to cope with non-ascii like say
# utf-16.
#
# XML::RSS::LibXML has an "encoding" option on its new(), but that's for
# feed creation or something, a parse() still follows the <?xml> tag.
#
sub enforce_rss_charset_override {
  my ($self, $xml) = @_;
  if (my $charset = $self->{'rss_charset_override'}) {
    $xml = Encode::decode ($charset, $xml);
    if ($xml =~ s/(<\?xml[^>]*encoding="?)([^">]+)/$1$charset/i) {
      if ($self->{'verbose'} >= 2) {
        print "replace encoding=$2 tag with encoding=$charset\n";
      }
    } elsif ($xml =~ s/(<\?xml[^?>]*)/$1 encoding="$charset"/i) {
      if ($self->{'verbose'} >= 2) {
        print "insert encoding=\"$charset\"\n";
      }
    } else {
      my $str = "<?xml version=\"1.0\" encoding=\"$charset\"?>\n";
      if ($self->{'verbose'} >= 2) {
        print "insert $str";
      }
      $xml = $str . $xml;
    }
    if ($self->{'verbose'} >= 3) {
      print "xml now:\n$xml\n";
    }
    $xml = Encode::encode ($charset, $xml);
  }
  return $xml;
}

my %mime_html_types = ('text/html'  => 1,
                       'text/xhtml' => 1,
                       'application/xhtml+xml' => 1);

# $item is an XML::Twig::Elt
#
sub fetch_rss_process_one_item {
  my ($self, $item) = @_;
  my $subject = $self->item_to_subject ($item);
  if ($self->{'verbose'} >= 1) { print __x(" item: {subject}\n",
                                           subject => $subject); }
  my $msgid = $self->item_to_msgid ($item);
  return 0 if $self->nntp_message_id_exists ($msgid);

  my $channel = item_to_channel($item);
  local $self->{'now822'} = rfc822_time_now();
  my @links      = $self->item_to_links ($item);

  # Crib: an undef value for a header means omit that header, which is good
  # for say the merely optional "Content-Language"
  #
  # there can be multiple "feed" links from Atom ...
  # 'X-RSS-Feed-Link:'  => $channel->{'link'},
  #
  my %headers
    = ('Path:'        => scalar ($self->uri_to_host),
       'Newsgroups:'  => $self->{'nntp_group'},
       From           => scalar ($self->item_to_from($item)),
       Subject        => $subject,
       Date           => scalar ($self->item_to_date($item)),
       'In-Reply-To:'      => scalar ($self->item_to_in_reply_to($item)),
       'Message-ID'        => $msgid,
       'Content-Language:' => scalar ($self->item_to_language($item)),
       'List-Post:'        => scalar (googlegroups_link_email(@links)),
       'PICS-Label:'       => scalar ($channel->first_child_text('rating')),
       'X-Copyright:'      => scalar ($self->item_to_copyright($item)),
       'X-RSS-URL:'        => scalar ($self->{'uri'}->as_string),
       'X-RSS-Generator:'  => scalar ($self->item_to_generator($item)),
      );

  # FIXME: atom <content> can be just a link

  # <media:text> is another possibility, but have seen it from Yahoo as just
  # a copy of <description>, though with type="html" to make the format clear
  # Atom spec is for no more than one <content>,
  my $body_charset = 'utf-8';
  my $body = ($item->first_child('description')
              || $item->first_child('dc:description')
              || do {
                # Atom <content> with src="" is no good, it's a link to
                # external contents.  There's supposed to be a <summary> in
                # that case instead.
                my $elt = $item->first_child('content');
                ($elt && ! ($elt->att('atom:src') || $elt->att('src'))
                 ? $elt : undef)
              }
              || $item->first_child('summary'));  # Atom
  my $body_type;
  if ($body) {
    given (elt_text_type ($body)) {
      when (['xhtml','text/xhtml']) {  # Atom
        $body = elt_xhtml_to_html ($body);
        $body_type = 'text/html';
      }
      when (['html','text/html']) {   # RSS or Atom
        $body = elt_subtext($body);
        $body_type = 'text/html';
      }
      default {
        # FIXME: other atom types are base64 mime

        # should be text-only, no sub-elements, but extract sub-elements to
        # cope with dodgy feeds with improperly escaped html etc
        $body = elt_subtext($body);
        $body_type = 'text/plain';

        # Text is designed to be wrapped etc, can be just a long line like
        # http://feeds.feedburner.com/SeriouslyGood
        require Text::WrapI18N;
        local $Text::WrapI18N::columns = $self->{'render_width'} + 1;
        local $Text::WrapI18N::unexpand = 0;       # no tabs in output
        local $Text::WrapI18N::huge = 'overflow';  # don't break long words
        $body =~ tr/\n/ /;
        $body = Text::WrapI18N::wrap('', '', $body);
      }
    }
  } else {
    $body = '';
    $body_type = 'text/plain';
  }
  if ($self->{'verbose'} >= 3) { print " body: $body_type\n$body\n"; }

  if ($body_type eq 'text/html') {
    my $body_base = '';
    if (my $base_uri = elt_xml_base($item)) {
      $body_base = <<"HERE";
<base href="$Entitize{$base_uri}">
HERE
    }

    $body = <<"HERE";
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<html>
<head>
<meta http-equiv=Content-Type content="text/html; charset=$Entitize{$body_charset}">
$body_base</head>
<body>
$body
HERE
    # <nobr> on link lines to try to prevent the displayed URL being chopped
    # up by a line-wrap, which can make it hard to cut and paste.  <pre> can
    # prevent a line wrap, but it ends up treated as starting a paragraph,
    # separate from the 'name' part.
    #
    if (! $self->{'render'}) { # link append if not rendering to text
      if (@links) {
        my $sep = "\n\n<p>\n";
        foreach my $l (@links) {
          my $hreflang = $l->{'hreflang'};
          if (defined $hreflang) {
            $hreflang = " hreflang=\"$Entitize{$hreflang}\"";
          } else  {
            $hreflang = '';
          }
          my $type = $l->{'type'};
          if (defined $type) {
            $type = " type=\"$Entitize{$type}\"";
          } else  {
            $type = '';
          }
          my $name = $Entitize{$l->{'name'}};
          my $uri = $Entitize{$l->{'uri'}};

          $body .= <<"HERE";
$sep<nobr>$name&nbsp;<a$hreflang$type href="$uri">$uri</a></nobr>
HERE
          $sep = "<br>\n";
        }
        $body .= "</p>";
      }
    }

    $body .= "\n</body></html>\n";
    $body = Encode::encode ($body_charset, $body);
  }

  ($body, $body_type, $body_charset)
    = $self->render_maybe ($body, $body_type, $body_charset);

  # Links appended as text if rendered to text, rather than rely on
  # <a href="">...</a> to come out looking good.  In particular it doesn't
  # come out looking good with lynx.
  if ((($body_type ne 'text/html') || $self->{'render'})
      && @links) {
    $body =~ s/\s+$//; # trailing whitespace
    $body .= "\n\n";
    foreach my $l (@links) {
      $body .= Encode::encode ($body_charset, "$l->{'name'} $l->{'uri'}\n");
    }
  }

  require MIME::Entity;
  my $top = $self->mime_build
    (\%headers,
     Type           => $body_type,
     Charset        => $body_charset,
     Data           => $body);

  if ($self->{'rss_get_links'}) {
    foreach my $l (@links) {
      next if ! $l->{'download'};
      if ($self->{'verbose'}) { print __x("  link: \"{name}\" {url}\n",
                                          name => $l->{'name'},
                                          url => $l->{'uri'}); }
      require HTTP::Request;
      my $req = HTTP::Request->new (GET => $l->{'uri'});
      my $resp = $self->ua->request($req);
      $resp = $self->aireview_follow ($l->{'uri'}, $resp);

      my ($down, $down_type, $down_charset);
      if ($resp->is_success) {
        $self->enforce_html_charset_from_content ($resp);
        $down = $resp->decoded_content (charset=>'none');
        $down_type = $resp->content_type;
        $down_charset = $resp->content_charset ($resp);
        ($down, $down_type, $down_charset)
          = $self->render_maybe ($down, $down_type, $down_charset);
      } else {
        print __x("rss2leafnode: {url}\n {status}\n",
                  url => $l->{'uri'},
                  status => $resp->status_line);
        $down = "\n" . __x("Cannot download link {url}\n{status}",
                           url => $l->{'uri'},
                           status => $resp->status_line);
        $down_type = 'text/plain';
        $down_charset = 'us-ascii';
      }

      if ($body_type eq 'text/plain'
          && $down_type eq 'text/plain'
          && ($down_charset eq $body_charset || $down_charset eq 'us-ascii')) {
        mime_body_append ($top->bodyhandle, $down);
      } else {
        $top->attach (Type     => $down_type,
                      Encoding => '-SUGGEST',
                      Charset  => $down_charset,
                      Data     => $down,
                      # only really applicable to text/html content type, but
                      # shouldn't hurt to include it always
                      'Content-Location:' => $l->{'uri'});
      }
    }
  }

  $self->nntp_post($top) || return 0;
  if ($self->{'verbose'} >= 1) { print __("   posted\n"); }
  return 1;
}

# $group is a string, the name of a local newsgroup
# $url is a string, an RSS feed to be read
#
sub fetch_rss {
  my ($self, $group, $url) = @_;
  if ($self->{'verbose'} >= 2) { print "fetch_rss: $group $url\n"; }

  my $group_uri = URI->new($group,'news');
  local $self->{'nntp_host'} = uri_to_nntp_host ($group_uri);
  local $self->{'nntp_group'} = $group = $group_uri->group;
  $self->nntp_group_check($group) or return;

  # an in-memory cookie jar, used only per-RSS feed and then discarded,
  # which means only kept for fetching for $self->{'rss_get_links'} from a
  # feed
  $self->ua->cookie_jar({});

  if ($self->{'verbose'} >= 1) { print __x("feed: {url}\n", url => $url); }
  require HTTP::Request;
  my $req = HTTP::Request->new (GET => $url);
  $self->status_etagmod_req ($req) || return;

  # $req->uri can be a URI object or a string
  local $self->{'uri'} = URI->new ($req->uri);

  my $resp = $self->ua->request($req);
  if ($resp->code == 304) {
    $self->status_unchanged ($url);
    return;
  }
  if (! $resp->is_success) {
    print __x("rss2leafnode: {url}\n {status}\n",
              url => $url,
              status => $resp->status_line);
    return;
  }
  local $self->{'resp'} = $resp;

  my $xml = $resp->decoded_content (charset => 'none');  # raw bytes
  $xml = $self->enforce_rss_charset_override ($xml);

  my ($twig, $err) = $self->twig_parse($xml);
  if (defined $err) {
    $self->error_message
      (__x("Error parsing {url}", url => $url),
       __x("XML::Twig parse error on\n\n  {url}\n\n{error}",
           url => $url,
           error => $err));
    # after successful error message to news
    $self->status_etagmod_resp ($url, $resp);
    return;
  }
  if ($self->{'verbose'} >= 3) {
    require Data::Dumper;
    print Data::Dumper->new([$twig->root],['root'])
      ->Indent(1)->Sortkeys(1)->Dump;
  }

  # "item" for RSS/RDF, "entry" for Atom
  my @items = $twig->descendants(qr/^(item|entry)$/);

  if ($self->{'rss_newest_only'}) {
    our ($a,$b);
    my $newest = List::Util::reduce { $self->item_date_max($a,$b) } @items;
    @items = ($newest);
  }

  my $new = 0;
  foreach my $item (@items) {
    $new += $self->fetch_rss_process_one_item ($item);
  }

  if ($self->{'verbose'} >= 2) {
    my $jar = $self->ua->cookie_jar;
    my $str = $jar->as_string;
    if ($str eq '') {
      print "no cookies from this feed\n";
    } else {
      print "accumulated cookies from this feed:\n$str";
    }
  }
  $self->ua->cookie_jar (undef);

  $self->status_etagmod_resp ($url, $resp, $twig);
  print __xn("{group}: {count} new article\n",
             "{group}: {count} new articles\n",
             $new,
             group => $group,
             count => $new);
}

1;
__END__

=for stopwords rss2leafnode RSS Leafnode config Ryde

=head1 NAME

App::RSS2Leafnode -- post RSS feeds to newsgroups

=head1 SYNOPSIS

 use App::RSS2Leafnode;
 my $r2l = App::RSS2Leafnode->new;
 exit $r2l->command_line;

=head1 DESCRIPTION

This is the guts of the C<rss2leafnode> program, see L<rss2leafnode> for
user-level operation.

=head1 FUNCTIONS

=over 4

=item C<< $r2l = App::RSS2Leafnode->new (key=>value,...) >>

Create and return a new RSS2Leafnode object.  The optional keyword
parameters are the config variables, plus C<verbose>

    verbose
    render
    render_width
    rss_get_links
    rss_newest_only
    rss_charset_override
    html_charset_from_content

=item C<< $r2l->fetch_rss ($newsgroup, $url) >>

=item C<< $r2l->fetch_html ($newsgroup, $url) >>

Fetch an RSS feed or web page and post articles to C<$newsgroup>.  This is
the C<fetch_rss> and C<fetch_html> operations for F<~/.rss2leafnode.conf>.

=back

=head1 SEE ALSO

L<rss2leafnode>,
L<XML::Twig>

=head1 HOME PAGE

L<http://user42.tuxfamily.org/rss2leafnode/index.html>

=head1 LICENSE

Copyright 2007, 2008, 2009, 2010 Kevin Ryde

RSS2Leafnode is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by the Free
Software Foundation; either version 3, or (at your option) any later
version.

RSS2Leafnode is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
more details.

You should have received a copy of the GNU General Public License along with
RSS2Leafnode.  If not, see L<http://www.gnu.org/licenses/>.

=cut
