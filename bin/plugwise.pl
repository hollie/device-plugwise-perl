#! /usr/bin/perl -w

use v5.10;
use strict;
use warnings;
use Device::Plugwise;
use Data::Dumper;
use IO::File;

# ABSTRACT: Example Perl script to control Plugwise devices
# PODNAME: plugwise.pl

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

=head1 SYNOPSIS

  This script enables simple control of individual Circles as follows

    ./plugwise.pl <device> <command> <target>

  Example:
    ./plugwise.pl /dev/ttyUSB0 on ABCDEF

    will switch circles with address ABCDEF on

=cut
