#! perl

use strict;
use Test::More tests => 1;

use MIDI::Percussion;

my $opus = MIDI::Percussion->new( testing     => 1,
				  signature   => '4/4',
				  tempo       => 80,
				  instruments =>
				  [ "Closed Hi-Hat",
				    "Pedal Hi-Hat",
				    "Crash Cymbal 1",
				    "Acoustic Bass Drum",
				  ] );

# Tabs have teen tested in t/30*.t.
$opus->tab( <<EOD );
Cl HH |---7--7-7-7-7---|-7-7--7-7-7-7-7-|-7-7--7-7-7-7-7-|-7-7--7-7-7-7-7-|
Pd HH |--------------7-|----------------|----------------|----------------|
Crash |-7--------------|----------------|----------------|----------------|
Kick  |7---------------|7---------------|7---------------|7---------------|
EOD

$opus = $opus->finish;		# returns MIDI structure.

# $opus->dump( { dump_tracks => 1, flat => 0 } );

my $ref = bless( {
  'format' => 1,
  'ticks'  => 192,
  'tracks' => [   # 2 tracks...
    # Track #0 ...
    MIDI::Track->new({
      'type' => 'MTrk',
      'events' => [  # 2 events.
        ['set_tempo', 0, 750000],
        ['time_signature', 0, 4, 2, 24, 8],
      ]
    }),

    # Track #1 ...
    MIDI::Track->new({
      'type' => 'MTrk',
      'events' => [  # 34 events.
        ['track_name', 0, 'Percussion'],
        ['patch_change', 0, 9, 0],
        ['note_on', 0, 9, 35, 77],
        ['note_on', 48, 9, 49, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 144, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 44, 77],
        ['note_on', 96, 9, 35, 77],
        ['note_on', 48, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 144, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 35, 77],
        ['note_on', 48, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 144, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 35, 77],
        ['note_on', 48, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 144, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
        ['note_on', 96, 9, 42, 77],
      ]
    }),
  ]
}, 'MIDI::Opus' );

is_deeply( $opus, $ref );
