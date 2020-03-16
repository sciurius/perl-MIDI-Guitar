#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'MIDI::Guitar' );
}

diag( "Testing MIDI::Guitar $MIDI::Guitar::VERSION, Perl $], $^X" );
