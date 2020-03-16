#! perl

package MIDI::Guitar;

use warnings;
use strict;

=head1 NAME

MIDI::Guitar - Plucked guitar MIDI

our $VERSION = '0.01';

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
	       );
    $self->init( %args, @_);
    return $self;
}

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

    # Randomizers.
    $self->{rtime} = $args{rtime} || 0;
    $self->{rvol}  = $args{rvol}  || 0;

    $self->{clock} = 0;
    $self->{ticks} = 192;
    $self->{tpb} = $self->{ticks};

    $self->{lead} = $args{lead};
    if ( defined $self->{lead} && $self->{lead} > 0 ) {
	$self->{clock} += $self->{lead} * $self->{tpb};
    }
    $self->{cskip} = 0;
    @{ $self->{root} } = map { 12+$MIDI::note2number{$_} } split( ' ', $args{strings} );
    @{ $self->{sounding} } = (0) x @{ $self->{root} };

    return $self;
}

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
		    push( @pattern, [ $offset, [ $_ ] ] );
		    $offset += $disp;
		}
	    }
	    # Displacement zero => pluck all strings.
	    else {
		push( @pattern, [ $offset, \@ev ] );
	    }
	}
    }
    # Bless it, so we can check its type.
    bless \@pattern => 'PlayPattern';
}

sub play {
    my $self = shift;

    unless ( @_ ) {
	$self->{cskip} += $self->{bpm} * $self->{tpb};
	return $self->{clock} += $self->{bpm} * $self->{tpb};
    }
    $self->{cskip} = 0;

    my ( $pattern, $strings ) = @_;

    unless ( UNIVERSAL::isa($pattern, 'PlayPattern' ) ) {
	croak("PlayPattern required");
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
		$self->note( $cclock, $note,
		      $vel > $self->{rvol} ? $vel + $dv : $vel );
		$self->{sounding}->[$str] = $vel ? $note : 0;
	    }
	}

    }
    $self->{clock} += $self->{bpm} * $self->{tpb};
}

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

sub note {
    my ( $self, $clock, $note, $velocity ) = @_;
    push( @{ $self->{events} },
	  [ $velocity > 0 ? 'note_on' : 'note_off',
	    $clock, $self->{chan}, $note, $velocity ] );
    return $self;
}

my @xtempo;
sub tempo {
    my ( $self, $tempo, $cclock ) = @_;
    $cclock //= $self->{clock};
    push( @xtempo, [ $cclock, int(60000000/$tempo) ] );
    $self->{bpmin} = $tempo;
    return $self;
}

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

sub finish {
    my ( $self, %opts ) = @_;

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

    if ( defined $self->{lead} ) {
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
	}
	time2delta(\@mm);
	push( @tracks, MIDI::Track->new( { events => \@mm } ) );
    }

    my $opus = MIDI::Opus->new( { format => 1,
				  ticks => $self->{ticks},
				  tracks => \@tracks } );

    $opus->write_to_file( $opts{file} ) if $opts{file};

    return $opus;
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


=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 FUNCTIONS

=head2 function1

=cut

sub function1 {
}

=head2 function2

=cut

sub function2 {
}

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

=head1 COPYRIGHT & LICENSE

Copyright 2020 Johan Vromans, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of MIDI::Guitar
