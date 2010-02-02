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
use Date::Parse;
use Locale::TextDomain ('App-RSS2Leafnode');

our $VERSION = 18;


# Cribs:
#
# http://my.netscape.com/publish/help/
#     RSS 0.9 spec.
# http://my.netscape.com/publish/help/mnn20/quickstart.html
#     RSS 0.91 spec.
# http://purl.org/rss/1.0/
#     RSS 1.0 spec.
# http://www.rssboard.org/rss-specification
# http://www.rssboard.org/files/rss-2.0-sample.xml
#     RSS 2.0 spec and sample.
# http://www.rssboard.org/rss-profile
#     "Best practices."
#
# RFC 850, RFC 1036 -- News message format, inc headers and rnews format
# RFC 977 -- NNTP
# RFC 1327 - X.400 to RFC822 introducing Language header
# RFC 1738 -- URL formats
# RFC 1864 -- Content-MD5 header
# RFC 2557 -- MHTML Content-Location
# RFC 2616 -- HTTP/1.1 Accept-Encoding header
# RFC 2369 -- List-Post header and friends
# RFC 3282 -- Content-Language header
#
# RFC 2076 -- headers summary
# RFC 4021 -- headers summary
#
# http://www3.ietf.org/proceedings/98dec/I-D/draft-ietf-drums-mail-followup-to-00.txt
#     Draft Mail-Followup-To header.
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
# misc

use constant sy => 'http://purl.org/rss/1.0/modules/syndication/';

use constant RFC822_STRFTIME_FORMAT => '%a, %d %b %Y %H:%M:%S %z';

# return a string which is current time in RFC 822 format
sub rfc822_time_now {
  return POSIX::strftime (RFC822_STRFTIME_FORMAT, localtime(time()));
}

