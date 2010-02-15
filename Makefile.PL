#!/usr/bin/perl

# Copyright 2007, 2008, 2009, 2010 Kevin Ryde

# This file is part of RSS2Leafnode.
#
# RSS2Leafnode is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published
# by the Free Software Foundation; either version 3, or (at your option) any
# later version.
#
# RSS2Leafnode is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
# Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with RSS2Leafnode.  If not, see <http://www.gnu.org/licenses/>.

use 5.010;
use strict;
use warnings;
use ExtUtils::MakeMaker;

use lib 'inc';
use MyMakeMakerExtras;
use MyMakeMakerGettext;

MyMakeMakerExtras::WriteMakefile
  (NAME         => 'rss2leafnode',
   ABSTRACT     => 'Download RSS feeds into Leafnode news.',
   VERSION_FROM => 'lib/App/RSS2Leafnode.pm',
   AUTHOR       => 'Kevin Ryde <user42@zip.com.au>',
   LICENSE      => 'gpl',
   SIGN         => 1,
   EXE_FILES    => [ 'rss2leafnode' ],
   MIN_PERL_VERSION => '5.010',

   clean     => { FILES => '$(POT_TEMP_FILE)' # if bad xgettext
                },

   PREREQ_PM    => {
                    'XML::Twig' => 0,

                    # LWP 5.832 for content_charset()
                    'LWP' => '5.832',
                    # 'LWP::Debug' => 0,
                    'LWP::UserAgent' => 0,
                    'HTTP::Message' => 0,
                    'HTTP::Request' => 0,
                    'HTTP::Response' => 0,

                    # maybe URI 1.13 circa 2001 for dotted ipv6 support, if
                    # using that
                    'URI' => 0,
                    'URI::Escape' => 0,
                    'URI::tag' => 0, # for hostname of atom <id>s

                    # MIME-Tools
                    'MIME::Entity' => 0,
                    'MIME::Tools' => 0,
                    'MIME::Words' => 0,

                    # this is required by MIME-Tools anyway
                    'Date::Parse' => 0,

                    'HTML::FormatText' => 0,
                    'List::MoreUtils' => 0,
                    'Scope::Guard' => 0,
                    'File::HomeDir' => 0,
                    'Locale::TextDomain' => 0,
                   },

   META_MERGE
   => { resources
        => { homepage
             => 'http://user42.tuxfamily.org/rss2leafnode/index.html',
           },
        optional_features
        => { xml_rss_timing
             => { description => 'Check RSS feed advertised update times before redownloading.',
                  requires => { 'XML::RSS::Timing' => 0 },
                },
             xml_rss_timing_print
             => { description => 'A prettier print of time to next RSS update.',
                  requires => { 'Time::Duration' => 0 },
                },
             xml_rss_timing_print_locale
             => { description => 'A prettier print of time to next RSS update, with language-specific print.',
                  requires => { 'Time::Duration::Locale' => 0,
                                'Time::Duration::ja'     => 0,
                                'Time::Duration::sv'     => 0,
                              },
                },

             render_text_with_links
             => { description => 'Optionally render HTML to text using FormatText::WithLinks.',
                  requires => { 'HTML::FormatText::WithLinks' => 0 },
                },
             render_text_external
             => { description => 'Optionally render HTML to text using external programs like lynx.',
                  requires => { 'HTML::FormatExternal' => 0 },
                },

             fetch_html_uri_title
             => { description => ' A better Subject for fetch_html() messages using URI::Title.',
                  requires => { 'URI::Title' => 0 },
                },

             maximum_tests
             => { description => 'Have "make test" do as much as possible.',
                  requires => { 'Test::NoWarnings' => 0,
                                'URI::Title' => 0,
                              },
                },
             maximum_devel
             => { description => 'Stuff used variously for development.',
                  requires => { 'XML::Atom' => 0,
                                'XML::LibXML' => 0,
                                'XML::Atom::Feed' => 0,
                                'XML::RSS' => 0,
                                'XML::RSS::LibXML' => 0,
                                'Perl6::Slurp' => 0,
                                'URI::file' => 0, # part of URI
                                'URI::Title' => 0,
                                'HTML::TreeBuilder' => 0,
                                'HTML::FormatText' => 0,
                                'HTML::Entities' => 0,
                                'DateTime' => 0,
                                'DateTime::Format::Mail' => 0,
                              },
                },
           },
      },
  );


#------------------------------------------------------------------------------
package MY;
sub postamble {
  my ($makemaker) = @_;
  $makemaker->{'PO_DOMAIN'} = 'App-RSS2Leafnode';
  return
    MyMakeMakerExtras::postamble($makemaker)
        . MyMakeMakerGettext::postamble($makemaker);
}