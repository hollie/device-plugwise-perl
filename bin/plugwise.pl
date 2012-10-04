#! /usr/bin/perl -w

use v5.10;
use strict;
use warnings;
use Device::Plugwise;
use Data::Dumper;
use IO::File;

# ABSTRACT: Example Perl script to control Plugwise devices
# PODNAME: plugwise.pl

my $device = '/dev/ttyUSB0';

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

