#!/usr/bin/perl

# Example of playing TAB data.

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../lib";
use MIDI::Guitar;

my $opus = MIDI::Guitar->new( signature => '4/4',
			      tempo     => 80,
			      midi      => 'stairway.midi' );

# The tab is downloaded from one of the many internet sites that have
# all kinds of tabs. Since there are many forms of guitar tabs, and
# our idea of tabs is currently a bit limited, we need to transform
# the downloaded tab into a more suitable format.

sub xp($) {
    my ( $t ) = @_;
    # Replace leading string names by a bar.
    $t =~ s;^[EADGB]-;|-;igm;
    # This tab has a leading - after each bar. Strip it.
    $t =~ s;\|-;|;g;
    # Strip pulls and hammers until we know how to handle.
    $t =~ s;[/^];-;g;
    return $t
}

$opus->tab( 4, xp <<EOD );
E-------5-7-----7-|-8-----8-2-----2-|-0---------0-----|-----------------|
B-----5-----5-----|---5-------3-----|---1---1-----1---|---1-1-----------|
G---5---------5---|-----5-------2---|-----2---------2-|-0-2-2-----------|
D-7-------6-------|-5-------4-------|-3---------------|-----------------|
A-----------------|-----------------|-----------------|-2-0-0---0--/8-7-|
E-----------------|-----------------|-----------------|-----------------|
EOD

$opus->tab( 4, xp <<EOD );
E---------7-----7-|-8-----8-2-----2-|-0---------0-----|-----------------|
B-------5---5-----|---5-------3-----|---1---1-----1---|---1-1-----------|
G-----5-------5---|-----5-------2---|-----2---------2-|-0-2-2-----------|
D---7-----6-------|-5-------4-------|-3---------------|-----------------|
A-0---------------|-----------------|-----------------|-2-0-0-------0-2-|
E-----------------|-----------------|-----------------|-----------------|
EOD

$opus->tab( 4, xp <<EOD );
E-------0-2-----2-|-0-----0---------|---------3-----3-|-3^2-2-2---------|
B-----------3-----|---1-----0-------|-1-----1---0-----|-----3-3---------|
G-----0-------2---|-----2-----2-----|---0---------0---|-----------------|
D---2-----0-------|-3---------------|-----2-----------|-0---0-0---------|
A-3---------------|---------0---0-2-|-3---------------|-------------0-2-|
E-----------------|-----------------|---------3-------|-----------------|
EOD

$opus->tab( 4, xp <<EOD );
E---------2-----2-|-0-----0---------|---------------2-|-0-0-0-----------|
B-------1---3-----|---1-----0-------|-------1-----3---|-1-1-1-----------|
G-----0-------2---|-----2-----2-----|-----0-----2-----|-2-2-2-----------|
D---2-----0-------|-3---------------|---2-----0-------|-3-3-3-----------|
A-3---------------|---------0---0-2-|-3---------------|-----------------|
E-----------------|-----------------|-----------------|-----------------|
EOD

# Let the strings sounds decay. 'play' without arguments is a measure
# of nothing.
$opus->play;
$opus->play;

# Finish and write the MIDI file.
# This is not really needed since it will be done implicitly when the
# opus object is destroyed.
# $opus->finish;

