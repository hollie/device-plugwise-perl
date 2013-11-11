
use strict;
use warnings;

use 5.010000;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Perl module to communicate with Plugwise hardware",
  "AUTHOR" => "Lieven Hollevoet <hollie\@cpan.org>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "Device-Plugwise",
  "EXE_FILES" => [
    "bin/plugwise.pl",
    "bin/plugwise_demo.pl"
  ],
  "LICENSE" => "perl",
  "NAME" => "Device::Plugwise",
  "PREREQ_PM" => {
    "Carp" => 0,
    "Data::Dumper" => 0,
    "Device::SerialPort" => 0,
    "Digest::CRC" => 0,
    "Fcntl" => 0,
    "IO::File" => 0,
    "IO::Select" => 0,
    "IO::Socket::INET" => 0,
    "Math::Round" => 0,
    "Socket" => 0,
    "Symbol" => 0,
    "Time::HiRes" => 0,
    "constant" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "TEST_REQUIRES" => {
    "Test::More" => 0
  },
  "VERSION" => "0.4.2",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  my $tr = delete $WriteMakefileArgs{TEST_REQUIRES};
  my $br = $WriteMakefileArgs{BUILD_REQUIRES};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



