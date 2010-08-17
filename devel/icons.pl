#!/usr/bin/perl -w

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

{
  require Image::Pngslimmer;
  open my $fh, '<', '/usr/share/icons/hicolor/48x48/apps/emacs.png' or die;
  my $bytes = do { local $/; <$fh> }; # slurp
  close $fh or die;
  ### before: length($bytes)
  $bytes = Image::Pngslimmer::zlibshrink($bytes);
  ### after: length($bytes)
  exit 0;
}


my $ua = LWP::UserAgent->new;
{
  my $self = bless({verbose=>2},'main');
  #my $url = 'file:///usr/share/emacs/22.3/etc/images/icons/emacs_32.png';
  # my $url = 'file:///tmp/x.jpg';
  #my $url = 'file:///usr/share/icons/hicolor/64x64/apps/xtide.png';
  my $url = 'file:///usr/share/icons/hicolor/48x48/apps/emacs.png';
  $self->download_face($url, 0, 0);
  exit 0;
}
{
  my $self = bless({verbose=>2},'main');
  my $url = "file://$ENV{HOME}/tux/web/ch"."art/index.html";
  my $resp = $ua->get($url);
  ### favicon: resp_favicon_uri($resp)
  ### face: $self->resp_face($resp)
  exit 0;
}

sub item_face {
  my ($self, $item) = @_;
  $self->{'get_face'} || return;
  my ($uri, $width, $height) = $self->item_image_uwh ($item)
    or return;
  $self->face_wh_ok ($width, $height) || return;
  return $self->download_face ($uri, $width, $height);
}

sub item_image_uwh {
  my ($self, $item) = @_;
  # RSS <image>
  #       <url>foo.png</url>
  #       <width>...</width>     optional
  #       <height>...</height>   optional
  #
  {
    my $image;
    if (($image = $item->first_child('image'))
        && is_non_empty(my $url = $image->first_child('url'))) {
      return (URI->new_abs ($url, $self->{'uri'}),
              $image->first_child_text('width') // 0,
              $image->first_child_text('height') // 0);
    }
  }

  # Atom <icon>foo.png</icon>    should be square
  # or   <logo>foo.png</logo>    bigger form, should be rectangle 2*K x K
  {
    my $url;
    if (is_non_empty($url = $item->first_child_text_trimmed('icon'))
        || is_non_empty($url = $item->first_child_text_trimmed('logo'))) {
      return (URI->new_abs ($url, $self->{'uri'}),
              0,  # no width known
              0); # no height known
    }
  }
  return;
}

sub resp_face {
  my ($self, $resp) = @_;
  $self->{'get_face'} || return;
  my ($uri) = resp_favicon_uri($resp) || return;
  return $self->download_face ($uri, 0, 0);
}

sub resp_favicon_uri {
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
  $p->parse ($resp->decoded_content (charset => 'none'));
  return $href && URI->new_abs ($href, $resp->request->uri);
}

sub face_wh_ok {
  my ($self, $width, $height) = @_;

  if ($width > 0 && $width > 2*$height) {
    # some obnoxious banner
    if ($self->{'verbose'} >= 2) {
      print __x("  icon some obnoxious banner ({width}x{height})\n",
                width => $width,
                height => $height);
    }
    return 0;
  }
  return 1;
}

sub download_face {
  my ($self, $url, $width, $height) = @_;

  require HTTP::Request;
  my $req = HTTP::Request->new (GET => $url);
  my $resp = $ua->request($req);

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

  my $data = $resp->decoded_content(charset=>'none');
  if ($type ne 'png'
      || $width == 0 || $height == 0
      || $width > 48 || $height > 48) {
    $data = $self->imagemagick_to_png($type,$data) // return;
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
  # $xface = Image::XFace::compface(@bits);
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


