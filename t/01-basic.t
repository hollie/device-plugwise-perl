#!/usr/bin/perl
#
# Copyright (C) 2012 by Lieven Hollevoet

use strict;
use Test::More tests => 4;

use_ok 'Device::Plugwise';

my $log = 't/log/basic.log';
open my $fh, $log or die "Failed to open $log: $!\n";

my $plugwise = Device::Onkyo->new(filehandle => $fh);
ok $plugwise, 'object created';

my $msg = $plugwise->read;
is $msg, 'PWR01', '... read power on';

$msg = $plugwise->read;
is $msg, 'PWR00', '... read power off';

