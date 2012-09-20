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

__END__

=pod

=head1 NAME

plugwise.pl - Perl script to control Plugwise devices

=head1 VERSION

version 0.003

=head1 AUTHOR

Lieven Hollevoet <hollie@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Lieven Hollevoet.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
