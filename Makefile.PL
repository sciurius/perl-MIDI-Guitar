#! perl

use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'MIDI::Guitar',
    AUTHOR              => 'Johan Vromans <jv@cpan.org>',
    VERSION_FROM        => 'lib/MIDI/Guitar.pm',
    ABSTRACT_FROM       => 'lib/MIDI/Guitar.pm',
    LICENSE		=> 'perl_5',
    PL_FILES            => {},
    MIN_PERL_VERSION	=> '5.010001',
    PREREQ_PM => {
        'ExtUtils::MakeMaker' => 6.46, # for META_MERGE, LICENSE
        'Test::More'	=> 0,
	'MIDI'		=> 0.83,
    },
    META_MERGE => {
      resources    => {
        repository => {
          type => 'git',
	   web  => 'https://github.com/sciurius/perl-MIDI-Guitar',
	   url  => 'https://github.com/sciurius/perl-MIDI-Guitar.git',
	},
	bugtracker => {
	  web => "https://github.com/sciurius/perl-MIDI-Guitar/issues",
	},
      },
      'meta-spec' => {
        version => '2',
	url     => 'https://metacpan.org/pod/CPAN::Meta::Spec',
      },
    },
);