# $a and $b are XML::RSS feed items (hash references).
# Return the one with the greatest pubDate, or $a if they're equal or they
# don't both have a pubDate.
# The dates ought to be RFC822 format, but let Date::Parse figure that out.
#
sub item_pubdate_max {
  my ($a, $b) = @_;

  my $a_time = $a->{'pubDate'};
  if ($a_time) { $a_time = Date::Parse::str2time($a_time); }

  my $b_time = $b->{'pubDate'};
  if ($b_time) { $b_time = Date::Parse::str2time($b_time); }

  if ($a_time && $b_time && $b_time > $a_time) {
    return $b;
  } else {
    return $a;
  }
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
  my ($self, $uri, $str) = @_;
  $uri = URI->new($uri)->canonical;

  # $host can be empty if you test from a file:/// url
  # "localhost" is a bit bogus and in particular leafnode won't accept it
  my $host;
  if ($uri->can('host')) { $host = $uri->host; }
  if (! defined $host || $host eq '' || $host eq 'localhost') {
    require Sys::Hostname;
    eval { $host = Sys::Hostname::hostname() };
  }
  if (! defined $host || $host eq '' || $host eq 'localhost') {
    $host = 'rss2leafnode.invalid';
  }
  my $pathbit = $uri->scheme.':'.$uri->path;
  $str //= '';
  if ($str ne '') { $str = ".$str"; }

  return ('<' . msgid_chars("rss2leafnode"
                            . $self->{'msgidextra'}
                            . ".$pathbit$str")
          . '@' . msgid_chars($host)
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
# "Dublin core"

use constant dc => 'http://purl.org/dc/elements/1.1/';

sub item_dc_date_to_pubdate {
  my ($item) = @_;   # a channel item hashref
  if ($item->{'pubDate'}) { return; }
  my $isodate = $item->{(dc)}{'date'} // return;
  $item->{'pubDate'} = isodate_to_rfc822($isodate);
}

sub isodate_to_rfc822 {
  my ($isodate) = @_;
  $isodate =~ /\dT\d/ or return $isodate; # not an iso format

  # eg. "2000-01-01T12:00+00:00"
  #     "2000-01-01T12:00:00Z"
  my $date = $isodate;  # the original goes through if unrecognised
  my $zonestr = ($isodate =~ s/([+-][0-9][0-9]):([0-9][0-9])$// ? " $1$2"
                 : $isodate =~ s/Z$// ? ' +0000'
                 : '');
  require Date::Parse;
  my $time_t = Date::Parse::str2time($isodate);
  if (defined $time_t) {
    $date = POSIX::strftime ("%a, %d %b %Y %H:%M:%S$zonestr",
                             localtime ($time_t));
  }
  return $date;
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
  my $d = Data::Dumper->new([$self->{'global_status'}],['global_status'])
    ->Indent(1)->Sortkeys(1);
  my $str = <<'HERE';
# rss2leafnode status file -- automatically generated -- DO NOT EDIT
#
# (If there seems to be something very wrong then you can delete this file
# and it'll be started afresh on the next run.)

HERE
  $str .= $d->Dump . "\n";

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
# Optional $feed is $resp parsed to an XML:RSS object.
# Record against $url any ETag, Last-Modified and ttl from $resp and $feed.
# If $resp is an error return, or is undef, then do nothing.
sub status_etagmod_resp {
  my ($self, $url, $resp, $feed) = @_;
  if ($resp && $resp->is_success) {
    my $status = $self->status_geturl ($url);
    $status->{'Last-Modified'} = $resp->header('Last-Modified');
    $status->{'ETag'}          = $resp->header('ETag');
    $status->{'timingfields'}  = feed_to_timingfields ($feed);
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

  if (my $timing = timingfields_to_timing ($status->{'timingfields'})) {
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

# XML::RSS and XML::RSS::LibXML are compatible, you can use whichever you've
# got installed.  XML::RSSLite can't be used, it's a bit different.  If it
# got a new() and parse() interface similar to XML::RSS it could be ok,
# though as of version 0.11 it has a hard time on CDATA and maybe other xml
# obscurities.
#
sub XML_RSS_class {
  my ($self) = @_;
  if (defined $self->{'XML_RSS_class'}) {
    return $self->{'XML_RSS_class'};
  }

  my @classes = ('XML::RSS::LibXML', 'XML::RSS');
  my @errors;
  require Module::Load;
  foreach my $class (@classes) {
    if (eval { Module::Load::load ($class); 1 }) {
      if ($self->{'verbose'}) { print "xml use $class\n"; }
      return $class;
    }
    push @errors, $@;
  }
  croak "Cannot load ",join(' or ',@classes),"\n",
    @errors,"  ";
}


#------------------------------------------------------------------------------
# XML::RSS::Timing

sub feed_to_timingfields {
  my ($feed) = @_;
  my %timingfields;
  my $channel = $feed->{'channel'};
  $timingfields{'ttl'} = $channel->{'ttl'};
  # LibXML has empty strings under $channel but arrayrefs under $feed
  if (my $skipHours = $feed->{'skipHours'}->{'hour'}) {
    $timingfields{'skipHours'} = $skipHours;
  }
  if (my $skipDays = $feed->{'skipDays'}->{'day'}) {
    $timingfields{'skipDays'} = $skipDays;
  }
  foreach my $key (qw(updatePeriod updateFrequency updateBase)) {
    $timingfields{$key} = $channel->{(sy)}->{$key}; # "syn" spec fields
  }
  delete @timingfields{grep {! defined $timingfields{$_}} keys %timingfields};
  # if XML::RSS::Timing doesn't like the values then don't record them
  return timingfields_to_timing (\%timingfields) && \%timingfields;
}

# return an XML::RSS::Timing object, or undef
sub timingfields_to_timing {
  my ($timingfields) = @_;
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
    foreach my $complaint (@complaints) {
      print __x("XML::RSS::Timing complains: {error}\n",
                error => $complaint);
    }
    print __("  ... ignore timing\n");
    return undef;
  }
  return $timing;
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

  my $from = 'RSS2Leafnode <nobody@localhost>';
  my $date = rfc822_time_now();
  my $host = 'localhost';
  my $content = str_ensure_newline ($message);
  my $msgid = $self->url_to_msgid
    ('http://localhost',
     Digest::MD5::md5_base64 ($date.$subject.$content));

  require MIME::Entity;
  my $top = MIME::Entity->build('Path:'       => $host,
                                'Newsgroups:' => $self->{'nntp_group'},
                                From          => $from,
                                Subject       => $subject,
                                Date          => $date,
                                'Message-ID'  => $msgid,

                                Type          => 'text/plain',
                                Encoding      => '-SUGGEST',
                                Data          => $content);
  $self->mime_mailer_rss2leafnode ($top);

  $self->nntp_post($top) || return;
  print __x("{group} 1 new article\n", group => $self->{'nntp_group'});
}


#------------------------------------------------------------------------------
# fetch HTML

sub fetch_html {
  my ($self, $group, $url) = @_;
  if ($self->{'verbose'} >= 1) { print "page: $url\n"; }

  my $group_uri = URI->new($group,'news');
  local $self->{'nntp_host'} = _choose ($group_uri->host, 'localhost');
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

  my $now822 = rfc822_time_now();
  my $date = scalar($resp->header('Last-Modified')) || $now822;
  my $host = URI->new($url)->host
    || 'localhost'; # in case file:// schema during testing
  my $from = 'nobody@'.$host;
  my $language = $resp->header('Content-Language');

  require File::Basename;
  my $subject = html_title($resp) // File::Basename::basename($url);

  ($content, $content_type, $charset)
    = $self->render_maybe ($content, $content_type, $charset);

  require MIME::Entity;
  my $top = MIME::Entity->build ('Path:'             => $host,
                                 'Newsgroups:'       => $group,
                                 From                => $from,
                                 Subject             => $subject,
                                 Date                => $date,
                                 'Message-ID'        => $msgid,
                                 'Date-Received:'    => $now822,
                                 'Content-Language:' => $language,
                                 'Content-Location:' => $url,

                                 Type                => $content_type,
                                 Encoding            => '-SUGGEST',
                                 Charset             => $charset,
                                 Data                => $content);
  $self->mime_mailer_rss2leafnode ($top);

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
  my $link = $item->{'link'} // return;
  $link =~ m{^http://[^/]*yahoo\.com/.*\*(http://.*yahoo\.com.*)$} or return;
  return $1;
}

# This is a special case for Google Groups RSS feeds.
# $link is a url string, or undef.  If it's a google groups form like
# "http://groups.google.com/group/cfcdev/msg/445d4ccfdabf086b" then return a
# mailing list address like "cfcdev@googlegroups.com".  If not in that form
# then return undef.
#
sub googlegroups_link_email {
  my ($link) = @_;
  defined $link or return;
  $link =~ m{^http://groups\.google\.com/group/([^/]+)/} or return;
  return ($1 . '@googlegroups.com');
}

# This is a nasty hack for http://www.aireview.com.au/rss.php
# $link is a link url string just fetched, $resp is a HTTP::Response.  The
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
  my ($self, $link, $resp) = @_;

  if ($resp->is_success) {
    my $content = $resp->decoded_content (charset=>'none');
    if ($content =~ /<META[^>]*Refresh[^>]*checkForCookies/i) {
      if ($self->{'verbose'}) {
        print "  following aireview META Refresh with cookies\n";
      }
      require HTTP::Request;
      my $req = HTTP::Request->new (GET => $link);
      $resp = $self->ua->request($req);
    }
  }
  return $resp;
}


#------------------------------------------------------------------------------
# fetch RSS

sub _trim_whitespace {
  my ($str) = @_;
  defined $str or return;
  $str =~ s/^\s+//; # leading whitespace
  $str =~ s/\s+$//; # trailing whitespace
  return $str;
}
sub _choose {
  my @choices = @_;
  # require Data::Dumper;
  # print Data::Dumper->new([\@choices],['choices'])->Dump;
  foreach my $str (@choices) {
    next if ! defined $str;
    $str = _trim_whitespace("$str"); # stringize LibXML stuff
    next if $str eq '';
    return $str;
  }
  return;
}

# return a Message-ID string for this $item coming from $self->{'uri'}
#
sub item_to_msgid {
  my ($self, $item) = @_;

  if (defined (my $permalink = $item->{'permaLink'})) {
    # <guid isPermaLink="true">
    return $self->url_to_msgid ($permalink);
  }
  if (my $link = item_yahoo_permalink ($item)) {
    return $self->url_to_msgid ($link);
  }
  if (defined (my $guid = $item->{'guid'})) {
    # <guid isPermaLink="false">
    return $self->url_to_msgid ($self->{'uri'}, $guid);
  }

  # nothing in the item, use the feed url and MD5 of some fields which
  # will hopefully distinguish it from other items at this url
  if ($self->{'verbose'} >= 2) { print "msgid from MD5\n"; }
  return $self->url_to_msgid ($self->{'uri'},
                              md5_of_utf8 (($item->{'title'} // '')
                                           . ($item->{'author'} // '')
                                           . ($item->{(dc)}{'creator'} // '')
                                           . ($item->{'description'} // '')
                                           . ($item->{'link'} // '')
                                           . ($item->{'pubDate'} // '')));
}

# return the host part of $self->{'uri'}, or "localhost" if none
sub uri_to_host {
  my ($self) = @_;
  my $uri = $self->{'uri'};
  return _choose ($uri->can('host') && $uri->host,
                  'localhost');
}

sub atom_person_to_email {
  my ($person) = @_;
  (Scalar::Util::blessed($person) && $person->isa('XML::Atom::Person'))
    or return $person;
  my $name  = _choose ($person->name);
  my $email = _choose ($person->email);
  if (! defined $name) { return $email; }
  if (defined $email) { $name .= " <$email>"; }
  return $name;
}

# return email addr string
sub item_to_from {
  my ($self, $feed, $item) = @_;
  my $channel = $feed->{'channel'};

  my $from = _choose
    (# from the item
     (Scalar::Util::blessed($item)
      && $item->can('author')  # XML::Atom::Entry
      && atom_person_to_email($item->author)),
     $item->{'author'},
     $item->{(dc)}{'creator'},

     # from the feed
     (Scalar::Util::blessed($feed)
      && $feed->can('author')  # XML::Atom::Feed
      && atom_person_to_email($feed->author)),
     $channel->{'managingEditor'},
     $channel->{'webMaster'},
     $channel->{(dc)}{'publisher'},
     # scraping the bottom of the barrel ...
     $channel->{'title'},

     'nobody@'.$self->uri_to_host);

  # eg.     "Rael Dornfest (mailto:rael@oreilly.com)"
  # becomes "Rael Dornfest <rael@oreilly.com>"
  $from =~ s/\(mailto:(.*)\)/<$1>/;

  # Collapse whitespace against possible tabs and newlines in a <author> as
  # from googlegroups for instance.  MIME::Entity seems to collapse
  # newlines, but not tabs.
  $from =~ s/\s+/ /g;

  return $from;
}

sub item_to_subject {
  my ($self, $item) = @_;

  return _choose ((Scalar::Util::blessed($item)
                   && $item->can('title')  # XML::Atom::Entry
                   && $item->title),
                  $item->{'title'},
                  __('no subject'));
}

sub item_to_date {
  my ($self, $feed, $item) = @_;
  my $channel = $feed->{'channel'};

  my $date = _choose
    (# item dates
     (Scalar::Util::blessed($item)
      && $item->can('modified')   # XML::Atom::Entry
      && $item->modified),
     (Scalar::Util::blessed($item)
      && $item->can('issued')  # XML::Atom::Entry
      && $item->issued),
     (Scalar::Util::blessed($item)
      && $item->can('created')  # XML::Atom::Entry
      && $item->created),
     $item->{'pubDate'},
     $item->{(dc)}{'date'},

     # feed dates
     $channel->{'pubDate'},
     $channel->{'lastBuildDate'},

     $self->{'now822'});

  return isodate_to_rfc822($date);
}

# return language code string or undef
sub item_to_language {
  my ($self, $feed, $item) = @_;
  return _choose ((Scalar::Util::blessed($feed)
                   && $feed->can('language')  # XML::Atom::Feed
                   && $feed->language),
                  $feed->{'channel'}->{'language'},
                  scalar $self->{'resp'}->content_language);
}

# return copyright string or undef
sub item_to_copyright {
  my ($self, $feed, $item) = @_;
  return _choose ((Scalar::Util::blessed($feed)
                   && $feed->can('copyright')  # XML::Atom::Feed
                   && $feed->copyright),
                  (Scalar::Util::blessed($feed)
                   && $feed->can('rights')     # XML::Atom::Feed
                   && $feed->rights),
                  $item->{(dc)}{'rights'},
                  $feed->{'channel'}->{'copyright'});
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
    } elsif ($xml =~ s/(<\?xml)/$1 encoding="$charset"/i) {
      if ($self->{'verbose'} >= 2) {
        print "insert encoding=$charset\n";
      }
    } else {
      my $str = "<?xml encoding=\"$charset\"?>\n";
      if ($self->{'verbose'} >= 2) {
        print "insert $str";
      }
      $xml = $str . $xml;
    }
    $xml = Encode::encode ($charset, $xml);
  }
  return $xml;
}

# $feed is an XML::RSS hashref, the parsed RSS feed from $url
# $item is a hashref, one of the $feed->{'items'}
#
sub fetch_rss_process_one_item {
  my ($self, $feed, $item) = @_;

  # $req->uri can be a URI object or a string, use URI->new to make an object
  my $uri = URI->new ($self->{'resp'}->request->uri);
  local $self->{'uri'} = $uri;

  my $msgid = $self->item_to_msgid ($item);
  return 0 if $self->nntp_message_id_exists ($msgid);

  my $subject = $self->item_to_subject ($item);
  if ($self->{'verbose'} >= 1) { print __x(" item: {subject}\n",
                                           subject => $subject); }

  my $channel = $feed->{'channel'};
  local $self->{'now822'} = rfc822_time_now();

  item_dc_date_to_pubdate ($item);
  my $date = $self->item_to_date ($feed, $item);

  my $link = $item->{'link'};

  my $from = $self->item_to_from ($feed, $item);
  my $list_email = googlegroups_link_email($link);
  my $copyright = $self->item_to_copyright ($feed, $item);
  my $generator = $channel->{'generator'};
  my $pics = $channel->{'rating'};

  # Headers in utf-8, the same as other text.  The docs of
  # encode_mimewords() isn't clear, but seems to expect bytes of the
  # specified charset.
  require MIME::Words;
  foreach ($from, $subject, $copyright, $generator) {
    if (defined $_) {
      $_ = MIME::Words::encode_mimewords (Encode::encode_utf8($_),
                                          Charset => 'UTF-8');
    }
  }

  # dunno if many newsreaders look at Content-Language, but put it through
  # if we've got it
  my $language = $self->item_to_language ($feed, $item);

  my $body = <<'HERE';
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<html>
<head>
<meta http-equiv=Content-Type content="text/html; charset=utf-8">
</head
<body>
HERE
  # ought to have a description, but sometimes missing
  if (defined $item->{'description'}) {
    $body .= $item->{'description'};
  }
  # <pre> and <nobr> on the link with the idea of not letting the displayed
  # form get chopped up
  if ($link && !$self->{'render'}) { # link appended if not rendering to text
    $body .= "\n\n<p><a href=\"$link\"><nobr><pre>$link</pre></nobr><br><br></a></p>";
  }
  $body .= "\n</body></html>\n";

  my $body_charset = 'utf-8';
  $body = Encode::encode_utf8 ($body);
  my $body_type = 'text/html';

  ($body, $body_type, $body_charset)
    = $self->render_maybe ($body, $body_type, $body_charset);

  # Link appended as text if rendered to text, rather than rely on
  # <a href="">...</a> to come out looking good.  In particular it doesn't
  # come out looking good with lynx.
  if ($link && $self->{'render'}) {
    $body =~ s/[ \t\r\n]+$//;
    $body .= Encode::encode_utf8 ("\n\n$link\n");
  }

  # Crib: an undef value for a header means omit that header, which is good
  # for say the merely optional $language
  #
  require MIME::Entity;
  my $top = MIME::Entity->build('Path:'        => $self->uri_to_host,
                                'Newsgroups:'  => $self->{'nntp_group'},
                                From           => $from,
                                Subject        => $subject,
                                Date           => $date,
                                'Message-ID'   => $msgid,
                                'Content-Language:' => $language,
                                'Date-Received:'    => $self->{'now822'},
                                'List-Post:'        => $list_email,
                                'PICS-Label:'       => $pics,
                                'X-Copyright:'      => $copyright,
                                'X-RSS-URL:'        => $uri->as_string,
                                'X-RSS-Feed-Link:'  => $channel->{'link'},
                                'X-RSS-Generator:'  => $generator,

                                Type           => $body_type,
                                Encoding       => '-SUGGEST',
                                Charset        => $body_charset,
                                Data           => $body);
  $self->mime_mailer_rss2leafnode ($top);

  if ($link && $self->{'rss_get_links'}) {
    if ($self->{'verbose'}) { print __x("  link: {link}\n",
                                        link => $link); }
    require HTTP::Request;
    my $req = HTTP::Request->new (GET => $link);
    my $resp = $self->ua->request($req);
    $resp = $self->aireview_follow ($link, $resp);

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
                url => $link,
                status => $resp->status_line);
      $down = "\n" . __x("Cannot download link:\n{status}",
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
                    'Content-Location:' => $link);
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
  local $self->{'nntp_host'} = _choose ($group_uri->host, 'localhost');
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

  my $xml_rss_class = $self->XML_RSS_class;
  my $feed = $xml_rss_class->new;
  if (! eval { $feed->parse($xml); 1 }) {
    my $err = $@;
    $err = _trim_whitespace($err);  # spurious leading newlines from XML::RSS
    if ($self->{'verbose'} >= 1) {
      print __x("rss2leafnode: {url}\n", url => $url);
      print __x(" parse error: {error}\n", error => $err);
    }
    $self->error_message
      (__x("Error parsing {url}", url => $url),
       __x("{class} parse error on:\n\n    {url}\n\n{error}",
           class => $xml_rss_class,
           url => $url,
           error => $err));
    # after successful error message to news
    $self->status_etagmod_resp ($url, $resp);
    return;
  }
  if ($self->{'verbose'} >= 2) {
    require Data::Dumper;
    print Data::Dumper->new([$feed],["$xml_rss_class feed"])
      ->Indent(1)->Sortkeys(1)->Dump;
  }
  my $items = $feed->{'items'};

  if ($self->{'rss_newest_only'}) {
    my ($a,$b);
    my $newest = List::Util::reduce { item_pubdate_max ($a, $b) } @$items[0];
    $items = [ $newest ];
  }

  my $new = 0;
  foreach my $item (@$items) {
    $new += $self->fetch_rss_process_one_item ($feed, $item);
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

  $self->status_etagmod_resp ($url, $resp, $feed);
  print __xn("{group}: {count} new article\n",
             "{group}: {count} new articles\n",
             $new,
             group => $group,
             count => $new);
}

1;
__END__

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
L<XML::RSS::LibXML>,
L<XML::RSS>,

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
