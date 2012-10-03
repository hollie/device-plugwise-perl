#!/usr/bin/perl
#
# Copyright (C) 2012 by Lieven Hollevoet

use strict;
use Test::More tests => 12;

use_ok 'IO::File';
use_ok 'Device::Plugwise';

# The stimulus file contains the responses
# required to run some basic module tests
#  * init response
#  * response to Circle ON command
#  * response to Circle OFF command
my $stim = 't/stim/basic.txt';
my $fh = IO::File->new( $stim, q{<} );

my $plugwise = Device::Plugwise->new(filehandle => $fh);

#my $plugwise = Device::Plugwise->new(device => 'localhost:2500');
ok $plugwise, 'object created';

my $msg = $plugwise->read(3);
is $msg, 'connected', '... connected';

my $status = $plugwise->status();

is $status->{connected}, 1, '... status updated OK';
is $status->{short_key}, 'BABE', "... network key extracted";

is $plugwise->command('on', 'ABCDEF'), 1, "... command send OK";
is $plugwise->command('off', 'ABCDEE'), 1, "... command send OK";
is $plugwise->queue_size(), 1, "... message queued OK";
$msg = $plugwise->read(3);
is @{$msg->{body}}[-1], "HIGH", "... command response OK";
$msg = $plugwise->read(3);
is @{$msg->{body}}[1], "ABCDEE", "... expected device ID OK";
is @{$msg->{body}}[-1], "LOW", "... command response OK";

$fh->close();
