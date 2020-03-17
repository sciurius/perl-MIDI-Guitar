#! perl

use strict;
use Test::More tests => 1;

use MIDI::Guitar;

my $opus = MIDI::Guitar->new;

my $strum = $opus->strum( '1 4/4 6:90 1-3:80' );

my $chord  = '0 3 2 0 1 0';

$opus->play( $strum => $chord );
$opus->rit( 0.6, 2 );
$opus->play( $strum => $chord );
$opus->play( $strum => $chord );
$opus->play( $strum => $chord );

$opus = $opus->finish;

my $ref = bless( {
  format => 1,
  ticks => 192,
  tracks => [
    bless( {
      events => [
        [ 'set_tempo',      0,  600000     ],
        [ 'time_signature', 0, 4, 2, 24, 8 ],
	[ 'set_tempo',    768,  631578     ],
        [ 'set_tempo',    192,  666666     ],
        [ 'set_tempo',    192,  705882     ],
        [ 'set_tempo',    192,  750000     ],
        [ 'set_tempo',    192,  800000     ],
        [ 'set_tempo',    192,  857142     ],
        [ 'set_tempo',    192,  923076     ],
        [ 'set_tempo',    192, 1000000     ],
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
        [ 'note_on',    0, 0, 40, 90 ],
        [ 'note_off', 192, 0, 64,  0 ],
        [ 'note_on',    0, 0, 64, 80 ],
        [ 'note_off', 192, 0, 60,  0 ],
        [ 'note_on',    0, 0, 60, 80 ],
        [ 'note_off', 192, 0, 55,  0 ],
        [ 'note_on',    0, 0, 55, 80 ],
        [ 'note_off', 192, 0, 40,  0 ],
        [ 'note_on',    0, 0, 40, 90 ],
        [ 'note_off', 192, 0, 64,  0 ],
        [ 'note_on',    0, 0, 64, 80 ],
        [ 'note_off', 192, 0, 60,  0 ],
        [ 'note_on',    0, 0, 60, 80 ],
        [ 'note_off', 192, 0, 55,  0 ],
        [ 'note_on',    0, 0, 55, 80 ],
        [ 'note_off', 192, 0, 40,  0 ],
        [ 'note_on',    0, 0, 40, 90 ],
        [ 'note_off', 192, 0, 64,  0 ],
        [ 'note_on',    0, 0, 64, 80 ],
        [ 'note_off', 192, 0, 60,  0 ],
        [ 'note_on',    0, 0, 60, 80 ],
        [ 'note_off', 192, 0, 55,  0 ],
        [ 'note_on',    0, 0, 55, 80 ],
        [ 'note_off', 192, 0, 40,  0 ],
        [ 'note_off',   0, 0, 55,  0 ],
        [ 'note_off',   0, 0, 60,  0 ],
        [ 'note_off',   0, 0, 64,  0 ],
      ], type => 'MTrk',
    }, 'MIDI::Track' ),
  ],
}, 'MIDI::Opus' );

is_deeply( $opus, $ref );
