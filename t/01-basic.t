#!/usr/bin/perl
#
# Copyright (C) 2012 by Lieven Hollevoet

use strict;
use Test::More tests => 4;

use_ok 'Device::Plugwise';

my $stim = 't/stim/basic.txt';
open my $fh, $stim or die "Failed to open $stim: $!\n";

my $plugwise = Device::Plugwise->new(filehandle => $fh);
ok $plugwise, 'object created';

my $msg = $plugwise->read;
is $msg, 'PWR01', '... read power on';

$msg = $plugwise->read;
is $msg, 'PWR00', '... read power off';

