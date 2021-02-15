#! perl

package MIDI::Guitar;

use warnings;
use strict;

=head1 NAME

MIDI::Guitar - Plucked guitar MIDI

=cut

our $VERSION = '0.08';

=head1 SYNOPSIS

This module provides basic tools to generated MIDI for plucked string
guitar sounds.

    use MIDI::Guitar;

    my $opus = MIDI::Guitar->new();
    $opus->init( signature => '3/4', tempo => 160 );

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
# $cskip;			# skip metro on sound out
# @root;			# root notes for strings
# @sounding;			# strings that sound
# @xevents
# $cresc

# MIDI parameters.
#
# $chan;			# MIDI channel
# $ticks;			# MIDI ticks
# $clock;			# current
# @events;			# events for main track

=head1 METHODS

=head2 $opus = MIDI::Guitar->new( %args )

Creates a new MIDI::Guitar instance, supplies default values, and
initialises it with the arguments, if any.

Possible arguments are:

=over

=item name

The MIDI track name.

=item signature

Time signature. This should be a fraction where the denominator is a
power of 2, e.g. C<4/4> or C<6/8>.

Default is C<4/4>.

=item tempo

Tempo, in beats per minute.

Default is C<100>.

=item volume

Initial volume scaling factor. Individual velocities of string plucks
are scaled by this factor.

Valid values are C<0> .. C<1.5>. Default value is C<1>.

Note that no final velocity will exceed the MIDI maximum of C<127>.

=item instrument

MIDI instrument name. See L<MIDI> for a list of instrument names.

Default is C<Acoustic Guitar(nylon)>.

=item strings

The strings of the instrument, in scientific pitch notation.

Default is common guitar tuning, C<E2 A2 D3 G3 B3 E4>.

Note: There can be any number of strings.

=item ticks

Experts only.

=item rtime

Time randomizer. Suitable values are 0 .. 10.

=item rvolume

Volume randomizer. Suitable values are 0 .. 6.

Default is 0 (no volume randomizing).

=item lead_in

Lead-in ticks.

Specifies the number of lead-in beats (not bars).

Default is 0 (no lead_in).

=item metronome

If nonzero, a metronome tick in included in the MIDI.

=item midi

The name of the MIDI file to be produced, if any.

=item channel

Experts only. Designates the MIDI channel (0 .. 15) to use.

Note that the lead_in and metronome will always use channel 9, as per
MIDI conventions.

=back

=cut

sub new {
    my $pkg = shift;
    my $self = bless {} => $pkg;

    # Hardwired for now.
    $self->{chan} = 0;

    # Defaults.
    my %args = ( name       => "Guitar",
		 signature  => '4/4',
		 tempo      => 100,
		 instrument => 'Acoustic Guitar(nylon)',
		 strings    => 'E2 A2 D3 G3 B3 E4',
		 volume     => 1,
	       );
    $self->_init( %args, @_);
    return $self;
}


sub _init {
    my $self = shift;
    my %args = ( @_ );

    $self->{testing} = delete $args{testing};

    $self->{name} = delete($args{name}) || "Guitar";

    # Time signature.
    $self->{sig} = delete $args{signature};
    croak("Invalid time signature: $args{signature}")
      unless $self->{sig} =~ m;^(\d+)/(\d)$;;
    $self->{bpm} = $1;		# beats per measure
    $self->{q} = $2;

    # Beats per minutes.
    $self->{bpmin} = $self->{bpmin0} = 0+delete($args{tempo});

    $self->{chan} = delete($args{channel}) || 0;
    croak("Invalid MIDI channel, should be between 0 and 15: $args{channel}")
      unless $self->{chan} >= 0 && $self->{chan} <= 15;

    # Instrument. Patch name.
    $self->{patch} = delete $args{instrument};
    unless ( $self->{patch} =~ /^[0-9]+$/ ) {
	$self->{patch} = $MIDI::patch2number{$self->{patch}} //
	  croak("Unknown MIDI instrument: $args{instrument}");
    }

    # Volume.
    $self->{volume} = delete($args{volume}) || 1;
    croak("Invalid volume, should be between 0 and 1: $args{volume}")
      unless $self->{volume} >= 0 && $self->{volume} <= 1.5;

    # Randomizers.
    $self->{rtime} = delete($args{rtime}) || 0;
    $self->{rvol}  = delete($args{rvolume}) || 0;

    $self->{clock} = 0;
    $self->{ticks} = delete $args{ticks} || 192;
    $self->{tpb} = $self->{ticks};

    $self->{lead} = delete $args{lead_in};
    if ( defined $self->{lead} && $self->{lead} ) {
	$self->{clock} += $self->{lead} * $self->{tpb};
    }
    if ( delete $args{metronome} ) {
	$self->{lead} //= 0;
    }
    else {
	$self->{lead} = -$self->{lead} if defined( $self->{lead} );
    }
    $self->{cskip} = 0;
    my $strings = delete $args{strings};
    unless ( UNIVERSAL::isa($strings,'ARRAY') ) {
	$strings = [ split(' ',$strings) ];
    }
    if ( $self->{chan} == 9 ) {
	$self->{root} = [];
	for ( @$strings ) {
	    croak("Unknown percussion instrument: $_")
	      unless defined $MIDI::percussion2notenum{$_};
	    unshift( @{ $self->{root} }, 0+$MIDI::percussion2notenum{$_} );
	}
    }
    else {
	$self->{root} = [];
	for ( @$strings ) {
	    croak("Unknown note: $_")
	      unless defined $MIDI::note2number{$_};
	    push( @{ $self->{root} }, 12+$MIDI::note2number{$_} );
	}
    }
    @{ $self->{sounding} } = (0) x @{ $self->{root} };

    # Output file, if any. May also be specified in a C<finish> call.
    $self->{midi} = delete $args{midi};

    if ( %args ) {
	croak( "Unrecognized init arguments: " .
	       join( " ", sort keys %args ) );
    }

    return $self;
}

