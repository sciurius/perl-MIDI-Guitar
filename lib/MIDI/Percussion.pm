#! perl

package MIDI::Percussion;

use warnings;
use strict;
use parent qw( MIDI::Guitar );

=head1 NAME

MIDI::Percussion - MIDI Percussion

=cut

our $VERSION = '0.05';

=head1 SYNOPSIS

This module provides basic tools to generated MIDI for percussion.

    use MIDI::Percussion;

    my $opus = MIDI::Percussion->new( sig  => '4/4',
				      bpm  => 80,
				      instr =>
				      [ "Closed Hi-Hat",
					"Pedal Hi-Hat",
					"Crash Cymbal 1",
					"Acoustic Bass Drum",
				      ],
				      midi => 'd.midi' );

    $opus->tab( <<EOD );
    Cl HH |---7--7-7-7-7---|-7-7--7-7-7-7-7-|-7-7--7-7-7-7-7-|-7-7--7-7-7-7-7-|
    Pd HH |--------------7-|----------------|----------------|----------------|
    Crash |-7--------------|----------------|----------------|----------------|
    Kick  |7---------------|7---------------|7---------------|7---------------|
    EOD

    $opus->finish;

=cut

use Carp;

=head1 METHODS

=head2 $opus = MIDI::Percussion->new( %args )

Creates a new MIDI::Percussion instance, supplies default values, and
initialises it with the arguments, if any.

Possible arguments are:

=over

=item name

The MIDI track name.

=item sig

Time signature. This should be a fraction where the denominator is a
power of 2, e.g. C<4/4> or C<6/8>.

Default is C<4/4>.

=item bpm

Beats per minute.

Default is C<100>.

=item kit

Drum kit selection. 0 = Standard Drum Kit.

=item instr

An array reference with instrument names.

There is no default.

Note: There can be any number of instruments.

=item rtime

Time randomizer. Suitable values are 0 .. 10.

=item rvol

Volume randomizer. Suitable values are 0 .. 6.

=item lead

Lead-in and metronome ticks.

If zero, or greater than zero, a metronome tick in included in the MIDI.

A greater than zero value specifies the number of lead-in bars.

TODO A negative value yields lead-in bars but no metronome.

=item midi

The name of the MIDI file to be produced.

=back

=cut

sub new {
    my $pkg = shift;
    my $self = bless {} => $pkg;
    my %opts = ( @_ );

    # Defaults.
    my %args = ( name    => "Percussion",
		 chan    => 9,
		 sig     => '4/4',
		 bpm     => 100,
		 instr   => 0,
		 strings => [ "Closed Hi-Hat",
			      "Pedal Hi-Hat",
			      "Crash Cymbal 1",
			      "Acoustic Bass Drum",
			    ],
		 volume  => 1,
	       );

    $args{instr} = delete $opts{kit} if defined $opts{kit};
    $args{strings} = delete $opts{instr};
    $self->_init( %args, %opts );
    return $self;
}

=head2 $opus->tab( $measures, $data )

WARNING: Experimental method. API is likely to change.

Plays I<measures> of tablature I<data>.

Support is still very basic, but interestingly functional.

For example:

    $opus->tab( <<EOD );
    Cl HH  |----5-----5-----|--5-------3-----|--1---1-----1---|--1-1-----------|
    Ped HH |--5---------5---|----5-------2---|----2---------2-|0-2-2-----------|
    Crash  |7-------6-------|5-------4-------|3---------------|----------------|
    Kick   |----------------|----------------|----------------|----------------|
    EOD

Note: Each line B<must> contain a series of dashes and numbers between
vertical bars (a measure). Multiple measures may be specified adjacent
to another. Each measure B<should> contain a number of characters equal to
an integer multiple of the beats per measure.

    |5|             5 on one
    |54|            5 on one, 4 on three
    |5444|          5 on one, 4 on two, three, four
    |5-4-4-4-|      same
    |5--4--4--4--|  same
    |5--4--4--444|  same, with triplet on four

The numbers denote the force with which the instrument will be hit.
Zero = mute, 9 = loudest.

The instrument mnemonics are optional and have no relation with the
actual instruments used. The instruments are defined top to bottom by
the C<strings> argument abome.

Returns itself.

=cut

sub tab {
    my ( $self, $tab ) = @_;

    my @args = split( /\s*[\n\r]\s*/, $tab );
    croak("Number of tab lines must be ", scalar(@{ $self->{root} }) )
      unless @args == @{ $self->{root} };

    my $i = 0;
    for ( @args ) {
	if ( /(\|(?:[-\d]+\|)+)$/ ) {
	    $_ = $1;
	}
	else {
	    croak("Tab format error[$i]: $_")
	}
	$i++;
    }

    my $cclock = $self->{clock};

    my $step;
    while ( $args[0] ) {
	my $vel = 100;

	# Randomize clock time and volume.
	my $dv = 0;
	$dv = ( 1 - rand(2) ) * $self->{rvol} if $self->{rvol};
	my $dc = 0;
	$dc = ( 1 - rand(2) ) * $self->{rtime} if $self->{rtime};
	$dc = 0 if $dc + $cclock <= 0;

	my $bar = 0;
	for ( my $s = 0; $s < @{ $self->{root} }; $s++ ) {
	    my $c = substr( $args[$s], 0, 1, '' );
	    if ( $c eq '|' ) {
		if ( $s == 0 ) {
		    if ( $args[0] && $args[0] =~ /^([-\d]+)\|/ ) {
			$step = length($1);
			croak("Strange measure size $step: $args[0]")
			  unless $self->{ticks}/$step == int($self->{ticks}/$step);
			$step = $self->{ticks} / $step * $self->{bpm};
		    }
		    $bar++;
		    $cclock -= $step;
		    next;
		}
		elsif ( $bar ) {
		    next;
		}
		else {
		    delete( $self->{events} ); # prevent destroy finish
		    croak("Tab format error[$s]: $c$args[$s]");
		}
	    }
	    next if $c eq '-';
	    my $str = @{ $self->{root} } - $s - 1;
	    my $note = $self->{root}->[$str];
	    #if ( $self->{sounding}->[$str] ) {
	    #	$self->note( $cclock+$dc, $self->{sounding}->[$str], 0 );
	    #}
	    my $vel = int( $vel * $c/9 );
	    $self->note( $cclock+$dc, $note,
		  $vel > $self->{rvol} ? $vel + $dv : $vel );
	    $self->{sounding}->[$str] = $vel ? $note : 0;
	}
	$cclock += $step;
    }

    $self->{clock} = $cclock;

    return $self;
}

=head1 SEE ALSO

L<MIDI>, L<MIDI::Guitar>.

=head1 COPYRIGHT & LICENSE

Copyright 2020 Johan Vromans, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of MIDI::Guitar
