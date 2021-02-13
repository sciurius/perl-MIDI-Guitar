#!/usr/bin/perl

# Example of playing drums. Really.

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";
use MIDI::Guitar;

my $opus = MIDI::Guitar->new( signature  => '4/4',
			      tempo      => 80,
			      channel    => 9,
			      instrument => 0, # "Standard Drum Kit",
			      strings =>
			      [ "Low Tom",
				"Low-Mid Tom",
				"High Tom",
				"Ride Cymbal 1",
				"Crash Cymbal 1",
				"Pedal Hi-Hat",
				"Closed Hi-Hat",
				"Acoustic Snare",
				"Acoustic Bass Drum",
			      ],
			      midi => 'drums.midi' );

my $p = $opus->pluck( '1.0  1:90 5:50',
		      '1.5  3:70',
		      '2.0  3:70',
		      '2.5  3:90',
		      '3.0  3:70',
		      '3.5  3:70',
		      '4.0  3:70',
		      '4.5  3:70' );

my $c = "@{[(0) x 9]}";

$opus->play( $p => $c );
$opus->play( $p => $c );

#$opus->tab( 4, xp(<<EOD) );
#AB 0---------------|0---------------|0---------------|0---------------|
#AS ----------------|----------------|----------------|----------------|
#CH ---0--0-0-0-0---|-0-0--0-0-0-0-0-|-0-0--0-0-0-0-0-|-0-0--0-0-0-0-0-|
#PH --------------0-|----------------|----------------|----------------|
#CC -0--------------|----------------|----------------|----------------|
#RC ----------------|----------------|----------------|----------------|
#HT ----------------|----------------|----------------|----------------|
#MT ----------------|----------------|----------------|----------------|
#LT ----------------|----------------|----------------|----------------|
#EOD


# Let the strings sounds decay. 'play' without arguments is a measure
# of nothing.
$opus->play;
$opus->play;

# Finish and write the MIDI file.
# This is not really needed since it will be done implicitly when the
# opus object is destroyed.
# $opus->finish;

sub xp {
    my ( $t ) = @_;
    # Replace leading names by a bar.
    $t =~ s;^.. ;|;igm;
    # Replace anything not |- by -.
    $t =~ s;[^-|\n\r];-;igm;
    return $t
}
