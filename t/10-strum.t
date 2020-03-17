#! perl

use strict;
use Test::More tests => 1;

use MIDI::Guitar;

my $opus = MIDI::Guitar->new;

my $strum = $opus->strum( '1 4/4 6:90 1-3:80' );

my $chord  = '0 3 2 0 1 0';

$opus->play( $strum => $chord );

$opus = $opus->finish;

my $ref = bless( {
  format => 1,
  ticks => 192,
  tracks => [
    bless( {
      events => [
        [ 'set_tempo',      0, 600000      ],
        [ 'time_signature', 0, 4, 2, 24, 8 ],
      ],
      type => 'MTrk',
    }, 'MIDI::Track' ),
    bless( {
      events => [
        [ 'track_name', 0, 'Guitar'  ],
        [ 'patch_change', 0, 0, 24   ],
	[ 'note_on',    0, 0, 40, 90 ],
	[ 'note_on',  192, 0, 64, 80 ],
	[ 'note_on',  192, 0, 60, 80 ],
	[ 'note_on',  192, 0, 55, 80 ],
	[ 'note_off', 192, 0, 40,  0 ],
	[ 'note_off',   0, 0, 55,  0 ],
	[ 'note_off',   0, 0, 60,  0 ],
	[ 'note_off',   0, 0, 64,  0 ],
      ],
      type => 'MTrk',
    }, 'MIDI::Track' ),
  ],
}, 'MIDI::Opus' );

is_deeply( $opus, $ref );
