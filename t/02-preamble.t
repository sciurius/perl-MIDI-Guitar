#! perl

use strict;
use Test::More tests => 1;

use MIDI::Guitar;

# No testing, so we'll get a preamble.
my $opus = MIDI::Guitar->new;

# Basically a trick to force content.
$opus->note( 0, 60, 100 );

$opus = $opus->finish;

my $ref = bless( {
  format => 1,
  ticks => 192,
  tracks => [
    bless( {
      events => [
	[ 'text_event', 0,
	  "Created by MIDI::Guitar version $MIDI::Guitar::VERSION" ],
	[ text_event => 0,
	  "https://github.com/sciurius/perl-MIDI-Guitar" ],
        [ 'set_tempo',      0, 600000      ],
        [ 'time_signature', 0, 4, 2, 24, 8 ],
      ],
      type => 'MTrk',
    }, 'MIDI::Track' ),
    bless( {
      events => [
        [ 'track_name', 0, 'Guitar'  ],
        [ 'patch_change', 0, 0, 24   ],
	[ 'note_on',    0, 0, 60, 100 ],
      ],
      type => 'MTrk',
    }, 'MIDI::Track' ),
  ],
}, 'MIDI::Opus' );

is_deeply( $opus, $ref );
