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

use 5.010;
use strict;
use warnings;

{
  require Sort::Key::Top;
  say Sort::Key::Top::rkeytop(sub{$_}, 3,  1,5,2,4,3,6);
  say Sort::Key::Top::rkeytop(sub{1}, 3,  1,5,2,4,3,6);
  say Sort::Key::Top::keytop(sub{1}, 3,  1,5,2,4,3,6);
  exit 0;
}

{
  require HTML::Entities::Interpolate;
  print $HTML::Entities::Interpolate::Entitize{"abc\n"};
  print $HTML::Entities::Interpolate::Entitize{"%$&<>\n"};
  exit 0;
}