=head2 $opus2 = $opus->aux( %args )

Creates an additional instance that can be used just like the
original, but will be using a different MIDI channel.

The arguments are as with new() and will default to the values of the
creating instance. In practice, only the following arguments make sense:

Experts only. Argument values are not yet validated.

=over 2

=item *

name

=item *

instrument

=item *

strings

=item *

volume

=item *

rtime

=item *

rvolume

=back

=cut

sub aux {
    my ( $self, %args ) = @_;

    if ( %args ) {
	my $unk = "";
	for ( sort keys %args ) {
	    next if /^rvol|rvolume|rtime|volume|instr|instrument|strings|name$/;
	    $unk .= $_ . " ";
	}
	croak("Unrecognized init arguments for aux: $unk") if $unk;
    }
 
    my $opus = bless {} => ref($self);
    @{$opus}{keys(%$self)} = values(%$self);

    if ( $args{strings} ) {
	@{ $opus->{root} } = map { 12+$MIDI::note2number{$_} } split( ' ', $args{strings} );
    }
    else {
	$opus->{root} = [ @{ $self->{root} } ];
    }
    $opus->{$_} = [] for qw( events xevents );
    $opus->{sounding} = [ (0) x @{ $opus->{root} } ];
    $opus->{master} = $self;
    push( @{$self->{aux}}, $opus );
    $opus->{chan} = @{$self->{aux}};

    for ( qw( name strings volume rtime rvolume ) ) {
	next unless exists $args{$_};
	$opus->{$_ eq "rvolume" ? "rvol" : $_} = delete $args{$_};
    }
    # Instrument. Patch name.
    if ( $args{instrument} ) {
	$opus->{patch} = $args{instrument};
	$opus->{patch} = $MIDI::patch2number{$opus->{patch}} //
	  croak("Unknown MIDI instrument: $args{instrument}");
    }

    return $opus;
}

=head2 $opus->pluck( @actions )

Returns a pattern to pluck a measureful of strings.

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

Returns a pattern to strum a measureful of strings.

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

=head2 $opus->play( $pattern => $strings, ... )

Plays a pattern over the (series of) strings.

Pattern is the result from an earlier call to pluck(), strum(), or tab().

Pattern may be a reference to an array with patterns. If so, a random
pattern will be selected from the array.

Strings is a space separated series of finger positions. The strings
are played according to the positions. C<0> indicates an open string,
C<-> a muted string.

Returns itself.

=cut

