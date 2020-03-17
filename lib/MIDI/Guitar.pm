#! perl

package MIDI::Guitar;

use warnings;
use strict;

=head1 NAME

MIDI::Guitar - Plucked guitar MIDI

=cut

our $VERSION = '0.02';

=head1 SYNOPSIS

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

Interesting features:

=over 4

=item *

Randomisation to make the sound more realistic.

=item *

Tempo changes, including gradual changes over multiple measures (ritardante).

=item *

Volume changes, including gradual changes over multiple measures (de/crescendo).

=item *

Playback from ASCII guitar tablature.

=back

=cut

use Carp;
use MIDI;

# These are valid for all events.
use constant EV_TYPE	     => 0;
use constant EV_TIME	     => 1;
# These are for events that apply to a channel only.
use constant EV_CHAN	     => 2;
# These are for note events.
use constant EV_NOTE_PITCH   => 3;
use constant EV_NOTE_VELO    => 4;
# These if for track_name events.
use constant EV_MARKER_NAME  => 2;

# Drum channel
use constant MIDI_CHAN_PERCUSSION => 10;

# Instance variables.
#
# $bpm;				# beats per measure
# $q;				# beat note ( 4 = quarter )
# $bpmin;			# beats per minute (actual)
# $bpmin0;			# beats per minute (initial)
# $tpb;				# ticks per beat;
# $patch;			# instrument
# $rtime;			# time randomizer
# $rvol;			# volume randomizer
# $lead;			# lead in ticks

# MIDI parameters.
#
# $chan;			# MIDI channel
# $ticks;			# MIDI ticks
# $clock;			# current
# $cskip;			# skip metro on sound out
# @events;			# events for main track
# @root;			# root notes for strings
# @sounding;			# strings that sound

=head1 METHODS

=head2 $opus = MIDI::Guitar->new( %args )

Creates a new MIDI::Guitar instance, supplies default values, and
initialises it with the arguments, if any. This is identical to

    $opus = MIDI::Guitar->new;
    $opus->init( %args );

=cut

sub new {
    my $pkg = shift;
    my $self = bless {} => $pkg;

    # Hardwired for now.
    $self->{chan} = 0;

    # Defaults.
    my %args = ( sig     => '4/4',
		 bpm     => 100,
		 instr   => 'Acoustic Guitar(nylon)',
		 strings => 'E2 A2 D3 G3 B3 E4',
		 volume  => 1,
	       );
    $self->init( %args, @_);
    return $self;
}


=head2 $opus->init( %args )

Initialises a new instance. Possible arguments are:

=over

=item sig

Time signature. This should be a fraction where the denominator is a
power of 2, e.g. C<4/4> or C<6/8>.

Default is C<4/4>.

=item bpm

Beats per minute.

Default is C<100>.

=item instr

MIDI instrument name. See L<MIDI> for a list of instrument names.

Default is C<Acoustic Guitar(nylon)>.

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

sub init {
    my $self = shift;
    my %args = ( @_ );

    # Time signature.
    croak("Invalid time signature: $args{sig}")
      unless $args{sig} =~ m;^(\d+)/(\d)$;;
    $self->{bpm} = $1;
    $self->{q} = $2;

    # Beats per minutes.
    $self->{bpmin} = $self->{bpmin0} = 0+$args{bpm};

    # Instrument. Patch name.
    $self->{patch} = $args{instr};
    $self->{patch} = $MIDI::patch2number{$self->{patch}} ||
      croak("Unknown MIDI instrument: $args{instr}");

    # Volume.
    $self->{volume} = $args{volume} || 1;

    # Randomizers.
    $self->{rtime} = $args{rtime} || 0;
    $self->{rvol}  = $args{rvol}  || 0;

    $self->{clock} = 0;
    $self->{ticks} = 192;
    $self->{tpb} = $self->{ticks};

    $self->{lead} = $args{lead};
    if ( defined $self->{lead} && $self->{lead} ) {
	$self->{clock} += abs($self->{lead}) * $self->{tpb};
    }
    $self->{cskip} = 0;
    @{ $self->{root} } = map { 12+$MIDI::note2number{$_} } split( ' ', $args{strings} );
    @{ $self->{sounding} } = (0) x @{ $self->{root} };

    $self->{midi} = $args{midi};
    return $self;
}

=head2 $opus->pluck( @actions )

Plucks a measurefull of strings.

