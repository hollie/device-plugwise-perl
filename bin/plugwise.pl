#! /usr/bin/perl -w

use v5.10;
use strict;
use warnings;
use Device::Plugwise;
use Data::Dumper;
use IO::File;

# ABSTRACT: Example Perl script to control Plugwise devices
# PODNAME: plugwise.pl
#
# Usage: plugwise.pl <device> <command> <target>
# Possible commands are the commands detailed in the Plugwise module
# documentation, plus some convenience functions like 'listcircles'

if ( scalar @ARGV < 2 ) {
    die "Please pass device and command as parameters";
}
my $device  = $ARGV[0];
my $command = $ARGV[1];

print "Sending $command...";

my $plugwise = Device::Plugwise->new( device => $device );
my $msg;

if ( $command eq 'listcircles' ) {
    my $status = $plugwise->status();
    say "Known Circles on the network are:";
    foreach ( keys %{ $status->{circles} } ) {
        say $_;
    }
    exit(0);
}

$plugwise->command( $command, $ARGV[2] );

# Ensure to process all reads
PROCESS_READS: do {
    $msg = $plugwise->read(2);
    print "Response: " . Dumper($msg) if defined $msg;
} while ( defined $msg );
