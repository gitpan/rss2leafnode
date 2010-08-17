#!/usr/bin/perl -w

# Copyright 2008, 2009, 2010 Kevin Ryde
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

use strict;
use warnings;
use App::RSS2Leafnode;
use URI;
use URI::file;
use Getopt::Long;

use FindBin;
my $progname = $FindBin::Script;

my $r2l = App::RSS2Leafnode->new
  (
   # rss_charset_override => 'windows-1252',
   # rss_charset_override => 'iso-8859-1',
   verbose => 1,
   # render => 'lynx',
   rss_newest_only => 3,
   # rss_get_links => 1,
   msgidextra => 'Z',
  );

my @uris;
my $method = 'fetch_rss';
my $option_post = 0;

GetOptions (require_order => 1,
            'verbose:1'  => \$r2l->{'verbose'},
            'msgid=s'    => \$r2l->{'msgidextra'},
            'newest'     => \$r2l->{'rss_newest_only'},
            'html'       => sub { $method = 'fetch_html' },
            'post'       => \$option_post,
            'all'        => sub { $r2l->{'rss_newest_only'} = 0 },
            '<>' => sub {
              my ($arg) = @_;
              push @uris, URI->new("$arg",'file');
            },
           ) or exit 1;

if (! $option_post) {
  no warnings 'redefine';
  *App::RSS2Leafnode::nntp_message_id_exists = sub { 0 };
  *App::RSS2Leafnode::nntp_post = sub {
    my ($self, $mime) = @_;
    print "\n[$progname: message]\n",
      $mime->as_string,
        "\n[$progname: end, mime_type ",$mime->mime_type,"]\n";

    if ($mime->mime_type eq 'text/html') {
      my $html = $mime->bodyhandle->as_string;
      # print $html;

      require HTML::Lint;
      my $lint = HTML::Lint->new;
      $lint->newfile ('message');
      $lint->parse ($html);

      my @errors = $lint->errors;
      @errors = grep {$_->errcode ne 'text-use-entity'} @errors;

      print "HTML::Lint errors ",scalar(@errors),"\n";
      foreach my $error (@errors) {
        print $error->as_string, "\n";
      }
    }
    return 1;
  };
}

if (1) {
  $r2l->ua->add_handler(response_done => \&lwp_response_done__add_content_md5);
  sub lwp_response_done__add_content_md5 {
    my ($resp, $ua, $h) = @_;
    if ($resp->is_success && ! defined $resp->header('Content-MD5')) {
      my $uri = $resp->request->uri;
      print "$progname: add Content-MD5 to $uri\n";
      my $content = $resp->decoded_content (charset => 'none');

      # require Data::Dumper;
      # print "$progname: ", Data::Dumper->new([\$content],['content'])->Useqq(1)->Dump;
      # print "$progname: ", $resp->headers->as_string;

      require Digest::MD5;
      my $md5 = Digest::MD5::md5_hex($content);
      $resp->headers->header ('Content-MD5' => $md5);
    }
  }

  #       if ($uri->scheme eq 'file' && $uri->host ~~ ['','localhost']) {
  #         my $filename = $uri->file;
  #         require Digest::file;
  #         $md5 = Digest::file::digest_file_hex($filename, "MD5");
  #       } else {
  #       }
}

if (! @uris) {
  @uris = map {URI::file->new($_)} glob('samp/*');
  $r2l->{'rss_newest_only'} = 1;
}

foreach my $uri (@uris) {
  if ($uri->isa('URI::file')) {
    $uri = URI->new_abs ($uri, URI::file->cwd);
  }
}

foreach my $uri (@uris) {
  print "-------------------------------------------------------------------------------\n$progname: $method $uri\n";

  # force re-read
  $r2l->status_read;
  delete $r2l->{'global_status'}->{$uri};

  $r2l->$method ('r2l.test', $uri);
}
exit 0;