sub play {
    my $self = shift;

    unless ( @_ ) {
	$self->{cskip} += $self->{bpm} * $self->{tpb};
	$self->{clock} += $self->{bpm} * $self->{tpb};
	return $self;
    }
    $self->{cskip} = 0;

    my ( $pattern, @strings ) = @_;

    # If it is an array of patterns, random select one.
    if ( UNIVERSAL::isa($pattern, 'ARRAY' )
	 && UNIVERSAL::isa($pattern->[0], 'MIDI::Guitar::Pattern' ) ) {
	$pattern = $pattern->[ rand( scalar(@$pattern) ) ];
    }
    unless ( UNIVERSAL::isa($pattern, 'MIDI::Guitar::Pattern' ) ) {
	croak("Pattern required");
    }

    for my $strings ( @strings ) {

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

    return $self;
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

Returns itself.

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

Returns itself.

For example, to decresc to 60% over 3 measures:

    $opus->cresc( 0.6, 3 );

=cut

sub cresc {
    my ( $self, $amt, $bars ) = @_;
    my $v0 = $self->{volume};
    my $v1 = $amt * $v0;
    my $c0 = $self->{clock} - $self->{tpb};
    my $c1 = $c0 + ( $bars * $self->{bpm} * $self->{tpb} );
    $self->{cresc} = [ $c0, $v0, $c1, $v1 ];
    return $self;
}

=head2 $opus->tempo( $tempo )

Sets the tempo (beats per minute).

Returns itself.

=cut

sub tempo {
    my ( $self, $tempo, $cclock ) = @_;
    $cclock //= $self->{clock};
    push( @{ $self->{xtempo} }, [ $cclock, int(60000000/$tempo) ] );
    $self->{bpmin} = $tempo;
    return $self;
}

=head2 $opus->rit( $amt, $measures )

Modifies the tempo in equal steps over the indicated number of measures.

Mostly used to slow down (ritenuto, ritardando, hence the name rit()).

Returns itself.

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

=item play

Plays the MIDI through a suitable MIDI player. This can be an array
with a command line, or a scalar, non-false value. In the latter case
the program C<midi-play> is used.

    $opus->finish( play => [ "timidity", "-c", "$ENV{HOME}/.timidity.cfg" ] );

If necessary, the MIDI data is written to a temporary file that is
removed after playing.

=back

Returns the MIDI Opus.

NOTE: If appropriate,  this method is implicitly called upon destruction,

=cut

sub finish {
    my ( $self, %opts ) = @_;

    return unless $self && %$self && defined($self->{events}) && @{$self->{events}};

    foreach ( @{ $self->{sounding} } ) {
	next unless $_;
	$self->note( $self->{clock}, $_, 0 );
    }

    my @ctlevents;
    unless ( $self->{testing} ) {
	push( @ctlevents,
	      [ text_event => 0,
		join( "", "Created by ", __PACKAGE__,
		      " version ", $VERSION ) ],
	      [ text_event => 0,
		"https://github.com/sciurius/perl-MIDI-Guitar" ] );
    }

    push( @ctlevents,
	  [ set_tempo => 0, int(60000000/$self->{bpmin0}) ],
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

    if ( my $xtempo = $self->{xtempo} ) {
	push( @ctlevents, [ 'set_tempo', $_->[0], $_->[1] ] ) for @$xtempo;
    }

    time2delta(\@ctlevents);
    my $ctl = MIDI::Track->new( { events => \@ctlevents } );


    unshift( @{ $self->{events} },
	     [ 'track_name',   0, $self->{name} ],
	     [ 'patch_change', 0, $self->{chan}, $self->{patch} ] );
    time2delta(\@{ $self->{events} });
    my $track = MIDI::Track->new( { events => \@{ $self->{events} } } );

    my @tracks = ( $ctl, $track );

    if ( $self->{aux} ) {
	my $ix = 1;
	foreach ( @{ $self->{aux} } ) {
	    my $self = $_;
	    my $ch = $self->{chan};
	    time2delta(\@{ $self->{events} });
	    push( @tracks, MIDI::Track->new
		  ( { events =>
		      [ [ 'track_name', 0, $self->{name} ],
			[ 'patch_change', 0, $ch, $self->{patch} ],
#			map { $_->[EV_CHAN] = $ch; $_ }
			    @{ $self->{events} } ] } ) );
	    delete $self->{events};
	}
    }

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
    my $tmp;
    if ( $opts{file} ) {
	$opus->write_to_file( $opts{file} );
    }
    elsif ( $opts{play} ) {
	use File::Temp qw( tempfile );
	my ( $fh, $filename ) = tempfile();
	close($fh);
	$opus->write_to_file( $filename );
	$opts{file} = $filename;
	$tmp++;
    }

    if ( $opts{play} ) {
	my @cmd = UNIVERSAL::isa($opts{play}, 'ARRAY')
	  ? @{$opts{play}}
	  : ( "midi-play" );
	system( @cmd, $opts{file} );
	unlink( $opts{file} ) if $tmp;
    }

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
    my $cresc = $self->{cresc};
    if ( $cresc && $clock >= $cresc->[2] ) {
	# Reached final volume.
	$self->{volume} = $cresc->[3];
	undef $cresc;
	delete $self->{cresc};
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

    # Percussion notes do not need note_off.
    return $self if $velocity == 0 && $self->{chan} == 9;

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
