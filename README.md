# MIDI::Guitar - Emulating plucked guitar

This module provides basic tools to generated MIDI for plucked string
guitar sounds.

    use MIDI::Guitar;

    my $opus = MIDI::Guitar->new();
    $opus->init( sig => '3/4', bpm => 160 );

    # A pluck pattern.
    my $p1 = $opus->pluck( '1 5:80',
                           '2 2-4:80',
                           '3 4-2:80' );

    # A strum pattern.
    my $s1 = $opus->strum( '1 3/6 6:90 1-5:80' );

    # Some chord shapes.
    my $Am = '0 0 2 2 1 0';
    my $E  = '0 2 2 1 0 0';
    my $C  = '0 3 2 0 1 0';

    $opus->play( $p1 => $Am );
    $opus->play( $p1 => $C  );
    $opus->play( $s1 => $E  );
    $opus->finish( file => 'x.midi' );

You can define play patterns (strum and pluck) and play sequence of
strings (chords) using these patterns. It sounds like a real plucked
instrument, which implies that strings keep sounding until played or
explicitly muted.

You can change tempo, slow down and accelerate.

Timing and volumes can be made varying for a more lively feeling.

## INSTALLATION

To install this module, run the following commands:

	perl Makefile.PL
	make
	make test
	make install

## SUPPORT AND DOCUMENTATION

Development of this module takes place on GitHub:
https://github.com/sciurius/perl-MIDI-Guitar.

You can find documentation for this module with the perldoc command.

    perldoc MIDI::Guitar

Please report any bugs or feature requests using the issue tracker on
GitHub.

## COPYRIGHT AND LICENCE

Copyright (C) 2020 Johan Vromans

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

