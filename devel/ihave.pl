#!/usr/bin/perl

# Copyright 2008, 2010 Kevin Ryde
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

use 5.010;
use strict;
use warnings;
use Net::NNTP;

{
  require URI;
  my $uri = URI->new ('r2l.test','news');
   $uri = URI->new ('news://foo.com/r2l.test','news');
   $uri = URI->new ('http://foo.com/r2l.test','news');
  print ref($uri),"\n";
  print $uri,"\n";
  print "scheme: ",$uri->scheme,"\n";
  print "host:   ",$uri->host//'undef',"\n";
  print "group:  ",$uri->group//'undef',"\n";
  print "path:   ",$uri->path//'undef',"\n";
  exit 0;
}

{
  my $nntp = Net::NNTP->new ('localhost', Debug => 1);
  #print $nntp->ihave('fsjdkfds'),"\n";

  print $nntp->postok(),"\n";

  print $nntp->post(),"\n";
}
