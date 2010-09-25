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
use Encode;
use Hash::Util::FieldHash;
use List::Util 'min', 'max';
use List::MoreUtils;
use POSIX (); # ENOENT, etc
use Text::Trim 1.02;  # version 1.02 for undef support
use URI;
use HTML::Entities::Interpolate;

# version 1.17 for __p(), and version 1.16 for turn_utf_8_on()
use Locale::TextDomain 1.17;
use Locale::TextDomain ('App-RSS2Leafnode');
BEGIN {
  use Locale::Messages;
  Locale::Messages::bind_textdomain_codeset ('App-RSS2Leafnode','UTF-8');
  Locale::Messages::bind_textdomain_filter ('App-RSS2Leafnode',
                                            \&Locale::Messages::turn_utf_8_on);
}

# uncomment this to run the ### lines
#use Smart::Comments;

our $VERSION;
BEGIN {
   $VERSION = 40;
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
#   http://www.rssboard.org/rss-specification
#   http://www.rssboard.org/files/rss-2.0-sample.xml
#       RSS 2.0 spec and sample.
#
#   http://www.rssboard.org/rss-profile
#       "Best practices."
#
# Dublin Core
#   RFC 5013 -- summary
#   http://dublincore.org/documents/dcmi-terms/ -- dc/terms
#
# Atom
#   RFC 4287 -- Atom spec
#   RFC 3339 -- ISO timestamps as used in Atom
#   RFC 4685 -- "thr" threading extensions
#   RFC 4946 -- <link rel="license">
#   RFC 5005 -- <link rel="next"> etc paging and archiving
#   http://diveintomark.org/archives/2004/05/28/howto-atom-id
#      Making an <id>
#
# RSS Modules:
#   http://www.meatballwiki.org/wiki/ModWiki -- wiki
#   http://web.resource.org/rss/1.0/modules/slash/
#   http://code.google.com/apis/feedburner/feedburner_namespace_reference.html
#   http://backend.userland.com/creativeCommonsRSSModule
#
#   http://web.resource.org/rss/1.0/modules/content/
#   http://www.rssboard.org/rss-profile#namespace-elements-content
#   http://validator.w3.org/feed/docs/warning/NeedDescriptionBeforeContent.html
#       <content:encoded> should precede <description>
#
#   http://www.apple.com/itunes/podcasts/specs.html
#   http://www.feedforall.com/itunes.htm
#   http://www.w3.org/2003/01/geo/wgs84_pos -- <geo:lat> etc
#   http://www.georss.org/
#       http://www.georss.org/Encodings
#       http://www.georss.org/atom
#       http://www.georss.org/rdf_rss1
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
#   RFC 3023 text/xml etc media types
#
# Mail Messages
#   RFC 850, RFC 1036 -- News message format, inc headers and rnews format
#   RFC 2076, RFC 4021 -- headers summary.
#   RFC 2557 -- MHTML Content-Location
#   RFC 1864 -- Content-MD5 header
#   RFC 2369 -- List-Post header and friends
#   http://www3.ietf.org/proceedings/98dec/I-D/draft-ietf-drums-mail-followup-to-00.txt
#       Draft "Mail-Followup-To" header.
#
#   RFC 1327 -- X.400 to RFC822 introducing Language header
#   RFC 3282 -- Content-Language header
#   RFC 1766, RFC 3066, RFC 4646 -- language tag form
#
# NNTP
#     RFC 977 -- NNTP
#     RFC 2616 -- HTTP/1.1 Accept-Encoding header
#     RFC 2980 -- NNTP extensions
#
# RFC 4642 -- NNTP with SSL
#
# For XML in Perl there's several ways to do it!
#   - XML::Parser looks likely for stream/event processing, but its builtin
#     tree mode is very basic.
#   - XML::Twig extends XML::Parser to a good tree, though the docs are
#     slightly light on.  It only does a subset of "XPath" but the
#     functions/regexps are more perl-like for matching and there's various
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
#   - XML::TreePP pure perl parser to a hash tree.
#
# The choice of XML::Twig is based on wanting both RSS and Atom, but
# XML::Feed not going far enough.  Tree processing is easier than stream,
# and an RSS isn't meant to be huge.  A tree may help if channel fields
# follow items or something equally unnatural, but will probably assume that
# doesn't happen and look at the twig partial-tree mode.  Between the tree
# styles XML::LibXML is harder to get into than Twig.
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
  require Digest::MD5;
  return Digest::MD5::md5_base64 (Encode::encode_utf8 ($str));
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

sub collapse_whitespace {
  my ($str) = @_;
  defined $str or return undef;
  $str =~ s/(\s+)/($1 eq '  ' ? $1 : ' ')/ge;
  return Text::Trim::trim($str);
}

sub is_ascii {
  my ($str) = @_;
  return ($str !~ /[^[:ascii:]]/);
}

use constant::defer NUMBER_FORMAT => sub {
  require Number::Format;
  Number::Format->VERSION(1.5); # for format_bytes() options params
  return Number::Format->new
    (-kilo_suffix => __p('number-format-kilobytes','K'),
     -mega_suffix => __p('number-format-megabytes','M'),
     -giga_suffix => __p('number-format-gigabytes','G'));
};

sub str_count_lines {
  my ($str) = @_;
  return scalar($str =~ tr/\n//) + (length($str) && substr($str,-1) ne "\n");
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

                # secret extra
                msgidextra      => '',

                @_
               }, $class;
}

sub command_line {
  my ($self) = @_;

  my $done_version;
  require Getopt::Long;
  Getopt::Long::Configure ('no_ignore_case');
  Getopt::Long::GetOptions
      ('config=s'   => \$self->{'config_filename'},
       'verbose:1'  => \$self->{'verbose'},
       'version'    => sub {
         say __x("RSS2Leafnode version {version}", version => $VERSION);
         $done_version = 1;
       },
       'bareversion'  => sub {
         say $VERSION;
         $done_version = 1;
       },
       'msgid=s'      => \$self->{'msgidextra'},
       'help|?' => sub {
         say __x("rss2leafnode [--options]");
         say __x("   --config=filename   configuration file (default ~/.rss2leafnode.conf)");
         say __x("   --help       print this help");
         say __x("   --verbose    describe what's done");
         say __x("   --verbose=2  show technical details of what's done");
         say __x("   --version    print program version number");
         exit 0;
       }) or return 1;
  if (! $done_version) {
    $self->do_config_file;
    $self->nntp_close;
  }
  return 0;
}

sub homedir {
  # my ($self) = @_;
  require File::HomeDir;
  # call each time just in case playing tricks with $ENV{HOME} in conf file
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
  }

  my $config_filename = $self->config_filename;
  if ($self->{'verbose'}) { say "config: $config_filename"; }

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
# LWP stuff

sub ua {
  my ($self) = @_;
  return ($self->{'ua'} ||= do {
    require LWP::UserAgent;
    LWP::UserAgent->VERSION(5.832);  # 5.832 for content_charset()

    # one connection kept alive
    my $ua = LWP::UserAgent->new (keep_alive => 1);
    require Scalar::Util;
    Scalar::Util::weaken ($ua->{(__PACKAGE__)} = $self);
    $ua->agent ('RSS2leafnode/' . $self->VERSION . ' ');

    Scalar::Util::weaken (my $weak_self = $self);
    $ua->add_handler (request_send => \&lwp_request_send__verbose);
    $ua->add_handler (response_done => sub {
                        lwp_response_done__check_md5 ($weak_self, @_);
                      });

    # ask for everything $resp->decode() / $resp->decoded_content() can cope
    # with, in particular "gzip" and "deflate" compression if Compress::Zlib
    # or whatever is available
    #
    require HTTP::Message;
    my $decodable = HTTP::Message::decodable();
    if ($self->{'verbose'} >= 2) { say "HTTP decodable: $decodable"; }
    $ua->default_header ('Accept-Encoding' => $decodable);

    $ua
  });
}

sub lwp_request_send__verbose {
  my ($req, $ua, $h) = @_;
  my $self = $ua->{(__PACKAGE__)};
  if ($self->{'verbose'} >= 2) {
    say 'request_send:';
    $req->dump;
    say '';
  }
  return;  # continue processing
}

sub lwp_response_done__check_md5 {
  my ($self, $resp, $ua, $h) = @_;
  $self || return;
  my $want = $resp->header('Content-MD5') // do {
    if ($self->{'verbose'} >= 2) {
      print "no Content-MD5 header\n";
    }
    return;
  };
  $resp->decode;
  my $cref = $resp->content_ref;
  require Digest::MD5;
  my $got = Digest::MD5::md5_hex($$cref);
  if ($got ne $want) {
    print __x("Warning, MD5 checksum mismatch on download {url}\n",
              url => $resp->request->uri);
  } else {
    if ($self->{'verbose'} >= 2) {
      print "Content-MD5 ok\n";
    }
  }
}

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
      && $resp->headers->content_is_html) {
    my $old = $resp->header('Content-Type');
    $resp->header('Content-Type' => $resp->headers->content_type);

    if ($self->{'verbose'} >= 2) {
      say 'html_charset_from_content mangled Content-Type from';
      say "   from $old";
      say "   to   ", $resp->header('Content-Type');
      say "   giving charset ", $resp->content_charset;
    }
  }
}


#------------------------------------------------------------------------------
my %known;

# <dc:valid> dates through which thing is valid
# ENHANCE-ME: is this something to work into the skipdays? or a message expiry?
$known{'/channel/item/dc:valid'} = undef;

# <eq:depth> earthquake depth, repeat of text
# <eq:seconds> unix seconds since 1970 date of earthquake, repeating text
@known{qw(/channel/item/eq:depth
          /channel/item/eq:seconds)} = ();

# rdf structure stuff
@known{qw(/channel/items
          /channel/items/rdf:Seq
          /channel/items/rdf:Seq/rdf:li)} = ();

@known{qw(
           /channel/cloud
           /channel/link
           /channel/docs
           /channel/generator
           /channel/rating
           /channel/id
           /channel/description
           /channel/tagline
           /channel/info      --atom-something-freeform
           /channel/itunes:summary
           /channel/item/dc:audience
           /channel/feedburner:info

           --nothing-much-in-these-as-yet-eg.-rssboard
           /channel/item/sitemap:priority
           /channel/item/sitemap:changefreq

           --feedburner-junk
           /channel/feedburner:feedFlare

           --images
           /channel/itunes:owner
           /channel/itunes:owner/itunes:name
           /channel/itunes:owner/itunes:email

           /channel/textInput
           /channel/textInput/description
           /channel/textInput/link
           /channel/textInput/name
           /channel/textInput/title
           /channel/textinput
           /channel/textinput/title
           /channel/textinput/description
           /channel/textinput/name
           /channel/textinput/link

           /channel/openSearch:totalResults
           /channel/openSearch:startIndex
           /channel/openSearch:itemsPerPage

           /channel/item
           /channel/item/source

        )} = ();

# --weather
# /channel/item/w:current
# /channel/item/w:forecast
# /channel/yweather:location
# /channel/yweather:units
# /channel/yweather:wind
# /channel/yweather:atmosphere
# /channel/yweather:astronomy
# /channel/item/yweather:condition
# /channel/item/yweather:forecast

# RBA per http://www.rba.gov.au/rss/rss-cb-exchange-rates.xml
# <cb:statistics> repeats in structured form the rate shown in the text
#
# Fed Reserve per http://www.federalreserve.gov/feeds/press_taf.xml
# <cb:news> repeats plain text
#
# Fed eg. http://www.federalreserve.gov/feeds/speeches.xml
# FIXME: <cb:speech> may have bit extra detail
#
# Fed eg. http://www.federalreserve.gov/feeds/ifdp.xml
# <cb:paper> repeat in structured form
# FIXME: except <cb:resource><cb:link> has extra pdf form link
#
# <cb:event> guess likewise
#
@known{qw(/channel/item/cb:statistics
          /channel/item/cb:news
          /channel/item/cb:speech
          /channel/item/cb:paper
          /channel/item/cb:event
        )} = ();
# --central-bank
# /channel/item/cb:statistics
# /channel/item/cb:statistics/cb:country
# /channel/item/cb:statistics/cb:institutionAbbrev
# /channel/item/cb:statistics/cb:exchangeRate
# /channel/item/cb:statistics/cb:exchangeRate/cb:value
# /channel/item/cb:statistics/cb:exchangeRate/cb:baseCurrency
# /channel/item/cb:statistics/cb:exchangeRate/cb:targetCurrency
# /channel/item/cb:statistics/cb:exchangeRate/cb:rateType
# /channel/item/cb:statistics/cb:exchangeRate/cb:observationPeriod
# /channel/item/cb:speech
# /channel/item/cb:speech/cb:simpleTitle
# /channel/item/cb:speech/cb:occurrenceDate
# /channel/item/cb:speech/cb:person
# /channel/item/cb:speech/cb:person/cb:givenName
# /channel/item/cb:speech/cb:person/cb:surname
# /channel/item/cb:speech/cb:person/cb:personalTitle
# /channel/item/cb:speech/cb:person/cb:nameAsWritten
# /channel/item/cb:speech/cb:person/cb:role
# /channel/item/cb:speech/cb:person/cb:role/cb:jobTitle
# /channel/item/cb:speech/cb:person/cb:role/cb:affiliation
# /channel/item/cb:speech/cb:venue


