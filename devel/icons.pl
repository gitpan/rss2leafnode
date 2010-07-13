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
use List::Util 'max','min';
use POSIX ();
use Locale::TextDomain 1.17;
use Locale::TextDomain ('App-RSS2Leafnode');

use Smart::Comments;

my $ua = LWP::UserAgent->new;
#my $url = 'file:///usr/share/emacs/22.3/etc/images/icons/emacs_32.png';
# my $url = 'file:///tmp/x.jpg';
my $url = 'file:///usr/share/icons/hicolor/64x64/apps/xtide.png';
download_face(bless({verbose=>2},'main'), $url);

sub download_face {
  my ($self, $url, $width, $height) = @_;
  $width //= 0;
  $height //= 0;

  if ($width > 0 && $width >= 2*$height) {
    # some obnoxious banner
    if ($self->{'verbose'} >= 2) {
      print __x("  icon some obnoxious banner ({width}x{height})\n",
                width => $width,
                height => $height);
    }
    return;
  }

  require HTTP::Request;
  my $req = HTTP::Request->new (GET => $url);
  my $resp = $ua->request($req);

  my $type = $resp->content_type;
  ### $type
  unless ($type =~ m{^image/(.*)$}i) {
    if ($self->{'verbose'} >= 2) {
      print "ignore non-image icon type: $type\n";
    }
    return;
  }
  $type = $1; # .'xx';

  my $data = $resp->decoded_content(charset=>'none');
  if ($type ne 'png'
      || $width == 0 || $height == 0
      || $width > 48 || $height > 48) {
    $data = $self->imagemagick_to_png($type,$data);
  }
  if ($self->{'verbose'} >= 2) {
    print "icon for Face ",length($data)," bytes\n";
  }
  if (length($data) > 16384) {
    if ($self->{'verbose'} >= 2) {
      print "ignore icon too big\n";
    }
    return;
  }

  require MIME::Base64;
  $data = MIME::Base64::encode_base64($data);
  ### $data
  return $data;
}

# sub image_size {
#   if (eval { require Image::ExifTool }) {
#   } elsif (eval { require Image::Magick }) {
# }

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
    print "  imagemagick doesn't like icon data: $ret\n";
    return;
  }
  return $image;
}

sub imagemagick_to_x_face {
  my ($self, $type, $data) = @_;
  eval { require Image::XFace } or return;
  ### $type
  my $image = $self->imagemagick_from_data($type,$data) // return;
  return;
}

sub imagemagick_to_png {
  my ($self, $type, $data) = @_;
  ### $type
  my $image = $self->imagemagick_from_data($type,$data) // return;

  my $width = $image->Get('width');
  my $height = $image->Get('height');
  ### compress: $image->Get('compression')
  if ($self->{'verbose'} >= 2) {
    print "icon ${width}x${height}\n";
  }
  if ($width == 0 || $height == 0) {
    return;
  }
  if ($width <= 48 && $height <= 48 && $type eq 'png') {
    return $data;
  }

  if ($width > 48 || $height > 48) {
    my $factor;
    if ($width <= 2*48 && $height <= 2*48) {
      $factor = 0.5;
    } else {
      $factor = max (48 / $width, 48 / $height);
    }
    $width = POSIX::ceil ($width * $factor);
    $height = POSIX::ceil ($height * $factor);
    if ($self->{'verbose'} >= 2) {
      print "icon shrink by $factor to ${width}x${height}\n";
    }
    $image->Resize (width => $width, height => $height);
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


