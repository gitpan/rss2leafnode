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
use XML::Liberal;
use XML::LibXML;
use File::Slurp;

use FindBin;
my $progname = $FindBin::Script;

# my $filename = $FindBin::Dir . '../samp/closing_commentary--2.rss';
# print "$filename\n";
# my $xml = read_file($filename);

my $xml = <<'HERE';
<?xml version="1.0" encoding="ISO-8859-1" ?>
<rss version="2.0">
 <channel>
  <item>
   <title>S&P 500</title>
   <description>Blah</description>
  </item>
 </channel>
</rss>
HERE


#my $parser = XML::LibXML->new;
my $parser = XML::Liberal->new('LibXML');
my $doc = eval { $parser->parse_string($xml) };
print $doc,"\n";
if ($doc) {
  print $doc->toString;

  $xml = $doc->toString;
  $parser = XML::LibXML->new;
  $doc = eval { $parser->parse_string($xml) };
  print $doc,"\n";
}
