#!/usr/bin/perl

# Copyright 2010 Kevin Ryde
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
use LWP::UserAgent;
use Cwd;
use FindBin;

{
  my $filename;
  $filename = '/usr/share/doc/sqlite3-doc/images/arch.png';
  $filename = "../../tux/web/gtk2-ex-clock/screenshot.png";

  require Image::ExifTool;
  my $info = Image::ExifTool::ImageInfo
    ($filename,
     ['Titxxle'],
     {List => 0,    # give list values as comma separated
      Charset => 'UTF8'});

  #   $e->ExtractInfo($filename,
  #                   ['Foo'],
  #                   List => 0,    # give list values as comma separated
  #                   Charset => 'UTF8',
  #                   Unknown => 1);
  #   my $info = $e->GetInfo('Title');

  require Data::Dumper;
  print Data::Dumper->new([\$info],['info'])->Dump;
  exit 0;
}

{
  require URI::file;
  require URI::Title;
  my $url = "file://@{[Cwd::cwd()]}/../../tux/web/gtk2-ex-clock/screenshot.png";
  print "$url\n";

  my $ua = LWP::UserAgent->new;
  my $resp = $ua->get($url);
  print $resp->content_type,"\n";

  my $title = URI::Title::title($url);
  print $title,"\n";
  exit 0;
}

{
  require URI;
  my $uri = URI->new('data:,Foo');
  print $uri->data,"\n";
  print $uri->host;
  exit 0;
}

my $ua = LWP::UserAgent->new;
# my $url = 'http://localhost/index.html';
my $url = "file://$FindBin::Bin/lwp-title.html";
my $resp = $ua->get($url);
my $title = $resp->title;
print $title,"\n";
# print $resp->as_string,"\n";

{
  require URI::Title;
  my $data = $resp->decoded_content(charset=>'none');
  $title = URI::Title::title({ data => \$data });
  print $title,"\n";
}

exit 0;

