#!/usr/bin/perl

# Example of playing drums. Really.

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";
use MIDI::Percussion;

my $opus = MIDI::Percussion->new( signature   => '4/4',
				  tempo       => 80,
				  instruments =>
				  [ "Closed Hi-Hat",
				    "Pedal Hi-Hat",
				    "Crash Cymbal 1",
				    "Acoustic Bass Drum",
				  ],
				  midi => 'drums2.midi' );

$opus->tab( <<EOD );
Cl HH |---7--7-7-7-7---|-7-7--7-7-7-7-7-|-7-7--7-7-7-7-7-|-7-7--7-7-7-7-7-|
Pd HH |--------------7-|----------------|----------------|----------------|
Crash |-7--------------|----------------|----------------|----------------|
Kick  |7---------------|7---------------|7---------------|7---------------|
EOD

# Let the strings sounds decay. 'play' without arguments is a measure
# of nothing.
$opus->play;
$opus->play;

# Finish and write the MIDI file.
# This is not really needed since it will be done implicitly when the
# opus object is destroyed.
# $opus->finish;
