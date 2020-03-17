#! perl

use strict;
use Test::More tests => 1;

use MIDI::Guitar;

my $opus = MIDI::Guitar->new;

$opus->tab( 4, <<EOD );
|------5-7-----7-|
|----5-----5-----|
|--5---------5---|
|7-------6-------|
|----------------|
|----------------|
EOD

$opus = $opus->finish;		# returns MIDI structure.

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
	[ 'track_name', 0, 'Guitar' ],
	[ 'patch_change', 0, 0, 24  ],
	[ 'note_on',   0, 0, 57, 80 ],
	[ 'note_on',  96, 0, 60, 80 ],
	[ 'note_on',  96, 0, 64, 80 ],
	[ 'note_on',  96, 0, 69, 80 ],
	[ 'note_off', 96, 0, 69,  0 ],
	[ 'note_on',   0, 0, 71, 80 ],
	[ 'note_off',  0, 0, 57,  0 ],
	[ 'note_on',   0, 0, 56, 80 ],
	[ 'note_off', 96, 0, 64,  0 ],
	[ 'note_on',   0, 0, 64, 80 ],
	[ 'note_off', 96, 0, 60,  0 ],
	[ 'note_on',   0, 0, 60, 80 ],
	[ 'note_off', 96, 0, 71,  0 ],
	[ 'note_on',   0, 0, 71, 80 ],
	[ 'note_off', 96, 0, 56,  0 ],
	[ 'note_off',  0, 0, 60,  0 ],
	[ 'note_off',  0, 0, 64,  0 ],
	[ 'note_off',  0, 0, 71,  0 ],
      ],
      type => 'MTrk',
    }, 'MIDI::Track' ),
  ],
}, 'MIDI::Opus' );

is_deeply( $opus, $ref );