Actions are strings (the ones between C<">) each containing a number
of space separated values.

The first value is the I<time> the action must be taken. The time is
expressed in fractional beats, C<1.0> is the first beat of a measure,
C<1.5> is halfway between C<1> and C<2>, and so on.

For triplets use C<1.0>, C<1.333>, and C<1.667>.

C<Actions> are strings (the ones that make music) and volumes. For
example, C<6:80> plucks string C<6> (on a guitar this is the I<lowest>
string) with relative volume C<80>. C<2-4:60> plucks strings C<2>,
C<3>, and C<4> with volume C<60>. C<5,1:70> plucks strings C<5> and
C<1> with volume C<70>, and so on.

Strings that are not indicated will keep sounding if they have been
plucked earlier. A volume of zero will mute the string.

See L<examples/risingsun.pl> for an example.

Note that regardless of the actions, pluck() fills a single measure.

=cut

sub pluck {
    my ( $self, @args ) = @_;

    foreach ( @args ) {
	# time actions... => time 0 actions
	my ( $offset, $actions ) = /^(\d+(?:\.\d+)?)\s+(.*)$/;
	croak("Invalid pluck pattern: $_") unless defined $offset;
	$_ = "$offset 0 $actions";
    }
    return $self->strum(@args);
}

=head2 $opus->strum( @actions );

Strums a measurefull of strings.

Actions are strings (the ones between C<">) each containing a number
of space separated values.

The first value is the I<time> the action starts. The time is
expressed in fractional beats, C<1.0> is the first beat of a measure,
C<1.5> is halfway between C<1> and C<2>, and so on.

The second value denotes the time distance between the strums. A value
of C<1> means that the strings will be plucked one beat after another.

It is conventional to denote the distance as a fraction. For example,
in a C<3/4> time signature, a strum starting at beat C<1> with
distance C<3/6> will equally distribute 6 plucks over the 3 beats of
the measure (1.0, 1.5, 2.0, 2.5, 3.0 3.5).

Actions are similar to the ones described for the pluck() method.
However, order is relevant now. For example, C<6:90 1-5:80> will pluck
strings 6, 1, 2, 3, 4, 5, in that order. C<6:90 5-1:80> will pluck 6,
5, 4, 3, 2, and 1.

Note that regardless of the actions, strum() fills a single measure.

=cut

sub strum {
    my ( $self, @args ) = @_;

    my @pattern;

    foreach ( @args ) {
	# time strum actions...
	my ( $offset, $disp, $actions ) =
	  m{ ^ (\d+(?:\.\d+)?)		# beat offset, 1-relative
	     \s+
	     ([-+]?\d+(?:\.\d+|\/\d+)?)	# strum displacement
	     \s+
	     (.*)			# actions
	     $ }x;
	croak("Invalid strum pattern: $_") unless defined $offset;

	# Strum displacement is either a float number, or a fraction.
	$disp = $1/$2 if $disp =~ m;^([-+]?\d+)/(\d+)$;;

	my @p;
	foreach ( split( ' ', $actions ) ) {
	    my @ev;

	    # Actions are string[-string]:velocity
	    croak("Invalid strum action: $_") unless /^([-\d,]+):(\d+)$/;
	    my $velocity = $2;
	    push( @ev, [ $_, $velocity ] ) for range($1);

	    # Negative displacement reverses the order of actions.
	    my $disp = $disp;
	    if ( $disp < 0 ) {
		$disp = -$disp;
		@ev = reverse @ev;
	    }

	    # Strum strings.
	    if ( $disp ) {
		foreach ( @ev ) {
		    push( @p, [ $offset, [ $_ ] ] );
		    $offset += $disp;
		}
	    }
	    # Displacement zero => pluck all strings.
	    else {
		push( @p, @ev );
	    }
	}
	push( @pattern, $disp ? @p : [ $offset, \@p ] );
    }
    # Bless it, so we can check its type.
    bless \@pattern => 'MIDI::Guitar::Pattern';
}

=head2 $opus->play( $pattern => $strings )

Plays a pattern over the strings.

Pattern is the result from an earlier call to pluck(), strum(), or tab().

Strings is a space separated series of finger positions. The strings
are played according to the positions. C<0> indicates an open string,
C<-> a muted string.

=cut

sub play {
    my $self = shift;

    unless ( @_ ) {
	$self->{cskip} += $self->{bpm} * $self->{tpb};
	return $self->{clock} += $self->{bpm} * $self->{tpb};
    }
    $self->{cskip} = 0;

    my ( $pattern, $strings ) = @_;

    unless ( UNIVERSAL::isa($pattern, 'MIDI::Guitar::Pattern' ) ) {
	croak("Pattern required");
    }
    unless ( UNIVERSAL::isa($strings, 'ARRAY' ) ) {
	$strings = [ split(' ', $strings) ];
    }
    croak("Number of strings must be ".scalar(@{ $self->{root} }))
      unless @$strings == @{ $self->{root} };

    foreach ( @$pattern ) {
	# [ measure-offset, [ actions ... ] ]
	my ( $offset, $actions ) = @$_;
	my $cclock = $self->{clock} + ( $offset - 1 ) * $self->{tpb};
	# Randomize clock time.
	$cclock += ( 1 - rand(2) ) * $self->{rtime} if $self->{rtime};
	$cclock = 0 if $cclock < 0;

	# Randomize velocity.
	my $dv = 0;
	$dv = ( 1 - rand(2) ) * $self->{rvol} if $self->{rvol};

	foreach ( @$actions ) {
	    # [ string velocity ]
	    my ( $str, $vel ) = @$_;
	    $str = @{ $self->{root} } - $str;
	    if ( defined $strings->[$str] ) {
		# Undefined is same as '-' (skip).
		next if $strings->[$str] eq '-';

		my $note = $self->{root}->[$str] + $strings->[$str];
		if ( $self->{sounding}->[$str] ) {
		    $self->note( $cclock, $self->{sounding}->[$str], 0 );
		}
		next unless $vel > 0;
		$self->note( $cclock, $note,
		      $vel > $self->{rvol} ? $vel + $dv : $vel );
		$self->{sounding}->[$str] = $vel ? $note : 0;
	    }
	}

    }
    $self->{clock} += $self->{bpm} * $self->{tpb};
}

=head2 $opus->tab( $measures, $data )

WARNING: Experimental method. API is likely to change.

Plays I<measures> of tablature I<data> (see e.g. L<https://en.wikipedia.org/wiki/Tablature#Guitar_tablature>).

Support is still very basic, but interestingly functional.

For example:

    $opus->tab( 4, <<EOD );
    ------5-7-----7-|8-----8-2-----2-|0---------0-----|----------------|
    ----5-----5-----|--5-------3-----|--1---1-----1---|--1-1-----------|
    --5---------5---|----5-------2---|----2---------2-|0-2-2-----------|
    7-------6-------|5-------4-------|3---------------|----------------|
    ----------------|----------------|----------------|2-0-0---0---8-7-|
    ----------------|----------------|----------------|----------------|
    EOD

See L<examples/stairway.pl> for an example.

=cut

sub tab {
    my ( $self, @args ) = @_;

    my $bpm = 4;
    if ( @args > 1 && $args[0] =~ /^\d+$/ ) {
	$bpm = 0 + shift(@args);
    }
    if ( @args == 1 ) {
	@args = split( /\s*[\n\r]\s*/, $args[0] );
    }
    croak("Number of tab lines must be ", scalar(@{ $self->{root} }) )
      unless @args == @{ $self->{root} };

    croak("Tab format error: $args[0]")
      unless $args[0] =~ /^\|?([-\d]+)\|/;
    my $step = length($1);
    croak("Strange measure size $step: $args[0]")
      unless $self->{ticks}/$step/$bpm == int($self->{ticks}/$step/$bpm);
    for ( @args ) {
	next if /^\|?([-\d]{$step}\|)+/;
	croak("Tab format error: $_");
    }
    s/\|//g for @args;
    $step = $self->{ticks} / ($step / $bpm);

    my $cclock = $self->{clock};

    while ( $args[0] ) {
	my $vel = 80;
	my $dv = 0;
	$dv = ( 1 - rand(2) ) * $self->{rvol} if $self->{rvol};
	# Randomize clock time.
	my $dc = 0;
	$dc = ( 1 - rand(2) ) * $self->{rtime} if $self->{rtime};
	$dc = 0 if $dc + $cclock <= 0;
	for ( my $s = 0; $s < @{ $self->{root} }; $s++ ) {
	    ( my $c, $args[$s] ) = $args[$s] =~ /(.)(.*)/;
	    next if $c eq '-';
	    my $str = @{ $self->{root} } - $s - 1;
	    my $note = $self->{root}->[$str] + $c;
	    if ( $self->{sounding}->[$str] ) {
		$self->note( $cclock+$dc, $self->{sounding}->[$str], 0 );
	    }
	    $self->note( $cclock+$dc, $note,
		  $vel > $self->{rvol} ? $vel + $dv : $vel );
	    $self->{sounding}->[$str] = $vel ? $note : 0;
	}
	$cclock += $step;
    }

    $self->{clock} = $cclock;
    return $self;
}

=head2 $opus->volume( $volume )

With an argument: sets the volume scaling.

Default scaling is 1.

Returns the old scaling.

=cut

sub volume {
    my ( $self, $vol ) = @_;
    my $v = $self->{volume};
    $self->{volume} = $vol if @_ > 1;
    return $v;
}

=head2 $opus->cresc( $amt, $measures )

Modifies the volume in equal steps over the indicated number of measures.

Mostly used for crescendo / decrescendo.

For example, to decresc to 60% over 3 measures:

    $opus->cresc( 0.6, 3 );

=cut

my $cresc;
sub cresc {
    my ( $self, $amt, $bars ) = @_;
    my $v0 = $self->{volume};
    my $v1 = $amt * $v0;
    my $c0 = $self->{clock} - $self->{tpb};
    my $c1 = $c0 + ( $bars * $self->{bpm} * $self->{tpb} );
    $cresc = [ $c0, $v0, $c1, $v1 ];
    return $self;
}

=head2 $opus->tempo( $tempo )

Sets the tempo (beats per minute).

=cut

my @xtempo;
sub tempo {
    my ( $self, $tempo, $cclock ) = @_;
    $cclock //= $self->{clock};
    push( @xtempo, [ $cclock, int(60000000/$tempo) ] );
    $self->{bpmin} = $tempo;
    return $self;
}

=head2 $opus->rit( $amt, $measures )

Modifies the tempo in equal steps over the indicated number of measures.

Mostly used to slow down (ritenuto, ritardando, hence the name rit()).

For example, to slow down 100bpm to 60bpm over 3 measures:

    $opus->rit( 0.6, 3 );

=cut

sub rit {
    my ( $self, $amt, $bars ) = @_;
    my $v0 = $self->{bpmin};
    my $v1 = $amt * $v0;
    my $d = ($v0 - $v1) / ($bars*$self->{bpm});
    my $cclock = $self->{clock};
    for ( 1 .. $bars*$self->{bpm} ) {
	$v0 -= $d;
	$self->tempo( $v0, $cclock );
	$cclock += $self->{ticks};
    }
    return $self;
}

=head2 $opus->finish( %opts )

Finishes the piece and writes the MIDI file (if requested).

Options are:

=over

=item file

Writes the piece to this MIDI file.

The filename can also be specified upon initialisation.

=back

NOTE: If appropriate,  this method is implicitly called upon destruction,

=cut

sub finish {
    my ( $self, %opts ) = @_;

    return unless $self && %$self && defined($self->{events}) && @{$self->{events}};

    foreach ( @{ $self->{sounding} } ) {
	next unless $_;
	$self->note( $self->{clock}, $_, 0 );
    }

    my @ctlevents = ( [ set_tempo => 0, int(60000000/$self->{bpmin0}) ],
		      [ time_signature => 0,
			$self->{bpm},
			$self->{q} == 2 ? 1
			: $self->{q} == 4 ? 2
			: $self->{q} == 8 ? 3
			: $self->{q} == 16 ? 4 : 0,
			24,
			8,
		      ],
		    );

    push( @ctlevents, [ 'set_tempo', $_->[0], $_->[1] ] ) for @xtempo;

    time2delta(\@ctlevents);
    my $ctl = MIDI::Track->new( { events => \@ctlevents } );


    unshift( @{ $self->{events} },
	     [ 'track_name',   0, 'Guitar' ],
	     [ 'patch_change', 0, $self->{chan}, $self->{patch} ] );
    time2delta(\@{ $self->{events} });
    my $track = MIDI::Track->new( { events => \@{ $self->{events} } } );

    my @tracks = ( $ctl, $track );

    if ( defined( my $l = $self->{lead} ) ) {
	my $tm       =  0;
	my $chan     =  9;	# 10, reserved for drums
	my $patch    =  0;	# standard kit
	my $note     = 37;	# SideKick
	my $velocity = 70;

	my @mm = ( [ 'track_name',   $tm, 'Metronome' ],
		   [ 'patch_change', $tm, $chan, $patch ],
		 );

	while ( $tm < $self->{clock} - $self->{cskip} ) {
	    push( @mm,
		  [  'note_on',  $tm,   $chan, $note, $velocity ],
		  [  'note_off', $tm+1, $chan, $note, 0         ] );
	    $tm += $self->{ticks};
	    last if $l++ == -1;
	}
	time2delta(\@mm);
	push( @tracks, MIDI::Track->new( { events => \@mm } ) );
    }

    my $opus = MIDI::Opus->new( { format => 1,
				  ticks => $self->{ticks},
				  tracks => \@tracks } );

    $opts{file} //= $self->{midi};
    $opus->write_to_file( $opts{file} ) if $opts{file};

    delete $self->{events};

    return $opus;
}

sub DESTROY {
    my $self = shift;
    return unless $self && %$self && defined($self->{events}) && @{$self->{events}};
    $self->finish;
    delete $self->{events};
}

################ Helper methods ################

sub note {
    my ( $self, $clock, $note, $velocity ) = @_;

    # Handle crescendo.
    if ( $cresc && $clock >= $cresc->[2] ) {
	# Reached final volume.
	$self->{volume} = $cresc->[3];
	undef $cresc;
    }
    if ( $cresc && $clock >= $cresc->[0] ) {
	my @c = @$cresc;
	$self->{volume} = $c[1] +
	  ( ( $c[3] - $c[1] ) / ( $c[2] - $c[0] ) ) * ( $clock - $c[0] );
    }

    # Handle velocity.
    $velocity *= $self->{volume};
    if ( $velocity > 127 ) {
	$velocity = 127;
    }

    push( @{ $self->{events} },
	  [ $velocity > 0 ? 'note_on' : 'note_off',
	    $clock, $self->{chan}, $note, $velocity ] );
    return $self;
}

################ Helpers (non-methods) ################

sub range {
    my ( $t ) = @_;
    my @r;

    foreach ( split( /,\s*/, $t ) ) {
	if ( /^\d+$/ ) {
	    push( @r, $_ );
	}
	elsif ( /^(\d+)-(\d+)$/ ) {
	    if ( $2 < $1 ) {
		push( @r, $_ ) for $2..$1;
	    }
	    elsif ( $2 > $1 ) {
		push( @r, $_ ) for $1..$2;
	    }
	    else {
		push( @r, $1 );
	    }
	}
	else {
	    croak("Range error: $t");
	}
    }
    return @r;
}

sub time2delta {
    my ( $ev ) = @_;

    my $time = 0;		# time until now
    foreach my $e ( @$ev ) {
	croak("NEGATIVE DELTA \@ $time: @{[$e->[EV_TIME]-$time]}\n")
	  if $e->[EV_TIME] < $time;
	# Make time relative.
	($time, $e->[EV_TIME]) = ($e->[EV_TIME], $e->[EV_TIME]-$time);
    }

    # For convenience:
    $ev;
}

1;

__END__

## Basic.

{ time => 10,
  abst => undef,
  play => [ { string =>  5,
	      pos    =>  3,
	      velo   => 80, },
	    { string =>  3,
	      pos    =>  0,
	      velo   => 70, },
	    { string =>  2,
	      pos    =>  1,
	      velo   => 70, },
	    { string =>  1,
	      pos    =>  0,
	      velo   => 70, },
	  ],
};

## Pluck.
play( pluck( '1 5:80', '2 2-4:80', '3 4-2:80' ),
      '0 0 2 2 1 0' );

#-> one basic struct, where string pos are taken from the 2nd (chord) arg.

## Strum.
play( strum( '1 3/6 6:90 1-5:80'),
      '0 0 2 2 1 0' );

#-> m series of basic structs, n/m apart, where each string pos is taken
    from the 2nd (chord) arg.


=head1 AUTHOR

Johan Vromans, C<< <JV at cpan.org> >>

=head1 SUPPORT AND DOCUMENTATION

Development of this module takes place on GitHub:
https://github.com/sciurius/perl-MIDI-Guitar.

You can find documentation for this module with the perldoc command.

    perldoc MIDI::Guitar

Please report any bugs or feature requests using the issue tracker on
GitHub.

=head1 ACKNOWLEDGEMENTS

The basics for this module are derived from MMA's Plectrum tracks.
Admittingly, quite a lot of MMA's Plectrum track stuff is mine :) .

See L<https://www.mellowood.ca/mma/> for information on the MMA
program. It takes a while to get used to but it's awesome!

=head1 SEE ALSO

L<MIDI>.

=head1 COPYRIGHT & LICENSE

Copyright 2020 Johan Vromans, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of MIDI::Guitar
