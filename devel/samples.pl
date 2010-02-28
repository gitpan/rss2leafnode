#!/usr/bin/perl

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

if (1) {
  no warnings 'redefine';
  *App::RSS2Leafnode::nntp_message_id_exists = sub { 0 };
  *App::RSS2Leafnode::nntp_post = sub {
    my ($self, $mime) = @_;
    print "\n",$mime->as_string,"\n\n";

    if ($mime->mime_type eq 'text/html') {
      my $html = $mime->bodyhandle->as_string;
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
    } else {
      print "[mime_type ",$mime->mime_type,"]\n";
    }
    return 1;
  };
}

my $r2l = App::RSS2Leafnode->new
  (
   # rss_charset_override => 'windows-1252',
   # rss_charset_override => 'iso-8859-1',
   verbose => 1,
   # render => 'lynx',
   rss_newest_only => 1,
   msgidextra => 'e',
  );

my @uris;

GetOptions (require_order => 1,
            'verbose:1'  => \$r2l->{'verbose'},
            'msgid=s'    => \$r2l->{'msgidextra'},
            'newest'     => \$r2l->{'rss_newest_only'},
            '<>' => sub {
              my ($arg) = @_;
              push @uris, URI->new("$arg",'file');
            },
           ) or return 1;

if (! @uris) {
  @uris = map {URI::file->new($_)} glob('samp/*');
  $r2l->{'rss_newest_only'} = 1;
}

foreach my $uri (@uris) {
  if ($uri->isa('URI::file')) {
    $uri = $uri->new_abs($uri);
  }
}

foreach my $uri (@uris) {
  print "-------------------------------------------------------------------------------\n$uri\n";
  $r2l->fetch_rss ('r2l.test', $uri);
}
exit 0;
