#!/usr/bin/perl
#
# Copyright (C) 2012 by Lieven Hollevoet

use strict;
use Test::More tests => 6;
use Data::Dumper;

use_ok 'Device::Plugwise';

my $stim = 't/stim/basic.txt';
open my $fh, $stim or die "Failed to open $stim: $!\n";

#my $plugwise = Device::Plugwise->new(filehandle => $fh);

my $plugwise = Device::Plugwise->new(device => 'localhost:2500');
ok $plugwise, 'object created';

my $msg = $plugwise->read(3);
$msg = $plugwise->read(3);
is $msg, 'connected', '... connnected';

my $status = $plugwise->status();

is $status->{connected}, 1, '... status updated OK';
is $status->{short_key}, 'BABE', "... network key extracted";

is $plugwise->command('on', 'ABCDEF'), 1, "... command send OK";