#------------------------------------------------------------------------------
# dates

use constant RFC822_STRFTIME_FORMAT => '%a, %d %b %Y %H:%M:%S %z';

# return a string which is current time in RFC 822 format
sub rfc822_time_now {
  return POSIX::strftime (RFC822_STRFTIME_FORMAT, localtime(time()));
}

sub isodate_to_rfc822 {
  my ($isodate) = @_;
  if (! defined $isodate) { return undef; }
  my $date = $isodate;  # the original goes through if unrecognised

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

# Return an RFC822 date string, or undef if nothing known.
# This gets a sensible sort-by-date in the newsreader.
sub item_to_date {
  my ($self, $item) = @_;
  my $date;
  foreach my $elt ($item, item_to_channel($item)) {
    $date = (non_empty    ($elt->first_child_trimmed_text('pubDate'))
             // non_empty ($elt->first_child_trimmed_text('dc:date'))
             # Atom
             // non_empty ($elt->first_child_trimmed_text('modified'))
             // non_empty ($elt->first_child_trimmed_text('updated'))
             // non_empty ($elt->first_child_trimmed_text('issued'))
             // non_empty ($elt->first_child_trimmed_text('created'))
             # channel
             // non_empty ($elt->first_child_trimmed_text('lastBuildDate'))
             # Atom
             // non_empty ($elt->first_child_trimmed_text('published'))
            );
    last if defined $date;
  }
  return isodate_to_rfc822($date);
}
@known{qw(/channel/dc:date
          /channel/lastBuildDate
          /channel/pubDate
          /channel/updated
          /channel/modified

          /channel/item/dc:date
          /channel/item/pubDate
          /channel/item/updated
          /channel/item/published
          /channel/item/modified
          /channel/item/created
          /channel/item/issued
        )} = ();


sub item_to_timet {
  my ($self, $item) = @_;
  my $str = $self->item_to_date($item)
    // return - POSIX::DBL_MAX(); # no date fields

  require Date::Parse;
  return (Date::Parse::str2time($str)
          // do {
            say __x('Unrecognised date "{date}" from {url}',
                    date => $str,
                    url  => $self->{'uri'});
            -POSIX::DBL_MAX();
          });
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
  return (non_empty($uri->host) // 'localhost') . ':' . $uri->port;
}

sub nntp {
  my ($self) = @_;
  # reopen if different 'nntp_host'
  if (! $self->{'nntp'}
      || $self->{'nntp'}->host ne $self->{'nntp_host'}) {
    my $host = $self->{'nntp_host'};
    if ($self->{'verbose'} >= 1) { say __x("nntp: {host}", host => $host); }
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
        say "Hmm, ", $nntp->host, " doesn't say \"posting ok\" ...";
      }
    }
  }
  return $self->{'nntp'};
}

