#!/usr/bin/perl

# Copyright 2008, 2009, 2010 Kevin Ryde

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
# You can get a copy of the GNU General Public License online at
# http://www.gnu.org/licenses.

use strict;
use warnings;
use News::Rnews;
use Test::More tests => 5;

SKIP: { eval 'use Test::NoWarnings; 1'
          or skip 'Test::NoWarnings not available', 1; }


my $want_version = 21;
is ($News::Rnews::VERSION, $want_version, 'VERSION variable');
is (News::Rnews->VERSION,  $want_version, 'VERSION class method');
{ ok (eval { News::Rnews->VERSION($want_version); 1 },
      "VERSION class check $want_version");
  my $check_version = $want_version + 1000;
  ok (! eval { News::Rnews->VERSION($check_version); 1 },
      "VERSION class check $check_version");
}

exit 0;
