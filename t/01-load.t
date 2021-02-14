#!perl -T

use Test::More tests => 2;

BEGIN {
	use_ok( 'MIDI::Guitar' );
	use_ok( 'MIDI::Percussion' );
}

diag( "Testing MIDI::Percussion $MIDI::Percussion::VERSION, Perl $], $^X" );