sub nntp_close {
  my ($self) = @_;
  if (my $nntp = delete $self->{'nntp'}) {
    if (! $nntp->quit) {
      say "Error closing nntp: ",$self->{'nntp'}->message;
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
    say "'$msgid' ", ($ret ? 'exists already' : 'new');
  } elsif ($self->{'verbose'} >= 1) {
    if ($ret) { say __('  exists already'); }
  }
  return $ret;
}

# post $msg to NNTP, return true if successful
sub nntp_post {
  my ($self, $msg) = @_;
  my $nntp = $self->nntp;
  if (! $nntp->post ($msg->as_string)) {
    say __x('Cannot post: {message}',
            message => scalar($nntp->message));
    return 0;
  }
  return 1;
}


#------------------------------------------------------------------------------
# HTML title

Hash::Util::FieldHash::fieldhash (my %resp_exiftool_info);

# return hashref { Title => $str, ... }, or empty {} if no exiftool etc
sub resp_exiftool_info {
  my ($resp) = @_;
  defined $resp or return {};
  if (! exists $resp_exiftool_info{$resp}) {
    $resp_exiftool_info{$resp} = _resp_exiftool_info($resp);
    ### exiftool info: $resp_exiftool_info{$resp}
  }
  return $resp_exiftool_info{$resp};
}
sub _resp_exiftool_info {
  my ($resp) = @_;

  # Want ExifTool 8.22 to have PNG tEXt returned as utf8, but don't bother
  # to enforce that.
  #
  # The returned fields from image formats with a defined charset are
  # converted to the exiftool default "Charset" of utf8, and from other
  # image formats the fields are bytes of something unknown.  Might slightly
  # like to know which is the case, and show raw bytes different from "bytes
  # which ought to be utf8", but for now just Encode::decode_utf8() and let
  # its Encode::FB_DEFAULT() put substitution chars for non-ascii non-utf8.
  #
  eval { require Image::ExifTool; 1 } || return {};
  $resp->decode;
  my $cref = $resp->content_ref;
  return Image::ExifTool::ImageInfo
    ($cref,
     ['Title','Author','Copyright','ImageSize'], # just these tags
     {List => 0});       # get list values as comma separated
}

# $resp is a HTTP::Response, return title
sub html_title {
  my ($resp) = @_;

  return (# for images prefer filename+size over URI::Title just filename
          non_empty (html_title_exiftool_image($resp))

          // non_empty (html_title_urititle($resp))
          // non_empty (html_title_exiftool($resp))
          // $resp->title);
}
sub html_title_urititle {
  my ($resp) = @_;
  eval { require URI::Title } or return undef;

  # suppress some dodginess in URI::Title 1.82
  local $SIG{'__WARN__'} = sub {
    my ($msg) = @_;
    $msg =~ /Use of uninitialized value/ or warn @_;
  };
  $resp->decode;
  return URI::Title::title
    ({ url  => ($resp->request->uri // ''),
       data => $resp->content});
}
sub html_title_exiftool_image {
  my ($resp) = @_;
  $resp->content_type =~ m{^image/} or return;
  if (defined (my $title = html_title_exiftool($resp))) {
    return $title;
  }
  my $info = resp_exiftool_info($resp) // return;
  ### html_title_exiftool_image() on: $info
  defined $info->{'ImageSize'} or return;
  return $resp->filename.' '.$info->{'ImageSize'};
}
sub html_title_exiftool {
  my ($resp) = @_;
  my $title = resp_exiftool_info($resp)->{'Title'} // return;
  return Encode::decode_utf8 ($title);
}


#------------------------------------------------------------------------------
# mime

# prepended to "X-Mailer" header
use constant mime_mailer_extra => "RSS2Leafnode $VERSION";

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

# if $str is not ascii then apply encode_mimewords()
sub mimewords_non_ascii {
  my ($str) = @_;
  if (defined $str && ! is_ascii($str)) {
    require MIME::Words;
    $str = MIME::Words::encode_mimewords (Encode::encode_utf8($str),
                                          Charset => 'UTF-8');
  }
  return $str;
}

sub mime_build {
  my ($self, $headers, @args) = @_;

  # Headers in utf-8, the same as other text.  The docs of
  # encode_mimewords() isn't clear, but seems to expect bytes of the
  # specified charset.
  foreach my $key (sort keys %$headers) {
    $headers->{$key}
      = mimewords_non_ascii(Text::Trim::trim($headers->{$key}));
  }

  %$headers = (%$headers, @args);
  $headers->{'Top'}      //= 0;  # default to a part not a toplevel
  $headers->{'Encoding'} //= '-SUGGEST';

  if ($headers->{'Top'}) {
    my $now822 = rfc822_time_now();
    $headers->{'Date'} //= $now822;
    $headers->{'Date-Received:'} = $now822;
  }

  if (utf8::is_utf8($headers->{'Data'})) {
    warn 'Oops, mime_build() data should be bytes';
  }

  # downgrade utf-8 to us-ascii if possible
  if ($headers->{'Type'} eq 'text/plain'
      && lc($headers->{'Charset'}||0) eq 'utf-8'
      && is_ascii ($headers->{'Data'})) {
    $headers->{'Charset'} = 'us-ascii';

    # not sure mangling text/html body content is a good idea -- would only
    # want it on generated html, not downloaded
    #
    # if ($headers->{'Type'} eq 'text/html') {
    #   $headers->{'Data'} =~ s{(<meta http-equiv=Content-Type content="text/html; charset=)([^"]+)}{$1us-ascii};
    # }
  }

  @args = map {$_,$headers->{$_}} sort keys %$headers;
  if ($self->{'verbose'} >= 4) {
    require Data::Dumper;
    print Data::Dumper->new([\@args],['mime headers'])->Dump;
  }

  require MIME::Entity;
  my $top = MIME::Entity->build (Disposition => 'inline', @args);

  if ($headers->{'Top'} && ! defined $headers->{'X-Mailer:'}) {
    my $head = $top->head;
    $head->set('X-Mailer', join_non_empty (', ',
                                           $self->mime_mailer_extra,
                                           $head->get('X-Mailer')));
  }

  return $top;
}

sub mime_part_from_response {
  my ($self, $resp, @headers) = @_;

  my $content_type = $resp->content_type;
  if ($self->{'verbose'} >= 2) { say " content-type: $content_type"; }
  $resp->decode;
  my $content      = $resp->content;         # the bytes
  my $charset      = $resp->content_charset; # and their charset
  my $url          = $resp->request->uri->as_string;
  my $content_md5  = $resp->header('Content-MD5');

  ($content, $content_type, $charset, my $rendered)
    = $self->render_maybe ($content, $content_type, $charset, $url);
  if ($rendered) {
    undef $content_md5;
  }

  return $self->mime_build
    ({ 'Content-Language:' => scalar ($resp->header('Content-Language')),
       'Content-Location:' => $url,
       'Content-MD5:'      => $content_md5,
       @headers
     },
     Type        => $content_type,
     Charset     => $charset,
     Data        => $content,
     Filename    => $resp->filename);
}


# set "Lines:" header per RFC 1036
# MIME::Entity 5.428 doesn't seem to have anything for this itself
# this is after qp or base64, is that right? the actual message lines
sub mime_entity_lines {
  my ($top) = @_;
  $top->head->set('Lines', str_count_lines ($top->stringify_body));
}

#------------------------------------------------------------------------------
# XML::Twig stuff

sub elt_tree_strip_prefix {
  my ($elt, $prefix) = @_;
  foreach my $child ($elt->descendants_or_self(qr/^\Q$prefix\E:/)) {
    $child->set_tag ($child->local_name);
  }
}

# Return a URI object for string $url.
# If $url is relative then it's resolved against xml:base, if available, to
# make it absolute.
# If $url is undef then return undef, which is handy if passing a possibly
# attribute like $elt->att('href').
# The feed toplevel has an xml:base set to the feed location if no other
# value, so elt_xml_based_uri() ends up relative to the feed location if no
# other xml:base.
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

# Return the text of $elt and treat child elements as improperly escaped
# parts of the text too.
#
# This is good for elements which are supposed to be HTML with <p> etc
# escaped as &lt;p&gt;, but copes with feeds that don't have the necessary
# escapes and thus come out with xml child elements under $elt.
#
# For elements which are supposed to be plain text with no markup and no
# sub-elements this will at least make improper child text visible, though
# it might not look very good.
#
# As of June 2010 http://www.drweil.com/drw/ecs/rss.xml is an example of
# improperly escaped html.
#
# FIXME: Any need to watch out for <rdf:value> types?
#
sub elt_subtext {
  my ($elt) = @_;
  defined $elt or return undef;
  if ($elt->is_text) { return $elt->text; }
  return join ('', map {_elt_subtext_with_tags($_)} $elt->children);
}
sub _elt_subtext_with_tags {
  my ($elt) = @_;
  defined $elt or return undef;
  if ($elt->is_text) { return $elt->text; }
  return ($elt->start_tag
          . join ('', map {_elt_subtext_with_tags($_)} $elt->children)
          . $elt->end_tag);
}

# $elt contains xhtml <div> etc sub-elements.  Return a plain html string.
# Prefixes like <xhtml:b>Bold</xhtml:b> are turned into plain <b>.
# This relies on the map_xmlns mapping to give prefix "xhtml:"
#
sub elt_xhtml_to_html {
  my ($elt) = @_;

  # could probably do it destructively, but just in case
  $elt = $elt->copy;
  elt_tree_strip_prefix ($elt, 'xhtml');

  # lose xmlns:xhtml="http://www.w3.org/1999/xhtml"
  $elt->strip_att('xmlns:xhtml');

  # something fishy turns "href" to "xhtml:href", drop back to "href"
  foreach my $child ($elt->descendants) {
    foreach my $attname ($child->att_names) {
      if ($attname =~ /^xhtml:(.*)/) {
        $child->change_att_name($attname, $1);
      }
    }
  }
  return $elt->xml_string;
}

# elt_content_type() returns 'text', 'html', 'xhtml' or a mime type.
# If no type="" attribute the default is 'text', except for RSS
# <description> which is 'html'.
#
# RSS http://www.debian.org/News/weekly/dwn.en.rdf circa Feb 2010 had some
# html in its <title>, but believe that's an error (mozilla shows it as
# plain text) and that RSS is all plain text outside <description>.
#
sub elt_content_type {
  my ($elt) = @_;
  if (! defined $elt) { return undef; }

  if (defined (my $type = ($elt->att('atom:type') // $elt->att('type')))) {
    # type="application/xhtml+xml" at http://xmltwig.com/blog/index.atom,
    # dunno if it should be just "xhtml", but recognise it anyway
    if ($type eq 'application/xhtml+xml') { return 'xhtml'; }
    return $type;
  }
  if ($elt->root->tag eq 'feed') {
    return 'text';  # Atom <feed> defaults to text
  }
  my $tag = $elt->tag;
  if ($tag =~ /^itunes:/) {
    # itunes spec is for text-only, no html markup
    return 'text';
  }
  if ($tag eq 'description'           # RSS <description> is encoded html
      || $tag eq 'content:encoded') { # same in content:encoded
    return 'html';
  }
  # other RSS is text
  return 'text';
}

# $elt is an XML::Twig::Elt of an RSS or Atom text element.
# Atom has a type="" attribute, RSS is html.  Html or xhtml are rendered to
# a single long line of plain text.
#
sub elt_to_rendered_line {
  my ($elt) = @_;
  defined $elt or return;

  my $str;
  my $type = elt_content_type ($elt);
  if ($type eq 'xhtml') {
    $str = elt_xhtml_to_html ($elt);
    $type = 'html';
  } else {
    $str = elt_subtext($elt);
  }
  if ($type eq 'html') {
    require HTML::FormatText;
    $str = HTML::FormatText->format_string ($str,
                                            leftmargin => 0,
                                            rightmargin => 999);
  }
  # plain 'text' or anything unrecognised collapsed too
  return non_empty(collapse_whitespace($str));
}


#------------------------------------------------------------------------------
# XML::RSS::Timing

sub twig_to_timingfields {
  my ($self, $twig) = @_;
  return if ! defined $twig;
  my $root = $twig->root;
  my %timingfields;

  if (my $ttl = $root->first_descendant('ttl')) {
    $timingfields{'ttl'} = $ttl->trimmed_text;
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
  if (! %timingfields) {
    return; # no info
  }

  # if XML::RSS::Timing doesn't like the values then don't record them
  return unless $self->timingfields_to_timing(\%timingfields);

  return \%timingfields;
}
@known{qw(/channel/skipDays
          /channel/skipDays/day
          /channel/skipHours
          /channel/skipHours/hour
          /channel/ttl
          /channel/syn:updateBase
          /channel/syn:updatePeriod
          /channel/syn:updateFrequency)} = ();

# return an XML::RSS::Timing object, or undef
sub timingfields_to_timing {
  my ($self, $timingfields) = @_;
  $timingfields // return undef;

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
    say __x('XML::RSS::Timing complains on {url}',
            url => $self->{'uri'});
    foreach my $complaint (@complaints) {
      say "  $complaint";
    }
    return undef;
  }
  return $timing;
}


#------------------------------------------------------------------------------
# rss2leafnode.status file

# $self->{'global_status'} is a hashref containing entries URL => STATUS,
# where URL is a string and STATUS is a sub-hashref of information

use constant STATUS_EXPIRE_DAYS => 21;

# read $status_filename into $self->{'global_status'}
sub status_read {
  my ($self) = @_;
  $self->{'global_status'} = {};
  my $status_filename = $self->status_filename;
  if ($self->{'verbose'} >= 2) { say "read status: $status_filename"; }

  $! = 0;
  my $global_status = do $status_filename;
  if (! defined $global_status) {
    if ($! == POSIX::ENOENT()) {
      if ($self->{'verbose'} >= 2) { say "status file doesn't exist"; }
    } else {
      say "rss2leafnode: error in $status_filename\n$@";
      say "ignoring that file";
    }
    $global_status = {};
  }
  $self->{'global_status'} = $global_status;
}

# delete old entries from $self->{'global_status'}
sub status_prune {
  my ($self) = @_;
  my $global_status = $self->{'global_status'} // return;
  my $pruned = 0;
  my $old_time = time() - STATUS_EXPIRE_DAYS * 86400;
  foreach my $key (keys %$global_status) {
    if ($global_status->{$key}->{'status-time'} < $old_time) {
      if ($self->{'verbose'} >= 2) {
        print __x("discard old status {url}\n", url => $key);
      }
      delete $global_status->{$key};
      $pruned++;
    }
  }
  if ($pruned && $self->{'verbose'}) {
    print __xn("discard {count} old status entry\n",
               "discard {count} old status entries\n",
               $pruned,
               count => $pruned);
  }
}

# save $self->{'global_status'} into the $status_filename
sub status_save {
  my ($self, $status) = @_;
  $status->{'status-time'} = time();
  if ($status->{'timingfields'}) {
    $status->{'timingfields'}->{'lastPolled'} = $status->{'status-time'};
  }

  $self->status_prune;

  require Data::Dumper;
  my $str = Data::Dumper->new([$self->{'global_status'}],['global_status'])
    ->Indent(1)->Sortkeys(1)->Terse(1)->Useqq(1)->Dump;
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
# Optional $twig is an XML::Twig.
# Record against $url any ETag, Last-Modified and ttl from $resp and $twig.
# If $resp is an error return, or is undef, then do nothing.
sub status_etagmod_resp {
  my ($self, $url, $resp, $twig) = @_;
  if ($resp && $resp->is_success) {
    my $status = $self->status_geturl ($url);
    $status->{'Last-Modified'} = $resp->header('Last-Modified');
    $status->{'ETag'}          = $resp->header('ETag');
    $status->{'timingfields'}  = $self->twig_to_timingfields ($twig);

    if ($twig) {
      if (rss_newest_cmp($self,$status) > 0) {
        # the newest number increases
        $status->{'rss_newest_only'} = $self->{'rss_newest_only'};
      }
    }
    foreach my $key (keys %$status) {
      if (! defined $status->{$key}) { delete $status->{$key} }
    }
    $self->status_save($status);
  }
}

# update recorded status for a $url with unchanged contents
sub status_unchanged {
  my ($self, $url) = @_;
  if ($self->{'verbose'} >= 1) { say __('  unchanged'); }
  $self->status_save ($self->status_geturl ($url));
}

# $req is a HTTP::Request object.
# Add "If-None-Match" and/or "If-Modified-Since" headers to it based on what
# the status file has recorded from when we last fetched the url in $req.
# Return 1 to download, 0 if nothing expected yet by RSS timing fields
#
sub status_etagmod_req {
  my ($self, $req, $for_rss) = @_;
  $self->{'global_status'} or $self->status_read;

  my $url = $req->uri->as_string;
  my $status = $self->{'global_status'}->{$url}
    // do {
      if ($self->{'verbose'} >= 2) {
        print __x("no status info for {url}\n", url => $url);
      }
      return 1; # download
    };

  if ($for_rss) {
    # if status says the last download was for only a certain number of
    # newest, then force a re-download if the now desired newest is greater
    if (rss_newest_cmp($self,$status) > 0) {
      return 1;
    }
  }

  if (my $timing = $self->timingfields_to_timing ($status->{'timingfields'})) {
    my $next = $timing->nextUpdate;
    my $now = time();
    if ($next > $now) {
      if ($self->{'verbose'} >= 1) {
        say __x(' timing: next update {time} (local time)',
                time => POSIX::strftime ("%H:%M:%S %a %d %b %Y",
                                         localtime($next)));
        if (eval 'use Time::Duration::Locale; 1'
            || eval 'use Time::Duration; 1') {
          say __x('         which is {duration} from now',
                  duration => duration($next-$now));
        }
      }
      return 0; # no update yet
    }
  }
  if (defined (my $lastmod = $status->{'Last-Modified'})) {
    $req->header('If-Modified-Since' => $lastmod);
  }
  if (defined (my $etag = $status->{'ETag'})) {
    $req->header('If-None-Match' => $etag);
  }
  return 1;
}

# return -1 if x<y, 0 if x==y, or 1 if x>1
sub rss_newest_cmp {
  my ($x, $y) = @_;
  if ($x->{'rss_newest_only'}) {
    if (! $y->{'rss_newest_only'}) {
      return -1;  # x finite, y infinite
    }
    # x and y finite
    return ($x->{'rss_newest_only'} <=> $y->{'rss_newest_only'});
  } else {
    # x infinite, so 1 if y finite, 0 if y infinite too
    return !! $y->{'rss_newest_only'};
  }
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
  my ($self, $content, $content_type, $charset, $base_url) = @_;
  my $rendered = 0;
  if ($self->{'render'} && $content_type eq 'text/html') {

    my $class = $self->{'render'};
    if ($class !~ /^HTML::/) { $class = "HTML::FormatText::\u$class"; }
    $class =~ s/::1$//;  # "::1" is $render=1 for plain HTML::FormatText
    require Module::Load;
    Module::Load::load ($class);

    if ($class =~ /^HTML::FormatText($|::WithLinks)/) {
      # Believe HTML::FormatText (as of version 2.04) doesn't know much
      # about input or output charsets, but it can be tricked into getting
      # pretty reasonable results by putting wide chars through it.
      # Likewise HTML::FormatText::WithLinks (as of version 0.11).
      #
      $content = Encode::decode ($charset, $content);
      local $SIG{'__WARN__'} = \&_warn_suppress_unknown_base;
      $content = $class->format_string
        ($content,
         base        => $base_url,
         leftmargin  => 0,
         rightmargin => $self->{'render_width'});
      $content = Encode::encode_utf8 ($content);

    } else {
      # HTML::FormatExternal style charset specs
      $content = $class->format_string
        ($content,
         base           => $base_url,
         leftmargin     => 0,
         rightmargin    => $self->{'render_width'},
         input_charset  => $charset,
         output_charset => 'utf-8');
    }
    $charset = 'UTF-8';
    $content_type = 'text/plain';
    $rendered = 1;
  }
  return ($content, $content_type, $charset, $rendered);
}
sub _warn_suppress_unknown_base {
  my ($msg) = @_;
  $msg =~ /^Unknown configure option 'base'/
    or warn $msg;
}

# $str is a wide-char string of text
sub text_wrap {
  my ($self, $str, $prefix) = @_;
  if (! defined $prefix) { $prefix = ''; }
  require Text::WrapI18N;
  local $Text::WrapI18N::columns = $self->{'render_width'} + 1;
  local $Text::WrapI18N::unexpand = 0;       # no tabs in output
  local $Text::WrapI18N::huge = 'overflow';  # don't break long words
  $str =~ tr/\n/ /;
  my $second_prefix = (length($prefix) ? ' 'x(length($prefix)+2) : '');
  return Text::WrapI18N::wrap($prefix, $second_prefix, $str);
}

#------------------------------------------------------------------------------
# Face icons

# $item is an XML::Twig::Elt of an RSS or Atom item
# return a string value for the Face: header, or undef if no icon
sub item_to_face {
  my ($self, $item) = @_;
  $self->{'get_icon'} || return;
  my ($uri, $width, $height) = $self->item_image_uwh ($item)
    or return;
  $self->face_wh_ok ($width, $height) || return;
  return $self->download_face ($uri, $width, $height);
}

# $item is an XML::Twig::Elt of an RSS or Atom item
# return values ($uri, $width, $height) of the <image> etc from it
#
sub item_image_uwh {
  my ($self, $item) = @_;
  ### item_image_uwh()

  # normally only in channel, doesn't hurt to look in item the same as
  # <itunes:image> can be in the item
  #
  foreach my $where ($item, item_to_channel($item)) {
    ### image text: $where->first_child_text('image')

    # RSS
    # <image>
    #   <url>foo.png</url>
    #   <width>...</width>     optional
    #   <height>...</height>   optional
    # </image>
    if (my $image_elt = $where->first_child('image')) {
      my $url_elt; # XML::Twig::Elt where the url came from
      my $url;     # url string
      if ($url_elt = $image_elt->first_child('url')) {
        $url = $url_elt->trimmed_text;
      } else {
        # Cooper Hewitt museum http://blog.cooperhewitt.org/rss/?limit=10
        # item <image> as html text like
        #    <image>
        #       <![CDATA[<img src="http://blog.cooperhewitt.org/images/277t.jpg" alt="" />]]>
        #    </image>
        # don't want to encourage dodginess like this, but picking it out
        # isn't too hard
        if ($image_elt->text =~ /<img[^>]*\ssrc="([^"]*)/) {
          ### image from html: $1
          $url_elt = $image_elt;
          $url = $1;
        }
      }
      if (is_non_empty ($url)) {
        require Scalar::Util;
        my $width = $image_elt->first_child_text('width');
        unless (Scalar::Util::looks_like_number($width) && $width > 0) {
          $width = 0;
        }
        my $height = $image_elt->first_child_text('height');
        unless (Scalar::Util::looks_like_number($height) && $height > 0) {
          $height = 0;
        }
        ### item_image_uwh() RSS: $url
        return (elt_xml_based_uri ($url_elt, $url),
                $width, $height);
      }
    }

    # Atom channel <icon>foo.png</icon>   should be square
    # or   channel <logo>foo.png</logo>   bigger form, rectangle 2*K x K
    #
    # <itunes:image href="http://..."> in item or channel.  Supposedly this
    # is bigger than the RSS 48x48, so would probably need shrinking.  Rate
    # it below <icon> or <logo> for that reason.
    #
    # <media:thumbnail href="" width="" height=""> snapshot of movie etc
    # Is it better to show the channel icon, being the From person?
    {
      my $elt;
      my ($width, $height);
      my $url = ((($elt = $where->first_child('icon'))
                  && non_empty ($elt->text))
                 || (($elt = $where->first_child('logo'))
                     && non_empty ($elt->text))
                 || (($elt = $where->first_child('itunes:image'))
                     && non_empty ($elt->att('href')))
                 || (($elt = $where->first_child('media:thumbnail'))
                     && is_non_empty ($elt->att('url'))
                     && do {
                       $width = $elt->att('width');
                       $height = $elt->att('height');
                       $elt->att('url') }));
      ### $url
      if ($url) {
        unless (Scalar::Util::looks_like_number($width) && $width > 0) {
          $width = 0;
        }
        unless (Scalar::Util::looks_like_number($height) && $height > 0) {
          $height = 0;
        }
        return (elt_xml_based_uri ($elt, $url),
                $width,
                $height);
      }
    }
  }
  return;
}
@known{qw(/channel/logo
          /channel/icon
          /channel/image
          /channel/image/url
          /channel/image/width
          /channel/image/height
          /channel/image/title
          /channel/image/link
          /channel/image/description
          /channel/itunes:image

          /channel/item/image
          /channel/item/media:thumbnail

        )} = ();

# $resp is a HTTP::Response
# return a string value for the Face: header, or undef if no icon
sub http_resp_to_face {
  my ($self, $resp) = @_;
  $self->{'get_icon'} || return;

  my $uri = http_resp_favicon_uri($resp) || return;
  if ($self->{'verbose'} >= 2) {
    say " response favicon URI: $uri";
  }
  return $self->download_face ($uri, 0, 0);
}

# $resp is a HTTP::Response
# if it's a html with a favicon link return a URI object of that image
#
sub http_resp_favicon_uri {
  my ($resp) = @_;
  $resp->headers->content_is_html || return;
  require HTML::Parser;
  my $href;
  my $p;
  $p = HTML::Parser->new (api_version => 3,
                          start_h => [ sub {
                                         my ($tagname, $attr) = @_;
                                         if ($tagname eq 'link'
                                             && $attr->{'rel'} eq 'icon') {
                                           $href = $attr->{'href'};
                                           $p->eof;
                                         }
                                       }, "tagname, attr"]);
  $resp->decode;
  $p->parse ($resp->content);
  return $href && URI->new_abs ($href, $resp->base);
}

# return base64 string value for "Face:" header
sub download_face {
  my ($self, $uri, $width, $height) = @_;
  my $key = $uri->canonical->as_string;
  if (! exists $self->{'download_face'}->{$key}) {
    $self->{'download_face'}->{$key}
      = $self->download_face_uncached ($uri, $width, $height);
  }
  return $self->{'download_face'}->{$key};
}
sub download_face_uncached {
  my ($self, $url, $width, $height) = @_;

  if ($self->{'verbose'}) {
    print "  image download: $url\n";
  }
  require HTTP::Request;
  my $req = HTTP::Request->new (GET => $url);
  my $resp = $self->ua->request($req);
  if (! $resp->is_success) {
    print __x("  no image: {status}\n",
              status => $resp->status_line);
    return;
  }

  my $type = $resp->content_type;
  ### $type
  if ($type =~ m{^image/(.*)$}i) {
    $type = $1;
  } else {
    if ($self->{'verbose'} >= 2) {
      print "ignore non-image icon type: $type\n";
    }
    return;
  }

  $resp->decode;
  my $data = $resp->content;
  if ($type ne 'png'
      || $width == 0 || $height == 0
      || $width > 48 || $height > 48) {
    $data = $self->imagemagick_to_png($type,$data) // return;
  }
  if ($self->{'verbose'} >= 2) {
    print "  image for Face ",length($data)," bytes\n";
  }

  # use a space as a separator since MIME::Entity will collapse out a
  # newline and make an enormous long word which then can't be split across
  # header lines and will likely exceed the nntp 998 char single-line limit
  require MIME::Base64;
  $data = MIME::Base64::encode_base64($data, " ");
  ### $data

  return $data;
}

sub face_wh_ok {
  my ($self, $width, $height) = @_;

  if ($width > 0 && $width > 2*$height) {
    # some obnoxious banner
    if ($self->{'verbose'} >= 1) {
      print "   image is a banner (${width}x${height}), ignore\n";
    }
    return 0;
  }
  return 1;
}

#------------------------------------------------------------------------------
# ImageMagick bits

# $type is "gif", "ico" etc, $data is an image in a byte string
# return a byte string of png, or undef if $data unrecognised
sub imagemagick_to_png {
  my ($self, $type, $data) = @_;
  ### $type
  my $image = $self->imagemagick_from_data($type,$data) // return;

  my $width = $image->Get('width');
  my $height = $image->Get('height');
  ### compress: $image->Get('compression')
  if ($self->{'verbose'} >= 2) {
    print "   image ${width}x${height}\n";
  }
  if ($width == 0 || $height == 0) {
    return;
  }
  if ($width <= 48 && $height <= 48 && $type eq 'png') {
    return $data;
  }

  # having downloaded the image is it better to keep a banner but shrink it,
  # or discard as no good?
  #
  # $self->face_wh_ok ($width, $height) || return;

  if ($width > 48 || $height > 48) {
    my $factor;
    if ($width <= 2*48 && $height <= 2*48) {
      $factor = 0.5;
    } else {
      $factor = min (48 / $width, 48 / $height);
    }
    $width = POSIX::ceil ($width * $factor);
    $height = POSIX::ceil ($height * $factor);
    if ($self->{'verbose'} >= 2) {
      print "  image shrink by $factor to ${width}x${height}\n";
    }
    # cf LiquidResize() or plain Resize()
    $image->AdaptiveResize (width => $width, height => $height);
  }

  my $ret = $image->Set (magick => 'PNG8');
  ### ret: "$ret"
  ### ret: $ret+0
  if ($ret != 0) {
    print "oops, imagemagick doesn't like PNG8: $ret\n";
    return;
  }
  ### compress: $image->Get('compression')

  # $image->Write ('/tmp/x.png');
  ($data) = $image->ImageToBlob ();
  return $data;
}


# $type is "png", "ico" etc, $data is an image in a byte string
# return a Image::Magick object, or undef if Perl-Magick not available
sub imagemagick_from_data {
  my ($self, $type, $data) = @_;
  eval { require Image::Magick } or return;
  my $image = Image::Magick->new;
  # $image->Set(debug=>'All');
  $image->Set (magick=>$type);
  my $ret = $image->BlobToImage ($data);
  ### ret: "$ret"
  ### ret: $ret+0
  if ($ret != 1) {
    print "  imagemagick doesn't like image data: $ret\n";
    return;
  }
  return $image;
}



#------------------------------------------------------------------------------
# error as news message

sub error_message {
  my ($self, $subject, $message, $attach_bytes) = @_;

  require Encode;
  my $charset = 'utf-8';
  $message = str_ensure_newline ($message);
  $message = Encode::encode ($charset, $message, Encode::FB_DEFAULT());

  my $date = rfc822_time_now();
  require Digest::MD5;
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
     Top     => 1,
     Type    => 'text/plain',
     Charset => $charset,
     Data    => $message);

  if (defined $attach_bytes) {
    $top->make_multipart;
    my $part = $self->mime_build
      ({},
       Charset  => 'none',
       Type     => 'application/octet-stream',
       Data     => $attach_bytes);
    $top->add_part ($part);
  }

  mime_entity_lines($top);
  $self->nntp_post($top) || return;
  say __x('{group} 1 new article', group => $self->{'nntp_group'});
}


#------------------------------------------------------------------------------
# fetch HTML

sub http_resp_to_from {
  my ($self, $resp) = @_;
  ### http_resp_to_from()
  return $self->http_resp_exiftool_author($resp)
    // 'nobody@'.$self->uri_to_host;
}
sub http_resp_exiftool_author {
  my ($self, $resp) = @_;
  # PNG Author field, or HTML <meta> author
  my $author = resp_exiftool_info($resp)->{'Author'} // return;
  return $self->email_format_maybe (Encode::decode_utf8($author), '', undef);
}

sub http_resp_to_copyright {
  my ($self, $resp) = @_;
  ### http_resp_to_copyright()
  if ($resp->content_type =~ m{^text/}) { return; }
  # PNG Copyright field, perhaps other formats
  my $copyright = resp_exiftool_info($resp)->{'Copyright'} // return;
  return Encode::decode_utf8($copyright);
}

sub fetch_html {
  my ($self, $group, $url) = @_;
  ### fetch_html()
  if ($self->{'verbose'} >= 1) { say "page: $url"; }

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
  if ($self->{'verbose'} >= 2) {
    print $resp->headers->as_string;
  }
  $self->enforce_html_charset_from_content ($resp);

  # message id is either the etag if present, or an md5 of the content if not
  my $msgid = $self->url_to_msgid
    ($url,
     $resp->header('ETag') // do {
       require Digest::MD5;
       $resp->decode;
       my $content = $resp->content;
       Digest::MD5::md5_base64($content)
       });
  return 0 if $self->nntp_message_id_exists ($msgid);

  my $subject = (html_title($resp)
                 // $resp->filename
                 # show original url in subject, not anywhere redirected
                 // __x('RSS2Leafnode {url}', url => $url));

  my $top = $self->mime_part_from_response
    ($resp,
     Top                 => 1,
     'Path:'             => scalar ($self->uri_to_host),
     'Newsgroups:'       => $group,
     From                => scalar ($self->http_resp_to_from($resp)),
     Subject             => $subject,
     Date                => scalar ($resp->header('Last-Modified')),
     'Message-ID'        => $msgid,
     'Face:'             => scalar ($self->http_resp_to_face($resp)),
     'X-Copyright:'      => scalar ($self->http_resp_to_copyright($resp)));

  mime_entity_lines($top);
  $self->nntp_post($top) || return;
  $self->status_etagmod_resp ($url, $resp);
  say __x("{group} 1 new article", group => $group);
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
  my $url = $item->first_child_text('link')
    // return undef;
  $url =~ m{^http://[^/]*yahoo\.com/.*\*(http://.*yahoo\.com.*)$}
    or return undef;
  return $1;
}

# This is a special case for Google Groups RSS feeds.
# The arguments are link elements [$name,$uri].  If there's a google groups
# like "http://groups.google.com/group/cfcdev/msg/445d4ccfdabf086b" then
# return a mailing list address like "cfcdev@googlegroups.com".  If not in
# that form then return undef.
#
sub googlegroups_link_email {
  ## no critic (RequireInterpolationOfMetachars)
  foreach my $l (@_) {
    if ($l->{'uri'}
        && $l->{'uri'}->canonical =~ m{^http://groups\.google\.com/group/([^/]+)/}) {
      return ($1 . '@googlegroups.com');
    }
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
    $resp->decode;
    my $content = $resp->content;
    if ($content =~ /<META[^>]*Refresh[^>]*checkForCookies/i) {
      if ($self->{'verbose'}) {
        say '  following aireview META Refresh with cookies';
      }
      require HTTP::Request;
      my $req = HTTP::Request->new (GET => $url);
      $resp = $self->ua->request($req);
    }
  }
  return $resp;
}


#------------------------------------------------------------------------------
# RSS links

# return list of hashrefs
#
sub item_to_links {
  my ($self, $item) = @_;

  # <feedburner:origLink> or <feedburner:origEnclosureLink> is when
  # something has been expanded into the item, or should it be shown?

  # FIXME: <media:content> can be a link, but have seen it just duplicating
  # <enclosure> without a length.  Would probably skip medium="image".
  # Can have a <media:title> sub-element.
  #
  # FIXME: <media:group> is a collection of <media:content> in different
  # formats etc.  Have seen this from archive.org just duplicating
  # <enclosure>.
  #
  my @elts = $item->children (qr/^(link
                                 |enclosure
                                 |content
                                 |wiki:diff
                                 |wiki:history
                                 |comments
                                 |wfw:comment
                                 )$/ix);
  my @links;
  my %seen;
  foreach my $elt (@elts) {
    if ($self->{'verbose'} >= 2) {
      say "link\n", Text::Trim::trim($elt->sprint);
    }

    my $tag = lc($elt->tag);
    ### $tag
    if ($tag eq 'content' && atom_content_flavour($elt) ne 'link') {
      next;
    }
    my $l = { download => 1 };

    foreach my $name ('hreflang', 'title', 'type') {
      $l->{$name} = ($elt->att("atom:$name") // $elt->att($name));
    }

    given (non_empty ($elt->att('atom:rel') // $elt->att('rel'))) {
      when (!defined) {
        given ($tag) {
          when (/diff/)      { $l->{'name'} = __('Diff:'); }
          when (/history/)   { $l->{'name'} = __('History:');
                               $l->{'download'} = 0;
                             }
          when ('enclosure') { $l->{'name'} = __('Encl:'); }
          when (/comment/) {
            if (defined (my $count = non_empty
                         ($item->first_child_text('slash:comments')))) {
              $l->{'name'} = __x('Comments({count}):', count => $count);
            } else {
              $l->{'name'} = __('Comments:');
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
        if ($self->{'verbose'} >= 1) { say "skip link \"$_\""; }
        next;
      }

      when ('alternate') {
        # "alternate" is supposed to be the content as the entry, but in a
        # web page or something.  Not sure that's always quite true, so show
        # it as a plain link.  If no <content> then an "alternate" is
        # supposed to be mandatory.
      }

      # when ('next') ... # not sure about "next" link

      when ('service.post') { $l->{'name'} = __('Comments:');
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
      when ('enclosure') { $l->{'name'} = __('Encl:') }
      when ('related')   { $l->{'name'} = __('Related:') }
      default { $l->{'name'} = __x('{linkrel}:', linkrel => $_) }
    }

    # Atom <link href="http:.."/>
    # RSS <link>http:..</link>
    # RSS <enclosure url="http:..">
    my $uri = (non_empty ($elt->att('atom:href'))   # Atom <link>
               // non_empty ($elt->att('href'))     # Atom <link>
               // non_empty ($elt->att('atom:src')) # Atom <content>
               // non_empty ($elt->att('src'))      # Atom <content>
               // non_empty ($elt->att('url'))      # RSS <enclosure>
               // non_empty ($elt->trimmed_text)    # RSS <link>
               // next);
    $uri = elt_xml_based_uri ($elt, $uri);

    # have seen same url under <link> and <comments> from sourceforge
    # http://sourceforge.net/export/rss2_keepsake.php?group_id=203650
    # so dedup
    if ($seen{$uri->canonical}++) {
      if ($self->{'verbose'} >= 1) { say "skip duplicate link \"$uri\""; }
      next;
    }

    $l->{'uri'} = $uri;
    $l->{'name'} //= __('Link:');

    my @paren;
    # show length if biggish, often provided on enclosures but not plain
    # links
    if (defined (my $length = ($elt->att('atom:length')
                               // $elt->att('length')))) {
      if ($length >= 2000) {
        push @paren, NUMBER_FORMAT()->format_bytes ($length, precision => 1);
      }
    }
    # <itunes:duration> applies to <enclosure>.  Just a number means
    # seconds, otherwise MM:SS or HH:MM:SS.
    if ($tag eq 'enclosure'
        && defined (my $duration = non_empty ($item->first_child_text('itunes:duration')))) {
      if ($duration !~ /:/) {
        $duration = __px('s-for-seconds', '{duration}s',
                         duration => $duration);
      }
      push @paren, $duration;
    }
    if (@paren) {
      $l->{'name'} =~ s{:}{ '(' . join(', ', @paren) . '):'}e;
    }

    push @links, $l;
  }

  # sort downloadables to the start, replies and comments to the end
  use sort 'stable';
  @links = sort {$b->{'download'}} @links;

  # lat/long last
  if (defined (my $str = $self->item_to_lat_long_alt_str ($item))) {
    push @links, { name => $str,
                   download => 0 };
  }

  return @links;
}
@known{qw(
           /channel/item/pheedo:origLink
           /channel/item/feedburner:origLink

           /channel/item/link
           /channel/item/enclosure
           /channel/item/comments
           /channel/item/wfw:comment
           /channel/item/wfw:commentRss
           /channel/item/slash:comments
           /channel/item/slash:hit_parade
           /channel/item/thr:total
           /channel/item/content  --atom
           /channel/item/wiki:diff
           /channel/item/itunes:duration

           /channel/wiki:interwiki
           /channel/wiki:interwiki/rdf:Description
           /channel/wiki:interwiki/rdf:Description/rdf:value
           /channel/item/wiki:version
           /channel/item/wiki:status
           /channel/item/wiki:history

           --believed-to-be-duplicate-of-description
           /channel/item/media:content
           /channel/item/media:text
        )} = ();

sub item_to_lat_long_alt_str {
  my ($self, $item) = @_;
  my ($lat, $long, $alt) = $self->item_to_lat_long_alt_values ($item)
    or return;
  ### $lat
  ### $long
  ### $alt

  if (Scalar::Util::looks_like_number($lat)) {
    $lat = ($lat >= 0
            # TRANSLATORS: the latin1/unicode degree symbol can be used
            # here instead of " deg"
            ? __x('{latitude} deg N', latitude => $lat)
            : __x('{latitude} deg S', latitude => -$lat));
  }
  if (Scalar::Util::looks_like_number($long)) {
    $long = ($long >= 0
             ? __x('{longitude} deg E', longitude => $long)
             : __x('{longitude} deg W', longitude => -$long));
  }

  if (is_non_empty ($alt)) {
    return __x('Geo location: {latitude}, {longitude}, alt {altitude}m',
               latitude  => $lat,
               longitude => $long,
               altitude  => $alt);
  } else {
    return __x('Geo location: {latitude}, {longitude}',
               latitude  => $lat,
               longitude => $long);
  }
}

sub item_to_lat_long_alt_values {
  my ($self, $item) = @_;

  # per-item <geo:lat>, <geo:long> eg. USGS earthquakes
  # http://earthquake.usgs.gov/eqcenter/recenteqsww/catalogs/eqs7day-M5.xml
  # <item>
  #   <geo:lat>11</geo:lat>
  #   <geo:long>22</geo:long>
  #
  # or under geo:Point, maybe, eg. http://www.gdacs.org/xml/RSSTC.xml
  # <item>
  #   <geo:Point>
  #     <geo:lat>11</geo:lat>
  #     <geo:long>22</geo:long>
  #
  foreach my $elt ($item, $item->children(qr/^geo:point$/i)) {
    my $lat = $elt->first_child_trimmed_text('geo:lat');
    if (is_non_empty ($lat)) {
      return ($lat,
              $elt->first_child_trimmed_text('geo:long'),
              non_empty ($elt->first_child_trimmed_text('geo:alt')));
    }
  }

  # <item>
  #   <georss:point>46.183 -123.816</georss:point>
  # space separator per http://www.georss.org/Encodings
  {
    my $str = $item->first_child_trimmed_text ('georss:point');
    if (is_non_empty ($str)) {
      return split(/\s+/, $str, 2); # no altitude
    }
  }

  return; # not found
}
@known{qw(/channel/item/geo:lat
          /channel/item/geo:long
          /channel/item/geo:alt
          /channel/item/geo:Point
          /channel/item/geo:Point/geo:lat
          /channel/item/geo:Point/geo:long
          /channel/item/georss:point
        )} = ();


sub links_to_html {
  @_ or return '';

  # <nobr> on link lines to try to prevent the displayed URL being chopped
  # up by a line-wrap, which can make it hard to cut and paste.  <pre> can
  # prevent a line wrap, but it ends up treated as starting a paragraph,
  # separate from the 'name' part.
  #
  my $str = '';
  my $sep = "\n\n<p>\n";
  foreach my $l (@_) {
    $str .= "$sep<nobr>$Entitize{$l->{'name'}}";
    $sep = "<br>\n";

    if (defined (my $uri = $l->{'uri'})) {
      $str .= "&nbsp;<a";
      if (defined (my $hreflang = $l->{'hreflang'})) {
        $str .= " hreflang=\"$Entitize{$hreflang}\"";
      }
      if (defined (my $type = $l->{'type'})) {
        $str .= " type=\"$Entitize{$type}\"";
      }
      $uri = $Entitize{$uri};
      $str .= " href=\"$uri\">$uri</a>";
    }
    $str .= "</nobr>\n";
  }
  return "$str</p>\n";
}

sub links_to_text {
  return join ('', map { join_non_empty (' ',
                                         $_->{'name'},
                                         $_->{'uri'}) . "\n" } @_);
}


#------------------------------------------------------------------------------
# "From:" and email addresses

use constant DUMMY_EMAIL_ADDRESS => 'nobody@rss2leafnode.dummy';

{
  my %tag_to_link_name
  = (author         => __('Author:'),
     creator        => __('Creator:'),
     contributor    => __('Contributor:'),
     managingEditor => __('Managing Editor:'),
     webMaster      => __('Webmaster:'),
     publisher      => __('Publisher:'),
     owner          => __('Owner:'),
     username       => __('User:'),
    );

  # return ($from, $linkhash)
  sub item_to_from {
    my ($self, $item) = @_;
    my $channel = item_to_channel($item);

    # <author> is supposed to be an email address whereas <dc:creator> is
    # looser.  The RSS recommendation is to use author when revealing an email
    # and dc:creator when hiding it.
    #
    # <dc:contributor> appears in wiki: feeds as the item's author.
    #
    # <contributor> can appear multiple times in Atom item.  Could show them
    # as multiple addresses in From:, but for now prefer just one primary
    # author.
    #
    my $elt;
    my $from =
      ($self->elt_to_email    ($elt = $item->first_child('author'))
       // $self->elt_to_email ($elt = $item->first_child('dc:creator'))
       // $self->elt_to_email ($elt = $item->first_child('dc:contributor'))
       // $self->elt_to_email ($elt = $item->first_child('wiki:username'))
       // $self->elt_to_email ($elt = $item->first_child('itunes:author'))

       // $self->elt_to_email ($elt = $channel->first_child('author'))
       // $self->elt_to_email ($elt = $channel->first_child('dc:creator'))
       // $self->elt_to_email ($elt = $channel->first_child('itunes:author'))
       // $self->elt_to_email ($elt = $channel->first_child('managingEditor'))
       // $self->elt_to_email ($elt = $channel->first_child('webMaster'))

       // $self->elt_to_email ($elt = $item   ->first_child('dc:publisher'))
       // $self->elt_to_email ($elt = $channel->first_child('dc:publisher'))
       // $self->elt_to_email ($elt = $channel->first_child('itunes:owner'))
       // do { undef $elt }

       # Atom <title> can have type="html" etc in the usual way, so render.
       # Hope the channel title is different from the item title.
       // $self->email_format (elt_to_rendered_line
                               ($channel->first_child('title')))

       // ('nobody@'.$self->uri_to_host)
      );
    my $link;
    if ($elt && (my $uri =
                 (# Atom
                  # <author>
                  #   <name>Foo Bar</name>
                  #   <uri>http://some.where</uri>
                  # </author>
                  #
                  non_empty ($elt->first_child_text('uri'))

                  # ModWiki dc:contributor example
                  #     <rdf:Description link="http://openwiki.com/?FooBar">
                  #       <rdf:value>Foo Bar</rdf:value>
                  #     </rdf:Description>
                  # The text shows rss:link= and the example just link=.
                  #
                  // non_empty (do {
                    my $child; ($child = $elt->first_child('rdf:Description'))
                      && ($child->att('link') // $child->att('rss:link'))
                    })))) {
      (my $tag = $elt->tag) =~ s/.*?://;
      $link = { uri      => URI->new($uri),
                name     => ($tag_to_link_name{$tag} // "\u$tag:"),
                download => 0 };
    }
    return ($from, $link);
  }
  @known{qw(/channel/author
            /channel/author/name   --atom
            /channel/author/uri    --atom
            /channel/author/url    --atom-typo-maybe
            /channel/author/email  --atom
            /channel/managingEditor
            /channel/webMaster
            /channel/dc:publisher
            /channel/dc:creator
            /channel/itunes:author

            /channel/item/author
            /channel/item/author/name   --atom
            /channel/item/author/uri    --atom
            /channel/item/author/url    --atom-typo-maybe
            /channel/item/author/email  --atom
            /channel/item/author/gd:extendedProperty  --good-dinner
            /channel/item/dc:creator
            /channel/item/dc:publisher
            /channel/item/wiki:username
            /channel/item/itunes:author
            /channel/item/dc:contributor
            /channel/item/dc:contributor/rdf:Description
            /channel/item/dc:contributor/rdf:Description/rdf:value

            /channel/item/contributor        --atom
            /channel/item/contributor/name
            /channel/item/contributor/uri
            /channel/item/contributor/url    --atom-typo-maybe
            /channel/item/contributor/email
          )} = ();
}

# $elt is an XML::Twig::Elt
# return an email address, either just the text part of $elt or Atom
# sub-elements <name> and <email>
#
sub elt_to_email {
  my ($self, $elt) = @_;
  return unless defined $elt;

  # <email> - under Atom
  # <itunes:email> - under <itunes:owner>
  my $email = elt_to_rendered_line ($elt->first_child(qr/^(itunes:)?email$/));

  # <name> - under Atom
  # <itunes:name> - under <itunes:owner>
  my $display = elt_to_rendered_line ($elt->first_child(qr/^(itunes:)?name$/))
    // '';

  my $maybe = join
    (' ',
     non_empty ($elt->text_only),
     non_empty (do {
       # <rdf:Description><rdf:value>...</></> under dc authors etc
       my $rdfdesc; ($rdfdesc = $elt->first_child('rdf:Description'))
         && $rdfdesc->first_child_text('rdf:value')
       }));

  return $self->email_format_maybe ($maybe, $display, $email);
}

# $mailbox_re is a mailbox with domain, like "foo@bar.com"
# no dots like "foo@localhost" is allowed
#
# $mailbox_with_comment_re allows an optional paren comment part like
# "foo@bar.com (Foo)"
#
# cf Email::Address $addr_spec, but its version 1.890 loosened to allow a
# domain-less bare "foo", which is no good
#
my $words_with_dots_re = qr/\w+(\.\w+)*/;
my $mailbox_re = qr/$words_with_dots_re\@$words_with_dots_re/o;
my $mailbox_with_comment_re = qr/$mailbox_re(\s*\([^\)]*\))?/os;

# $maybe is some free-form author part possibly including a foo@bar.com
# $display is a display part for the email like "Foo", possibly empty ""
# $email is a mailbox "foo@bar.com", or undef
# return an rfc822 "Foo <foo@bar.com>"
#
sub email_format_maybe {
  my ($self, $maybe, $display, $email) = @_;
  ### email_format_maybe() start
  ### $maybe
  ### $display
  ### $email

  # look also at $display the same in case Atom no <email> but a <name>
  # which is a mailbox and can be corrected,
  # eg. http://www.weather.gov/alerts-beta/hi.php?x=0
  #
  # Or $maybe full email like
  if (is_empty($email)) {
    foreach ($maybe, $display) {

      if (/^\s*(mailto:)?($mailbox_with_comment_re)\s*$/o) {
        ### maybe or display is a mailbox
        #     "foo@bar.com"
        #     "mailto:foo@bar.com"
        #     "foo@bar.com (Foo)"
        $email = $2;
        undef $_;
        last;

      } elsif (/(.*)\((mailto:)?($mailbox_re)\)\s*$/o
               || /(.*)<(mailto:)?($mailbox_re)>\s*$/o) {
        ### maybe or display part is display plus mailbox
        #     "Foo (mailto:foo@bar.com)"
        #     "Foo (foo@bar.com)"
        #     "Foo <foo@bar.com>"
        #
        $_ = $1;
        $email = $3;
        last;
      }
    }
  }

  $display .= ' '.($maybe//'');
  my $ret;
  if (is_empty($email) && $display =~ /^$mailbox_re$/o) {
    # display or maybe is a "foo@bar.com" or "foo@bar.com (Foo)", return it
    # as-is, in particular leave it in "(Foo)" style comment
    $ret = $display;
  } else {
    $ret = $self->email_format ($display, $email);
  }

  # Collapse whitespace against possible tabs and newlines in an <author> as
  # from googlegroups for instance.  MIME::Entity seems to collapse
  # newlines, but not tabs.
  return non_empty (collapse_whitespace ($ret));
}

# $display is a display part for the email "Foo", possibly empty ""
# $email is a mailbox "foo@bar.com", or undef or empty ""
# return an rfc822 "Foo <foo@bar.com>"
#
sub email_format {
  my ($self, $display, $email) = @_;
  ### $display
  $display = Text::Trim::trim($display);
  $email   = Text::Trim::trim($email);
  if (is_empty($display)) {
    if (is_empty($email)) {
      return;
    } else {
      return $email;
    }
  }
  if (is_empty($email)) {
    # think can't have empty <> or omitted, otherwise the quoted part is
    # still parsed as an address, certainly it's not rfc822 compliant to
    # omit
    $email = $self->DUMMY_EMAIL_ADDRESS;
  } else {
    $email = $email;
  }
  return email_phrase_quote_maybe($display) . " <$email>";
}

# return $str with quotes like "Foo Bar" if it needs them to go in an email
# display part
sub email_phrase_quote_maybe {
  my ($str) = @_;
  return if ! defined $str;

  # RFC2822 "atext" characters, with "-" last
  if ($str =~ q<[^[:alnum:][:space:]!#\$%&'*+/=?^_`{|}~-]>) {
    # strange chars, need to quote
    return email_phrase_quote($str);
  } else {
    # alphanumeric and whitespace, no quotes
    return $str;
  }
}
sub email_phrase_quote {
  my ($str) = @_;
  return if ! defined $str;
  $str =~ s/^"(.*)"$/$1/;   # strip existing quotes
  $str =~ s/(["\\])/\\$1/g; # escape internal quotes and backslashes
  return "\"$str\"";
}


#------------------------------------------------------------------------------
# fetch RSS

my $map_xmlns
  = {
     'http://purl.org/rss/1.0/'                     => 'rss',
     'http://www.w3.org/2005/Atom'                  => 'atom',
     'http://www.w3.org/1999/02/22-rdf-syntax-ns#'  => 'rdf',
     'http://purl.org/rss/1.0/modules/content/'     => 'content',
     'http://purl.org/rss/1.0/modules/slash/'       => 'slash',
     'http://purl.org/rss/1.0/modules/syndication/' => 'syn',
     'http://purl.org/syndication/thread/1.0'       => 'thr',
     'http://wellformedweb.org/CommentAPI/'         => 'wfw',
     'http://www.w3.org/1999/xhtml'                 => 'xhtml',
     'http://www.itunes.com/dtds/podcast-1.0.dtd'   => 'itunes',
     'http://rssnamespace.org/feedburner/ext/1.0'   => 'feedburner',
     'http://search.yahoo.com/mrss'                 => 'media',
     'http://backend.userland.com/creativeCommonsRssModule'=>'creativeCommons',
     'http://www.w3.org/2003/01/geo/wgs84_pos#'     => 'geo',
     'http://www.georss.org/georss'                 => 'georss',
     'http://www.pheedo.com/namespace/pheedo'       => 'pheedo',

     # Common Alerts Protocol
     'urn:oasis:names:tc:emergency:cap:1.1'         => 'cap',

     # central bank exchange rates format,
     # spec http://www.cbwiki.net/wiki/index.php/RSS-CBMain
     # eg. RBA http://www.rba.gov.au/rss/rss-cb-exchange-rates.xml
     'http://www.cbwiki.net/wiki/index.php/Specification_1.1' => 'cb',

     # earthquakes
     # eg. http://earthquake.usgs.gov/earthquakes/shakemap/rss.xml
     'http://earthquake.usgs.gov/rss/1.0/' => 'eq',

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
  my $twig = XML::Twig->new (map_xmlns => $map_xmlns,
                             pretty_print => 'wrapped');
  $twig->safe_parse ($xml);
  my $err = $@;

  # Try to fix bad non-ascii chars by putting it through Encode::from_to().
  # Encode::FB_DEFAULT substitutes U+FFFD when going to unicode, or question
  # mark "?" going to non-unicode.  Mozilla does some sort of similar
  # liberal byte interpretation so as to at least display something from a
  # dodgy feed.
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
      my $recoded_xml = $xml;
      Encode::from_to($recoded_xml, $charset, $charset, Encode::FB_DEFAULT());

      $twig = XML::Twig->new (map_xmlns => $map_xmlns);
      if ($twig->safe_parse ($recoded_xml)) {
        $twig->root->set_att('rss2leafnode:fixup',
                             "Recoded bad bytes to charset $charset");
        print __x("Feed {url}\n  recoded {charset} to parse, expect substitutions for bad non-ascii\n  ({where})\n",
                  url     => $self->{'uri'},
                  charset => $charset,
                  where   => $where);
        undef $err;
      }
    }
  }

  # Or attempt to put it through XML::Liberal, if available.
  #
  if ($err && eval { require XML::Liberal; 1 }) {
    my $liberal = XML::Liberal->new('LibXML');
    if (my $doc = eval { $liberal->parse_string($xml) }) {
      my $liberal_xml = $doc->toString;

      $twig = XML::Twig->new (map_xmlns => $map_xmlns);
      if ($twig->safe_parse ($liberal_xml)) {
        $err = Text::Trim::trim($err);
        $twig->root->set_att('rss2leafnode:fixup',
                             "XML::Liberal fixed: {error}",
                             error => $err);
        print __x("Feed {url}\n  parse error: {error}\n  continuing with repairs by XML::Liberal\n",
                  url   => $self->{'uri'},
                  error => $err);
        undef $err;
      }
    }
  }

  if ($err) {
    # XML::Parser seems to stick some spurious leading whitespace on the error
    $err = Text::Trim::trim($err);

    if ($self->{'verbose'} >= 1) {
      say __x("Parse error on URL {url}\n{error}",
              url   => $self->{'uri'},
              error => $err);
    }
    return (undef, $err);
  }

  # Strip any explicit "rss:" or "atom:" namespace down to bare part.
  # Should be unambiguous and is easier than giving tag names both with and
  # without the namespace.  Undocumented set_ns_as_default() might do this
  # ... or might not.
  #
  my $root = $twig->root;
  elt_tree_strip_prefix ($root, 'atom');
  elt_tree_strip_prefix ($root, 'rss');
  #
  # somehow map_xmlns mangles default attributes like "decimals=...", prefer
  # to see them without rss: or atom: -- maybe
  #   foreach my $child ($root->descendants_or_self) {
  #     foreach my $attname ($child->att_names) {
  #       if ($attname =~ /^(atom|rss):(.*)/) {
  #         $child->change_att_name($attname, $2);
  #       }
  #     }
  #   }

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
  if ($self->{'verbose'} >= 2) { say '  msgid from MD5'; }
  return $self->url_to_msgid
    ($self->{'uri'},
     md5_of_utf8 (join_non_empty ('',
                                  map {$item->first_child_text($_)}
                                  qw(title
                                     author
                                     dc:creator
                                     description
                                     content
                                     link
                                     pubDate
                                     published
                                     updated
                                   ))));
}
# FIXME: is <wordzilla:id> anything that can be used ?
@known{qw(/channel/item/guid
          /channel/item/id
          /channel/item/wordzilla:id)} = ();

# Return a Message-ID string (including angles <>) for $item, or empty list.
# This matches up to an Atom <id> element, dunno if it's much used.
# Supposedly there should be only one thr:in-reply-to, no equivalent to
# the "References" header giving all parents.
#
sub item_to_in_reply_to {
  my ($self, $item) = @_;
  my $inrep = $item->first_child('thr:in-reply-to') // return undef;
  my $ref = ($inrep->att('thr:ref')
             // $inrep->att('ref')
             // $inrep->att('atom:ref') # comes out atom: under map_xmlns ...
             // return undef);
  $ref = elt_xml_based_uri ($inrep, $ref); # probably shouldn't be relative ...
  return $self->url_to_msgid ($ref);
}
@known{qw(/channel/item/thr:in-reply-to
        )} = ();

# Return a string of comma separated keywords per RFC1036 and RFC2822.
  # <category> is often present with no other keywords, work that in as a
  # bit of a fallback, being better than nothing for classification.
  #
  # <itunes:category> might be covered by <itunes:keywords> anyway, but work
  # it in for more classification for now.  Can have child <itunes:category>
  # elements as sub-categories, but don't worry about them, haven't seen any
  # real ones, only the sample at
  # http://www.apple.com/itunes/podcasts/specs.html#example
  #
  # <slash:section> might in theory be turned into keyword, but it's
  # normally just "news" or something not particularly informative.
  #
  # <cap:category> is "Geo", "Met", "Safety", "Fire" etc.  Not sure if it
  # should be in the keywords if it's also in the body text, but at least
  # offers a bit of classification in the headers.
  #
  # <dc:subject> is supposed to be from a "restricted vocabulary" so might
  # want a bit of decoding.  Not much used, but for instance
  # http://www.gdacs.org/xml/RSSTC.xml
  # http://earthquake.usgs.gov/eqcenter/recenteqsww/catalogs/eqs7day-M5.xml
  #
  # How much value is there in the channel keywords?
  #
{
  my $re = qr/^(category
              |itunes:category
              |cap:category
              |itunes:keywords
              |media:keywords
              |dc:subject
              )$/x;
  sub item_to_keywords {
    my ($self, $item) = @_;

    my @item_children = ($re);
    my $channel = item_to_channel($item);

    return join_non_empty
      (', ',
       List::MoreUtils::uniq
       (map { collapse_whitespace($_) }
        map { split /,/ }
        map { $_->att('text')   # itunes:category
                // $_->text }   # other
        ($item->children($re),
         $channel->children($re),
         # <cb:news> etc sub-element <cb:category>
         map {$_->children('cb:keyword')} $item->children,
        )));
  }
  @known{qw(/channel/category
            /channel/itunes:category
            /channel/itunes:category/itunes:category

            /channel/item/category
            /channel/item/itunes:keywords
            /channel/item/media:keywords
            /channel/item/slash:section)} = ();
}

{
  # Feturn a string for the "Importance:" header of RFC 1911, RFC 2156
  # voice and X.400 messaging.  Possible values 'high', 'normal', 'low'.
  # 'normal' is the header default, return undef in that case in the
  # interests of not junking up headers with defaults
  #
  my %cap_severity_high   = (extreme => 1,
                             severe => 1);
  my %cap_severity_normal = (moderate => 1);
  my %cap_severity_low    = (minor => 1);

  sub item_to_importance {
    my ($self, $item) = @_;

    my $cap_severity = lc($item->first_child_trimmed_text('cap:severity')
                          // '');
    my $wiki_importance = ($item->first_child_trimmed_text('wiki:importance')
                           // '');
    if ($self->{'verbose'} >= 2) {
      if ($cap_severity) {
        print "  CAP severity:    $cap_severity\n";
        print "  Wiki importance: $wiki_importance\n";
      }
    }

    if ($cap_severity_high{$cap_severity}) {
      return 'high';
    }
    if ($cap_severity_normal{$cap_severity}) {
      return undef; # default "normal"
    }
    if ($cap_severity_low{$cap_severity}
        || $wiki_importance eq 'minor') {
      return 'low';
    }
    return undef; # unknown
  }
  @known{qw(/channel/item/wiki:importance
          )} = ();
}
{
  # Return a string for the "Priority:" header of RFC 1327, RFC 2156.
  # Possible values 'urgent', 'normal', 'non-urgent'.
  # 'normal' is the header default, return undef in that case in the
  # interests of not junking up headers with defaults
  #
  # <cap:urgency> is "Immediate", "Expected", "Future", "Past", "Unknown",
  # for when response action should be taken.  Is the <cap:severity> the
  # better indicator of transmission priority?
  #
  my %cap_severity_urgent = (extreme => 1,
                             severe  => 1);
  my %cap_severity_normal = (moderate => 1);

  sub item_to_priority {
    my ($self, $item) = @_;

    my $cap_severity = lc($item->first_child_trimmed_text('cap:severity')
                          // '');

    if ($cap_severity_urgent{$cap_severity}) {
      return 'urgent';
    }
    if ($cap_severity_normal{$cap_severity}) {
      return undef; # default "normal"
    }
    if (0) { # nothing for this yet
      return 'non-urgent';
    }
    return undef; # unknown
  }
}

# return a string for the slightly unofficial "Precedence:" header
# might be able to identify lists gatewayed to RSS and give "list" for them
# maybe "bulk" would suit low priority stuff
# for now nothing
#
# sub item_to_precedence {
#   my ($self, $item) = @_;
#   return undef; # nothing
# }

# return the host part of $self->{'uri'}, or "localhost" if none
sub uri_to_host {
  my ($self) = @_;
  my $uri = $self->{'uri'};
  ### uri_to_host(): $uri
  return (non_empty ($uri && $uri->can('host') && $uri->host)
          // 'localhost');
}

sub item_to_subject {
  my ($self, $item) = @_;

  # Atom <title> can have type="html" etc in the usual way.
  return
    (elt_to_rendered_line    ($item->first_child('title'))
     # dc:subject is supposed to be a keyword type thing, but might be
     # better than nothing
     // elt_to_rendered_line ($item->first_child('dc:subject'))
     // __('no subject'));
}
@known{qw(/channel/title
          /channel/dc:subject
          /channel/subtitle
          /channel/itunes:subtitle

          /channel/item/dc:subject
          /channel/item/title
          /channel/item/itunes:title
          /channel/item/itunes:subtitle  --not-using-this-as-yet
        )} = ();


# return language code string for Content-Language, or undef
# return is per RFC 1766, RFC 3066, RFC 4646
#
# xml:lang is defined to be per RFC 4646, no mangling needed
# RSS <language> seems close enough http://www.rssboard.org/rss-language-codes
# <dc:language> is recommended as RFC 4646
# cf. I18N::LangTags if mangling might be needed one day
#
sub item_to_language {
  my ($self, $item) = @_;
  my $lang;

  if (my $elt = $item->first_child('content')) {
    $lang = non_empty ($elt->att('xml:lang'));
  }
  # Either <language> / <dc:language> sub-element or xml:lang="" tag, in the
  # item itself or in channel, and maybe xml:lang in toplevel <feed>.
  # $elt->inherit_att() is close, but looks only at xml:lang, not a
  # <language> subelement.
  for ( ; $item; $item = $item->parent) {
    $lang //= (non_empty    ($item->first_child_trimmed_text
                             (qr/^(dc:)?language$/))
               // non_empty ($item->att('xml:lang'))
               // next);
  }
  return ($lang // $self->{'resp'}->content_language);
}
@known{qw(/channel/language
          /channel/dc:language
          /channel/item/language
          /channel/item/dc:language
        )} = ();

# return arrayref of copyright strings
# Keep all of multiple rights/license/etc in the interests of preserving all
# statements.
sub item_to_copyright {
  my ($self, $item) = @_;
  my $channel = item_to_channel($item);

  # <dcterms:license> supposedly supercedes <dc:rights>, maybe should
  # suppress the latter in the presence of the former (dcterms: collapsed to
  # dc: by the map_xmlns).
  #
  # Atom <rights> can be type="html" etc in its usual way, but think RSS is
  # always plain text
  #
  my $re = qr/^(rights     # Atom
              |copyright   # RSS, don't think entity-encoded html allowed there
              |dc:license
              |dc:rights
              |creativeCommons:license
              )$/x;
  return [ List::MoreUtils::uniq
           (map { non_empty(elt_to_rendered_line($_)) }
            ($item->children ($re),
             # Atom sub-elem <source><rights>...</rights> when from another feed
             (map {$_->children($re)} $item->children('source')),
             $channel->children ($re))) ];
}
@known{qw(/channel/copyright
          /channel/rights
          /channel/dc:rights
          /channel/dc:license
          /channel/creativeCommons:license
          /channel/item/dc:rights
          /channel/item/dc:license
          /channel/item/creativeCommons:license)} = ();
# /channel/item/media:credit   --nothing-much-in-this-one


# return copyright string or undef
sub item_to_generator {
  my ($self, $item) = @_;
  my $channel = item_to_channel($item);

  # both RSS and Atom use <generator>
  # Atom can include version="" and uri=""
  my $generator = $channel->first_child('generator') // return undef;
  return collapse_whitespace (join_non_empty (' ',
                                              $generator->text,
                                              $generator->att('atom:version'),
                                              $generator->att('version'),
                                              $generator->att('atom:uri'),
                                              $generator->att('uri')));
}

# return URL string or undef/empty
sub item_to_feedburner {
  my ($self, $item) = @_;
  my $channel = item_to_channel($item);
  my $elt = $channel->first_child('feedburner:info') || return;
  my $uri = $elt->att('uri') // return;
  return URI->new_abs ($uri, 'http://feeds.feedburner.com/')->as_string;
}

# $elt is an Atom <content>
sub atom_content_flavour {
  my ($elt) = @_;
  if (! defined $elt) { return ''; }
  my $type = ($elt->att('atom:type') // $elt->att('type'));
  if ($elt->att('atom:src') || $elt->att('src')) {
    # <content src=""> external
    return 'link';
  }
  if (! defined $type
      || $type ~~ ['html','xhtml','application/xhtml+xml']
      || $type =~ m{^text/}) {
    return 'body';
  }
  return 'attach';
}

sub html_wrap_fragment {
  my ($item, $fragment) = @_;
  my $charset = (is_ascii($fragment) ? 'us-ascii' : 'utf-8');
  my $base_uri = elt_xml_base($item);
  my $base_header = (defined $base_uri
                     ? "  <base href=\"$Entitize{$base_uri}\">\n"
                     : '');
  return (<<"HERE", $charset);
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<html>
<head>
  <meta http-equiv=Content-Type content="text/html; charset=$charset">
$base_header</head>
<body>
$fragment
</body></html>
HERE
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
        say "replace encoding=$2 tag with encoding=$charset";
      }
    } elsif ($xml =~ s/(<\?xml[^?>]*)/$1 encoding="$charset"/i) {
      if ($self->{'verbose'} >= 2) {
        say "insert encoding=\"$charset\"";
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

# slightly experimental extract of "cap" fields as from
# http://www.nws.noaa.gov/alerts-beta/
# http://www.weather.gov/alerts-beta/ca.php?x=0
sub item_common_alert_protocol {
  my ($self, $item, $want_html) = @_;
  my @fields;
  foreach my $elt ($item->children(qr/^cap:/)) {
    (my $field = $elt->name) =~ s/^cap://;
    if ($field eq 'geocode' || $field eq 'parameter') {
      # dunno how to show these yet ...
      next;
    }
    $known{'/channel/item/'.$elt->name} = undef;

    my $value = elt_to_rendered_line ($elt);
    $value = Text::Trim::trim ($value);
    if (is_non_empty ($value)) {
      push @fields, [ "\u$field: ", $value ];
    }
  }
  if (! @fields) {
    return '';
  }
  # FIXME: This $width padding doesn't come out in html, only in text.  The
  # NOAA is Atom plain text, so that one is ok at least.
  my $width = max(map {length $_->[0]} @fields);
  @fields = map { my $field = $_->[0];
                  my $value = $_->[1];
                  $field = sprintf ('%-*s', $width, $field);
                  $self->text_wrap ($value, $field)
                } @fields;
  if ($want_html) {
    return "<p>\n"
      . join("<br>\n", map {$Entitize{$_}} @fields)
        . "\n</p>\n";
  } else {
    return "\n"
      . join("\n",  @fields)
        . "\n";
  }
}

sub item_unknowns {
  my ($self, $item, $want_html) = @_;

  my $xml = '';
  foreach my $elt ($item->children) {
    next if $elt->tag =~ /^#/;  # text
    my $path = $elt->path;
    $path =~ s{^/(rss|channel)/channel}{/channel};
    $path =~ s{^/(feed|rdf:RDF)}{/channel};
    $path =~ s{^/channel/entry}{/channel/item};
    next if $path =~ m{/xhtml};
    next if $path =~ m{^/channel/item/(description|content:encoded)/};
    next if exists $known{$path};

    my $part = do {
      require Text::Wrap;
      local $Text::Wrap::columns = $self->{'render_width'} + 1 + 4;
      local $Text::Wrap::unexpand = 0;  # no tabs in output
      $elt->sprint
    };
    $part =~ s/^    //mg; # indentation from element depth
    $part =~ s/^\n+//;    # leading blank lines
    $xml .= $part;
  }
  if ($xml eq '') {
    return '';
  }
  ### $xml

  if ($want_html) {
    return "\n<p>\n" . __('Further XML fields:') . "<br>\n"
        . "<pre>$Entitize{$xml}</pre>\n</p>\n";
  } else {
    return "\n" . __('Further XML fields:') . "\n" . $xml;
  }
}

# $body construction below
@known{qw(/channel/item/description
           /channel/item/dc:description
           /channel/item/itunes:summary
           /channel/item/content:encoded
           /channel/item/summary
        )} = ();

# $item is an XML::Twig::Elt
#
sub fetch_rss_process_one_item {
  my ($self, $item) = @_;
  my $subject = $self->item_to_subject ($item);
  if ($self->{'verbose'} >= 1) {
    say __x(' item: {subject}',
            subject => $subject);
  }
  my $msgid = $self->item_to_msgid ($item);
  return 0 if $self->nntp_message_id_exists ($msgid);

  my $channel = item_to_channel($item);
  my ($from, $from_link) = $self->item_to_from($item);
  my @links = $self->item_to_links ($item);
  if ($from_link) {
    push @links, $from_link;
  }

  my $list_post = googlegroups_link_email(@links);
  my $precedence = (defined $list_post ? 'list' : undef);

  # RSS <rating> PICS-Label
  # http://www.w3.org/TR/REC-PICS-labels
  # ENHANCE-ME: Maybe transform <itunes:explicit> "yes","no","clean" into
  # PICS too maybe, unless it only applies to the enclosure as such.  Maybe
  # <media:adult> likewise.
  my $pics_label = collapse_whitespace ($channel->first_child_text('rating'));

  # Crib: an undef value for a header means omit that header, which is good
  # for say the merely optional "Content-Language"
  #
  # there can be multiple "feed" links from Atom ...
  # 'X-RSS-Feed-Link:'  => $channel->{'link'},
  #
  my %headers
    = ('Path:'        => scalar ($self->uri_to_host),
       'Newsgroups:'  => $self->{'nntp_group'},
       From           => $from,
       Subject        => $subject,
       Keywords       => scalar ($self->item_to_keywords($item)),
       Date           => scalar ($self->item_to_date($item)),
       'In-Reply-To:'      => scalar ($self->item_to_in_reply_to($item)),
       'Message-ID'        => $msgid,
       'Content-Language:' => scalar ($self->item_to_language($item)),
       'Importance:'       => scalar ($self->item_to_importance($item)),
       'Priority:'         => scalar ($self->item_to_priority($item)),
       'Face:'             => scalar ($self->item_to_face($item)),
       'List-Post:'        => $list_post,
       'Precedence:'       => $list_post,
       'PICS-Label:'       => $pics_label,
       'X-Copyright:'      => scalar ($self->item_to_copyright($item)),
       'X-RSS-URL:'        => scalar ($self->{'uri'}->as_string),
       'X-RSS-Feedburner:' => scalar ($self->item_to_feedburner($item)),
       'X-RSS-Generator:'  => scalar ($self->item_to_generator($item)),
      );

  my $attach_elt;

  # <media:text> is another possibility, but have seen it from Yahoo as just
  # a copy of <description>, with type="html" to make the format clear.
  #
  # ENHANCE-ME: <itunes:subtitle> might be worthwhile showing at the start
  # as well as <itunes:summary>.
  #
  my $body = (           # <content:encoded> generally bigger or better than
              # <description>, so prefer that
              $item->first_child('content:encoded')
              || $item->first_child('description')
              || $item->first_child('dc:description')
              || $item->first_child('itunes:summary')
              || do {
                # Atom spec is for no more than one <content>.
                my $elt = $item->first_child('content');
                given (atom_content_flavour($elt)) {
                  when ('link')   { undef $elt }
                  when ('attach') { $attach_elt = $elt; undef $elt; }
                }
                $elt
              }
              || $item->first_child('summary')); # Atom

  my $body_type = elt_content_type ($body);
  if ($self->{'verbose'} >= 3) { print " body_type from elt: $body_type\n"; }
  my $body_charset = 'utf-8';
  my $body_base_url = elt_xml_base ($body);
  given ($body_type) {
    when (! defined) {          # no $body element at all
      $body = '';
      $body_type = 'text/plain';
    }
    when ('xhtml') {            # Atom
      $body = elt_xhtml_to_html ($body);
      $body_type = 'html';
    }
    when ('html') {             # RSS or Atom
      $body = elt_subtext($body);
    }
    when ('text') {             # Atom 'text' to be flowed
      # should be text-only, no sub-elements, but extract sub-elements to
      # cope with dodgy feeds with improperly escaped html etc
      $body = $self->text_wrap (elt_subtext ($body));
      $body_type = 'text/plain';
    }
    when (m{^text/}) {          # Atom mime text type
      $body = elt_subtext ($body);
    }
    default {                   # Atom base64 something
      $body = MIME::Base64::decode ($body->text);
      $body_charset = undef;
    }
  }
  if ($self->{'verbose'} >= 3) { print " body: $body_type charset=",
                                   $body_charset//'undef',"\n",
                                     "$body\n"; }

  my $body_is_html = ($body_type ~~ ['html','text/html']);
  my $links_want_html = ($body_is_html && ! $self->{'render'});
  if ($self->{'verbose'} >= 3) { print " links_want_html: ",
                                   ($links_want_html ? "yes\n" : "no\n"); }
  my $links_str = ($links_want_html
                   ? links_to_html(@links)
                   : links_to_text(@links));
  $links_str .= $self->item_common_alert_protocol($item, $links_want_html);
  $links_str .= $self->item_unknowns($item, $links_want_html);
  my @parts;

  if ($self->{'rss_get_links'}) {
    foreach my $l (@links) {
      next if ! $l->{'download'};
      my $url = $l->{'uri'};
      if ($self->{'verbose'}) { say __x('  link: "{name}" {url}',
                                        name => $l->{'name'},
                                        url => $url); }
      require HTTP::Request;
      my $req = HTTP::Request->new (GET => $url);
      my $resp = $self->ua->request($req);
      $resp = $self->aireview_follow ($url, $resp);

      if (! $resp->is_success) {
        print __x("rss2leafnode: {url}\n {status}\n",
                  url => $l->{'uri'},
                  status => $resp->status_line);
        my $msg = __x("Cannot download link {url}\n {status}",
                      url => $l->{'uri'},
                      status => $resp->status_line);
        if ($links_want_html) {
          $msg = $Entitize{$msg};
          $msg =~ s/\n/<br>/;
          $links_str .= "<p>&nbsp;$msg\n</p>\n";
        } else {
          $links_str .= "\n$msg\n";
        }
        next;
      }

      # suspect little value in a description when inlined
      # 'Content-Description:' => mimewords_non_ascii($l->{'title'})
      # favicon used for Face if nothing in the item
      #
      $self->enforce_html_charset_from_content ($resp);
      $headers{'Face:'} ||= $self->http_resp_to_face($resp);
      push @parts, $self->mime_part_from_response ($resp);
    }
  }
  if ($links_want_html && $body_type eq 'html') {
    # append to html fragment
    $body .= $links_str;
    undef $links_str;
  }

  if ($body_type eq 'html') {
    ($body, $body_charset) = html_wrap_fragment ($item, $body);
    $body_type = 'text/html';
  }
  if (defined $body_charset) {
    $body = Encode::encode ($body_charset, $body);
  }

  ($body, $body_type, $body_charset)
    = $self->render_maybe ($body, $body_type, $body_charset, $body_base_url);

  if ($body_type eq 'text/plain') {
    # remove trailing whitespace from any text
    $body =~ s/\s+$//;
    $body .= "\n";

    if (! $links_want_html) {
      # append to text/plain, either atom type=text or rendered html
      unless (is_empty ($links_str)) {
        $links_str = Encode::encode ($body_charset, $links_str);
        $body .= "\n$links_str\n";
      }
      undef $links_str;
    }
  }

  unless (is_empty ($links_str)) {
    my $links_type;
    my $links_charset;
    if ($links_want_html) {
      $links_type = 'text/html';
      ($links_str, $links_charset) = html_wrap_fragment ($item, $links_str);
    } else {
      $links_type = 'text/plain';
      $links_charset = (is_ascii($links_str) ? 'us-ascii' : 'utf-8');
    }
    $links_str = Encode::encode ($links_charset, $links_str);
    unshift @parts, $self->mime_build ({},
                                       Type        => $links_type,
                                       Encoding    => $links_charset,
                                       Data        => $links_str);
  }


  my $top = $self->mime_build (\%headers,
                               Top     => 1,
                               Type    => $body_type,
                               Charset => $body_charset,
                               Data    => $body);

  # Atom <content> of a non-text type
  if ($attach_elt) {
    # ENHANCE-ME: this decodes base64 from the xml and then re-encodes for
    # the mime, is it possible to pass straight in?
    unshift @parts, $self->mime_build
      ({ 'Content-Location:' => $self->{'uri'}->as_string },
       Type     => scalar ($attach_elt->att('atom:type')
                           // $attach_elt->att('type')),
       Encoding => 'base64',
       Data     => MIME::Base64::decode($attach_elt->text));
  }
  foreach my $part (@parts) {
    $top->make_multipart;
    $top->add_part ($part);
  }

  mime_entity_lines($top);
  $self->nntp_post($top) || return 0;
  if ($self->{'verbose'} >= 1) { say __('   posted'); }
  return 1;
}

# $group is a string, the name of a local newsgroup
# $url is a string, an RSS feed to be read
#
sub fetch_rss {
  my ($self, $group, $url) = @_;
  if ($self->{'verbose'} >= 2) { say "fetch_rss: $group $url"; }

  my $group_uri = URI->new($group,'news');
  local $self->{'nntp_host'} = uri_to_nntp_host ($group_uri);
  local $self->{'nntp_group'} = $group = $group_uri->group;
  $self->nntp_group_check($group) or return;

  # an in-memory cookie jar, used only per-RSS feed and then discarded,
  # which means only kept for fetching for $self->{'rss_get_links'} from a
  # feed
  $self->ua->cookie_jar({});

  if ($self->{'verbose'} >= 1) { say __x('feed: {url}', url => $url); }
  require HTTP::Request;
  my $req = HTTP::Request->new (GET => $url);
  $self->status_etagmod_req($req,1) || return;

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

  $resp->decode;
  my $xml = $resp->content; # raw bytes
  $xml = $self->enforce_rss_charset_override ($xml);

  my ($twig, $err) = $self->twig_parse($xml);
  if (defined $err) {
    my $message = __x("XML::Twig parse error on\n\n  {url}\n\n",
                      url => $url);
    if ($resp->request->uri ne $url) {
      $message .= __x("which redirected to\n\n  {url}\n\n",
                      url => $resp->request->uri);
    }
    $message .= $err . "\n\n" . __("Raw XML below.\n") . "\n";
    $self->error_message
      (__x("Error parsing {url}", url => $url),
       $message, $xml);
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

  if (my $n = $self->{'rss_newest_only'}) {
    # secret feature newest N many items ...
    require Scalar::Util;
    unless (Scalar::Util::looks_like_number($n)) { $n = 1; }
    require Sort::Key::Top;
    @items = Sort::Key::Top::rkeytop (sub { $self->item_to_timet($_) },
                                      $n, @items);
  }

  my $new = 0;
  foreach my $item (@items) {
    $new += $self->fetch_rss_process_one_item ($item);
  }

  if ($self->{'verbose'} >= 2) {
    my $str = $self->ua->cookie_jar->as_string;
    if ($str eq '') {
      say 'no cookies from this feed';
    } else {
      print "accumulated cookies from this feed:\n$str";
    }
  }
  $self->ua->cookie_jar (undef);

  $self->status_etagmod_resp ($url, $resp, $twig);
  say __xn('{group}: {count} new article',
           '{group}: {count} new articles',
           $new,
           group => $group,
           count => $new);
}

1;
__END__

=for stopwords rss2leafnode RSS Leafnode config Ryde

=head1 NAME

App::RSS2Leafnode -- post RSS or Atom feeds and web pages to newsgroups

=head1 SYNOPSIS

 use App::RSS2Leafnode;
 my $r2l = App::RSS2Leafnode->new;
 exit $r2l->command_line;

=head1 DESCRIPTION

This is the guts of the C<rss2leafnode> program, see L<rss2leafnode> for
user-level operation.

=head1 FUNCTIONS

=over 4

=item C<< $exitcode = App::RSS2Leafnode->command_line () >>

=item C<< $exitcode = $r2l->command_line () >>

Run the C<rss2leafnode> program command line.  Arguments are taken from
C<@ARGV> and the return value is an exit code suitable for C<exit>.

=item C<< $r2l = App::RSS2Leafnode->new (key=>value,...) >>

Create and return a new RSS2Leafnode object.  Optional keyword parameters
are the config variables, plus C<verbose>

    verbose                   => integer
    render                    => flag or name
    render_width              => integer
    rss_get_links             => flag
    rss_newest_only           => integer
    rss_charset_override      => flag
    html_charset_from_content => flag

=item C<< $r2l->fetch_rss ($newsgroup, $url) >>

=item C<< $r2l->fetch_html ($newsgroup, $url) >>

Fetch an RSS feed or HTTP web page and post articles to C<$newsgroup>.  This
is the C<fetch_rss> and C<fetch_html> operations for
F<~/.rss2leafnode.conf>.

C<fetch_html> can in fact fetch any target type, not just HTML.
C<fetch_html> on an RSS feed would drop the whole XML into a news message,
whereas C<fetch_rss> turns it into a message per item.

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
