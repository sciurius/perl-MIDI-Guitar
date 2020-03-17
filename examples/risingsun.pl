#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";
use MIDI::Guitar;

=for doc

  This example plays the strum pattern made eternally famous 55 years
  ago by the Animals in their version of The House Of The Rising Sun.

  When you play the midi file you'll hear the first 16 bars of the
  song. The rest of the song is just repeating these 16 bars.

=cut

my $opus = MIDI::Guitar->new( sig   => '6/8',
			      bpm   => 240,
			      instr => 'Electric Guitar(clean)',
			      rtime =>  10,
			      rvol  =>   5,
			      midi  => 'risingsun.midi' );

# Chord shapes.
my $Am = '0 0 2 2 1 0';
my $C  = '0 3 2 0 1 0';
my $D  = '- - 0 2 3 2';
my $F  = '1 3 3 2 1 1';
my $E  = '0 2 2 1 0 0';

# Patterns.
# Bass on the A string.
# Note we need to mute the other bass strings to prevent them from
# sounding through the new chord.
# Note that we use imprecise timings so we need pluck, not strum.
my $pA = $opus->pluck( '1.0  5:90  4,6:0',
		       '2.1  4:80',
		       '2.8  3:80',
		       '3.2  2:80',
		       '4.0  1:90',
		       '5.0  2:80',
		       '6.0  3:80' );

# Bass on the D string.
my $pD = $opus->pluck( '1.0  4:90  5,6:0',
		       '2.1  4:80',
		       '2.8  3:80',
		       '3.2  2:80',
		       '4.0  1:90',
		       '5.0  2:80',
		       '6.0  3:80' );

# Bass on the (lower) E string.
my $pE = $opus->pluck( '1.0  6:90  4,5:0',
		       '2.1  4:80',
		       '2.8  3:80',
		       '3.2  2:80',
		       '4.0  1:90',
		       '5.0  2:80',
		       '6.0  3:80' );

# And play...
$opus->play( $pA => $Am );
$opus->play( $pA => $C  );
$opus->play( $pD => $D  );
$opus->play( $pD => $F  );

$opus->play( $pA => $Am );
$opus->play( $pA => $C  );
$opus->play( $pE => $E  );
$opus->play( $pE => $E  );

$opus->play( $pA => $Am );
$opus->play( $pA => $C  );
$opus->play( $pD => $D  );
$opus->play( $pD => $F  );

$opus->play( $pA => $Am );
$opus->play( $pE => $E  );
$opus->play( $pA => $Am );
$opus->play( $pE => $E  );

# Let the strings sounds decay. 'play' without arguments is a measure
# of nothing.
$opus->play;
$opus->play;

# Finish and write the MIDI file.
# This is not really needed since it will be done implicitly when the
# opus object is destroyed.
$opus->finish;

