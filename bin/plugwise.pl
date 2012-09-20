#! /usr/bin/perl -w

use strict;
use warnings;
use Device::Plugwise;

# ABSTRACT: Perl script to control Plugwise devices
# PODNAME: plugwise.pl

my $plugwise = Device::Plugwise->new(device => 'localhost:2500');
$plugwise->read(3);

$plugwise->command('on', 'ABCDEF');
$plugwise->read(3);