#! /usr/bin/perl -w

use v5.10;
use strict;
use warnings;
use Device::Plugwise;
use Data::Dumper;
use IO::File;

# ABSTRACT: Example Perl script to control Plugwise devices
# PODNAME: plugwise.pl

if ( scalar @ARGV < 1 ) {
    die "Please pass device name as command line parameter";
}
my $device  = $ARGV[0];

my $plugwise = Device::Plugwise->new( device => $device );

my $msg;
my $status;

# Generate status requests for all known Circles
$status = $plugwise->status();

foreach ( keys %{ $status->{circles} } ) {
    $plugwise->command( 'status', $_ );
}

READLOOP: do {
    $msg = $plugwise->read(3);
    print Dumper ($msg) if ( defined $msg );
} while ( defined $msg );

print "End of test code...\n";

=head1 SYNOPSIS

  This script is a basic demonstration of the Device::Plugwise module.
  To use it, start it as follows:
  
    ./plugwise_demo.pl <stick_serial_port>
    
  It should respond telling you it got a valid response on the init
  request, and it should start receiving calibration responses from
  active circles.
  
  After the calibration responses are received, the status of the 
  active circles in the nework should be printed.
  
=cut
