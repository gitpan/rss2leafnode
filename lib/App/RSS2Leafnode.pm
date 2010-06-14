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
use List::Util;
use List::MoreUtils;
use POSIX (); # ENOENT, etc
use URI;
use HTML::Entities::Interpolate;

our $VERSION = 28;

# version 1.17 for __p(), and version 1.16 for turn_utf_8_on()
use Locale::TextDomain 1.17;
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
#   RFC 1327 -- X.400 to RFC822 introducing Language header
#   RFC 2557 -- MHTML Content-Location
#   RFC 1864 -- Content-MD5 header
#   RFC 3282 -- Content-Language header
#   RFC 2369 -- List-Post header and friends
#   http://www3.ietf.org/proceedings/98dec/I-D/draft-ietf-drums-mail-followup-to-00.txt
#       Draft "Mail-Followup-To" header.
#
# RFC 977 -- NNTP
# RFC 4642 -- NNTP with SSL
# RFC 2616 -- HTTP/1.1 Accept-Encoding header
#
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

sub trim_whitespace {
  my ($str) = @_;
  defined $str or return undef;
  $str =~ s/^\s+//; # leading whitespace
  $str =~ s/\s+$//; # trailing whitespace
  return $str;
}

sub collapse_whitespace {
  my ($str) = @_;
  defined $str or return undef;
  $str =~ s/(\s+)/($1 eq '  ' ? $1 : ' ')/ge;
  return trim_whitespace($str);
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
    $ua->add_handler (request_send => \&lwp_request_send__verbose);
    $ua->add_handler (response_done => \&lwp_response_done__check_md5);

    # ask for everything decoded_content() can cope with, in particular "gzip"
    # and "deflate" compression if Compress::Zlib or whatever is available
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
  my ($resp, $ua, $h) = @_;
  my $want = $resp->header('Content-MD5') // return;
  my $content = $resp->decoded_content (charset => 'none');
  require Digest::MD5;
  my $got = Digest::MD5::md5_hex($content);
  if ($got ne $want) {
    print __x("Warning, MD5 checksum mismatch on download {url}\n",
              url => $resp->request->uri);
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
    say __x('Cannot post: {message}', message => $nntp->message);
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
  return (non_empty (html_title_urititle($resp))
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
  return URI::Title::title
    ({ url  => ($resp->request->uri // ''),
       data => $resp->decoded_content (charset => 'none')});
}
sub html_title_exiftool {
  my ($resp) = @_;
  eval { require Image::ExifTool } or return undef;

  my $data = $resp->decoded_content (charset => 'none');
  my $info = Image::ExifTool::ImageInfo
    (\$data,
     ['Title'],     # just the Title field
     {List => 0});  # give list values as comma separated

  my $title = $info->{'Title'};
  if (defined $title) {
    # PNG spec is for tEXt chunks to contain latin-1 and iTXt chunks utf-8

    # ExifTool 8.22 converts tEXt to utf8 for its return, prior versions
    # just give the latin-1 bytes.  Prior versions return iTXt as the utf-8
    # bytes, but there's no way to distinguish that.  Decoding as latin-1
    # will be wrong, but assume that anyone affected will get a new enough
    # exiftool.
    my $charset = (Image::ExifTool->VERSION >= 8.22 ? 'utf-8' : 'iso-8859-1');
    $title = Encode::decode ($charset, $title);
  }
  return $title;
}


#------------------------------------------------------------------------------
# mime

# return "X-Mailer" header string
use constant::defer mime_mailer => sub {
  require MIME::Entity;
  my $top = MIME::Entity->build (Type => 'multipart/mixed');
  return ("RSS2Leafnode $VERSION " . $top->head->get('X-Mailer'));
};

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

  my $now822 = rfc822_time_now();
  if (delete $headers->{'my_top'}) {
    $headers->{'Date'}           //= $now822;
    $headers->{'Date-Received:'} = $now822;
    $headers->{'X-Mailer'}       = $self->mime_mailer;
  }

  # Headers in utf-8, the same as other text.  The docs of
  # encode_mimewords() isn't clear, but seems to expect bytes of the
  # specified charset.
  foreach my $key (sort keys %$headers) {
    $headers->{$key}
      = mimewords_non_ascii(trim_whitespace($headers->{$key}));
  }

  %$headers = (%$headers, @args);
  $headers->{'Top'}      //= 0;  # default to a part not a toplevel
  $headers->{'Encoding'} //= '-SUGGEST';

  if (utf8::is_utf8($headers->{'Data'})) {
    warn 'Oops, mime_build() data should be bytes';
  }

  # downgrade utf-8 to us-ascii if possible
  if ($headers->{'Type'} eq 'text/plain'
      && lc($headers->{'Charset'}) eq 'utf-8'
      && is_ascii ($headers->{'Data'})) {
    $headers->{'Charset'} = 'us-ascii';

    # not sure mangling text/html is a good idea -- would only want it on
    # generated html, not downloaded
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

  return $top;
}

sub mime_part_from_response {
  my ($self, $resp, @headers) = @_;

  my $content_type = $resp->content_type;
  if ($self->{'verbose'} >= 2) { say "content-type: $content_type"; }
  my $content      = $resp->decoded_content (charset=>'none');  # the bytes
  my $charset      = $resp->content_charset;              # and their charset
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
  if (! %timingfields) {
    return; # no info
  }

  # if XML::RSS::Timing doesn't like the values then don't record them
  return unless $self->timingfields_to_timing(\%timingfields);

  return \%timingfields;
}

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
  my ($self, $str) = @_;
  require Text::WrapI18N;
  local $Text::WrapI18N::columns = $self->{'render_width'} + 1;
  local $Text::WrapI18N::unexpand = 0;       # no tabs in output
  local $Text::WrapI18N::huge = 'overflow';  # don't break long words
  $str =~ tr/\n/ /;
  return Text::WrapI18N::wrap('', '', $str);
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

  $self->nntp_post($top) || return;
  say __x('{group} 1 new article', group => $self->{'nntp_group'});
}


#------------------------------------------------------------------------------
# fetch HTML

sub http_to_host {
  my ($resp) = @_;
  my $req = $resp->request;
  my $uri = $req && $req->uri;
  return (non_empty ($uri->can('host') && $uri->host)
          // 'localhost'); # file:// schema during testing
}

sub http_to_from {
  my ($resp) = @_;
  return http_exiftool_author($resp)
    // 'nobody@'.http_to_host($resp);
}
sub http_exiftool_author {
  my ($resp) = @_;
  eval { require Image::ExifTool } || return;

  # PNG Author field, or HTML <meta> author
  my $data = $resp->decoded_content (charset => 'none');
  my $info = Image::ExifTool::ImageInfo
    (\$data,
     ['Author'],    # just the Author field
     {List => 0});  # give list values as comma separated
  my $author = $info->{'Author'} // return;
  return Encode::decode_utf8($author);
}

sub fetch_html {
  my ($self, $group, $url) = @_;
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
       my $content = $resp->decoded_content (charset=>'none');
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
     'Path:'             => scalar (http_to_host($resp)),
     'Newsgroups:'       => $group,
     From                => scalar (http_to_from($resp)),
     Subject             => $subject,
     Date                => scalar ($resp->header('Last-Modified')),
     'Message-ID'        => $msgid);

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

  # <media:content> can be a link, but have seen it just duplicating
  # <enclosure> without a length.  Would probably skip medium="image".
  #
  my @elts = $item->children (qr/^(link
                                 |enclosure
                                 |content
                                 |wiki:diff
                                 |comments
                                 |wfw:comment
                                 )$/x);
  my @links;
  my %seen;
  foreach my $elt (@elts) {
    if ($self->{'verbose'} >= 2) { say "link ",$elt->sprint,"\n"; }

    if ($elt->tag eq 'content' && atom_content_flavour($elt) ne 'link') {
      next;
    }

    my $l = { download => 1 };
    foreach my $name ('hreflang', 'title', 'type') {
      $l->{$name} = ($elt->att("atom:$name") // $elt->att($name));
    }

    given (non_empty ($elt->att('atom:rel') // $elt->att('rel'))) {
      when (!defined) {
        given ($elt->tag) {
          when (/diff/)      { $l->{'name'} = __('Diff:'); }
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
    if ($elt->tag eq 'enclosure'
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

  return @links;
}

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
    $str .= "$sep<nobr>$Entitize{$l->{'name'}}&nbsp;<a";
    $sep = "<br>\n";

    if (defined (my $hreflang = $l->{'hreflang'})) {
      $str .= " hreflang=\"$Entitize{$hreflang}\"";
    }
    if (defined (my $type = $l->{'type'})) {
      $str .= " type=\"$Entitize{$type}\"";
    }
    my $uri = $Entitize{$l->{'uri'}};
    $str .= " href=\"$uri\">$uri</a></nobr>\n";
  }
  return "$str</p>\n";
}

sub links_to_text {
  return join ('', map {"$_->{'name'} $_->{'uri'}\n"} @_);
}

#------------------------------------------------------------------------------
# fetch RSS

my $map_xmlns
  = {
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

  # Or atempt to put it through XML::Liberal, if available.
  #
  if ($err && eval { require XML::Liberal; 1 }) {
    my $liberal = XML::Liberal->new('LibXML');
    if (my $doc = eval { $liberal->parse_string($xml) }) {
      my $liberal_xml = $doc->toString;

      $twig = XML::Twig->new (map_xmlns => $map_xmlns);
      if ($twig->safe_parse ($liberal_xml)) {
        $twig->root->set_att('rss2leafnode:fixup',
                             "XML::Liberal fixed: {error}",
                             error => trim_whitespace($err));
        print __x("Feed {url}\n  parse error: {error}\n  continuing with repairs by XML::Liberal\n",
                  url     => $self->{'uri'},
                  error => trim_whitespace($err));
        undef $err;
      }
    }
  }

  if ($err) {
    # XML::Parser seems to stick some spurious leading whitespace on the error
    $err = trim_whitespace($err);

    if ($self->{'verbose'} >= 1) {
      say __x("Parse error on URL {url}\n{error}",
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
  elt_tree_strip_prefix ($root, 'atom');
  #
  #   foreach my $child ($root->descendants_or_self) {
  #     foreach my $attname ($child->att_names) {
  #       if ($attname =~ /^atom:(.*)/) {
  #         $child->change_att_name($attname, $1);
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
  if ($self->{'verbose'} >= 2) { say 'msgid from MD5'; }
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
  my $inrep = $item->first_child('thr:in-reply-to') // return undef;
  my $ref = ($inrep->att('thr:ref')
             // $inrep->att('ref')
             // $inrep->att('atom:ref') # comes out atom: under map_xmlns ...
             // return undef);
  $ref = elt_xml_based_uri ($inrep, $ref); # probably shouldn't be relative ...
  return $self->url_to_msgid ($ref);
}

# Return a string of comma separated keywords per RFC1036 and RFC2822.
sub item_to_keywords {
  my ($self, $item) = @_;

  # <category> is often present with no other keywords, work that in as a
  # bit of a fallback, being better than nothing for classification.
  #
  # <itunes:category> might be covered by <itunes:keywords> anyway, but work
  # it in for more classification for now.  Can have child <itunes:category>
  # elements as sub-categories, but don't worry about them.
  #
  # <slash:section> might in theory be turned into keyword, but it's
  # normally just "news" or something not particularly informative.
  #
  # How much value is there in the channel keywords?
  #
  my $re = qr/^(category
              |itunes:category
              |media:keywords
              |itunes:keywords
              )$/x;
  return join_non_empty
    (', ',
     List::MoreUtils::uniq
     (map { collapse_whitespace($_) }
      map { split /,/ }
      map { $_->att('text')   # itunes:category
              // $_->text }   # other
      ($item->children($re),
       item_to_channel($item)->children($re))));
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

  my $email = elt_to_rendered_line
    ($elt->first_child(qr/^(email                # Atom
                          |itunes:email)$/x));   # itunes:owner

  my $ret = join_non_empty
    (' ',
     $elt->text_only,
     elt_to_rendered_line
     ($elt->first_child(qr/^(name             # Atom
                           |itunes:name)/x)), # itunes:owner
     do {
       # <rdf:Description><rdf:value>...</></> under dc authors etc
       my $rdfdesc = $elt->first_child('rdf:Description');
       $rdfdesc && $rdfdesc->first_child_text('rdf:value')
     });

  if (is_non_empty($email)) {
    if (is_non_empty ($ret)) {
      # Are escapes needed in "<...>" part?  Shouldn't have strange chars in
      # the email address.
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

  # <author> is supposed to be an email address whereas <dc:creator> is
  # looser.  The RSS recommendation is to use author when revealing an email
  # and dc:creator when hiding it.
  #
  # <dc:contributor> in wiki: feeds.
  #
  # <contributor> multiple times in Atom item, don't think can usefully just
  # pick one of them.  Hope for a primary author.
  #
  return (elt_to_email    ($item->first_child('author'))
          // elt_to_email ($item->first_child('dc:creator'))
          // elt_to_email ($item->first_child('dc:contributor'))
          // elt_to_email ($item->first_child('wiki:username'))
          // elt_to_email ($item->first_child('itunes:author'))

          // elt_to_email ($channel->first_child('dc:creator'))
          // elt_to_email ($channel->first_child('author'))
          // elt_to_email ($channel->first_child('itunes:author'))
          // elt_to_email ($channel->first_child('managingEditor'))
          // elt_to_email ($channel->first_child('webMaster'))

          // elt_to_email ($item   ->first_child('dc:publisher'))
          // elt_to_email ($channel->first_child('dc:publisher'))
          // elt_to_email ($channel->first_child('itunes:owner'))

          # Atom <title> can have type="html" etc in the usual way.
          // elt_to_rendered_line ($channel->first_child('title'))

          # RFC822
          // ('nobody@'.$self->uri_to_host)
         );
}

sub item_to_subject {
  my ($self, $item) = @_;

  # Atom <title> can have type="html" etc in the usual way.
  return
    (elt_to_rendered_line    ($item->first_child('title'))
     // elt_to_rendered_line ($item->first_child('dc:subject'))
     // __('no subject'));
}

# return language code string or undef
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
  my $re = qr/^(rights      # Atom
              |copyright    # RSS, don't think entity-encoded html allowed there
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

# return copyright string or undef
sub item_to_feedburner {
  my ($self, $item) = @_;
  my $channel = item_to_channel($item);
  my $elt = $channel->first_child('feedburner:info') || return;
  my $uri = $elt->att('uri') // return;
  return URI->new_abs ($uri, 'http://feeds.feedburner.com/')->as_string;
}

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

# $item is an XML::Twig::Elt
#
sub fetch_rss_process_one_item {
  my ($self, $item) = @_;
  my $subject = $self->item_to_subject ($item);
  if ($self->{'verbose'} >= 1) { say __x(' item: {subject}',
                                         subject => $subject); }
  my $msgid = $self->item_to_msgid ($item);
  return 0 if $self->nntp_message_id_exists ($msgid);

  my $channel = item_to_channel($item);
  my @links = $self->item_to_links ($item);

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
       Keywords       => scalar ($self->item_to_keywords($item)),
       Date           => scalar ($self->item_to_date($item)),
       'In-Reply-To:'      => scalar ($self->item_to_in_reply_to($item)),
       'Message-ID'        => $msgid,
       'Content-Language:' => scalar ($self->item_to_language($item)),
       'List-Post:'        => scalar (googlegroups_link_email(@links)),
       # ENHANCE-ME: Maybe transform <itunes:explicit> "yes","no","clean"
       # into PICS too maybe, unless it only applies to the enclosure as
       # such.  Maybe <media:adult> likewise.
       'PICS-Label:'       => scalar (collapse_whitespace
                                      ($channel->first_child_text('rating'))),
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
  my $body = (# <content:encoded> generally bigger or better than
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
              || $item->first_child('summary'));  # Atom

  my $body_type = elt_content_type ($body);
  if ($self->{'verbose'} >= 3) { print " body_type from elt: $body_type\n"; }
  my $body_charset = 'utf-8';
  my $body_base_url = elt_xml_base ($body);
  given ($body_type) {
    when (! defined) { # no $body element at all
      $body = '';
      $body_type = 'text/plain';
    }
    when ('xhtml') {   # Atom
      $body = elt_xhtml_to_html ($body);
      $body_type = 'html';
    }
    when ('html') {    # RSS or Atom
      $body = elt_subtext($body);
    }
    when ('text') {    # Atom 'text' to be flowed
      # should be text-only, no sub-elements, but extract sub-elements to
      # cope with dodgy feeds with improperly escaped html etc
      $body = $self->text_wrap (elt_subtext ($body));
      $body_type = 'text/plain';
    }
    when (m{^text/}) { # Atom mime text type
      $body = elt_subtext ($body);
    }
    default {          # Atom base64 something
      $body = MIME::Base64::decode ($body->text);
      $body_charset = undef;
    }
  }
  if ($self->{'verbose'} >= 3) { print " body: $body_type charset=",
                                   $body_charset//'undef',"\n",
                                     "$body\n"; }

  my $body_is_html = ($body_type ~~ ['html','text/html']);
  my $links_want_html = ($body_is_html && ! $self->{'render'});
  my $links_str = ($links_want_html
                   ? links_to_html(@links)
                   : links_to_text(@links));

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
      #
      $self->enforce_html_charset_from_content ($resp);
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

  my $xml = $resp->decoded_content (charset => 'none');  # raw bytes
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
