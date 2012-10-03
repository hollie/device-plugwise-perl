#! /usr/bin/perl -w

use strict;
use warnings;
use Device::Plugwise;
use IO::File;

# ABSTRACT: Example Perl script to control Plugwise devices
# PODNAME: plugwise.pl


my $stim = 't/stim/basic.txt';
my $fh = IO::File->new( $stim, q{<} );

my $plugwise = Device::Plugwise->new( device => 'localhost:2500' );

$plugwise->read(3);

$plugwise->command( 'on',     'ABCDE0' );
$plugwise->command( 'off',    'ABCDE1' );
$plugwise->command( 'status', 'ABCDE2' );
$plugwise->command( 'on',     'ABCDE3' );
$plugwise->command( 'off',    'ABCDE4' );

my $msg;

READLOOP: do {
    $msg = $plugwise->read(3);
} while ( defined $msg );

print "End of test code...\n";

__END__

=pod

=head1 NAME

plugwise.pl - Example Perl script to control Plugwise devices

=head1 VERSION

version 0.1

=head1 AUTHOR

Lieven Hollevoet <hollie@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Lieven Hollevoet.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
