#!/usr/bin/perl
#
# Copyright (C) 2012 by Lieven Hollevoet

use strict;
use Test::More tests => 2;

use_ok 'Device::Plugwise';

my $stim = 't/stim/basic.txt';
open my $fh, $stim or die "Failed to open $stim: $!\n";

#my $plugwise = Device::Plugwise->new(filehandle => $fh);

my $plugwise = Device::Plugwise->new(device => 'localhost:2500');
ok $plugwise, 'object created';

#my $msg = $plugwise->read;
#is $msg, 'Connected', '... connnected';


