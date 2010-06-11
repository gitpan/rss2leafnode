#!/usr/bin/perl

# Copyright 2010 Kevin Ryde

# This file is part of Gtk2-Ex-Clock.
#
# Gtk2-Ex-Clock is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 3, or (at your option) any
# later version.
#
# Gtk2-Ex-Clock is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
# Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Gtk2-Ex-Clock.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use App::RSS2Leafnode;
use Test::More;

use lib 't';
use MyTestHelpers;
use Test::Weaken::ExtraBits;

my $have_test_weaken = eval "use Test::Weaken 2.000; 1";
if (! $have_test_weaken) {
  plan skip_all => "due to Test::Weaken 2.000 not available -- $@";
}
plan tests => 2;

diag ("Test::Weaken version ", Test::Weaken->VERSION);


#-----------------------------------------------------------------------------

{
  my $leaks = Test::Weaken::leaks
    ({ constructor => sub { return App::RSS2Leafnode->new },
     });
  is ($leaks, undef, 'deep garbage collection -- new()');
}

{
  my $leaks = Test::Weaken::leaks
    ({ constructor => sub {
         my $r2l = App::RSS2Leafnode->new;
         my $ua = $r2l->ua;
         return [ $r2l, $ua ];
       },
       # handler funcs set in ua()
       ignore => \&Test::Weaken::ExtraBits::ignore_global_function,
     });
  is ($leaks, undef, 'deep garbage collection -- new() and ua()');

  if ($leaks) {
    if (defined &explain) { diag "Test-Weaken ", explain $leaks; }
    my $unfreed = $leaks->unfreed_proberefs;
    foreach my $proberef (@$unfreed) {
      diag "  unfreed $proberef";
    }
    foreach my $proberef (@$unfreed) {
      diag "  search $proberef";
      MyTestHelpers::findrefs($proberef);
    }
  }
}

exit 0;
