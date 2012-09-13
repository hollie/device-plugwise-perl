use strict;
use warnings;
package Device::Plugwise;

use Carp qw/croak carp/;
use Device::SerialPort qw/:PARAM :STAT 0.07/;
use Fcntl;
use IO::Select;
use Socket;
use Symbol qw(gensym);
use Time::HiRes;

use constant DEBUG => $ENV{DEVICE_PLUGWISE_DEBUG};

# ABSTRACT: Perl module to communicate with Plugwise hardware

=head1 SYNOPSIS

  my $plugwise = Device::Plugwise->new(device => '/dev/cu.usbserial01');
  $plugwise->command('on', 'ABCDEF'); # Enable Circle#ABCDEF
  while (1) {
    my $message = $plugwise->read();
    print $message, "\n";
  }

  $plugwise = Device::Plugwise->new(device => 'hostname:port');
  $plugwise->command('on', 'ABCDEF'); # Enable Circle#ABCDEF

=head1 DESCRIPTION

Module for interfacing to Plugwise hardware.

Current implemented functions are

=over

=item Switching ON/OFF of circles

=item Query circles for their status

=item Query the Circles+ for known circles

=item Retrieve the live power consumption of a Circle

=item Readout the historic power consumption of a Circle (1-hour average)

=back

B<IMPORTANT:> This module required Plugwise firmware v2.37 or higher.

=method C<new(%parameters)>

This constructor returns a new Device::Plugwise object. Supported parameters are listed below

=over

=item device

The name of the device to connect to, The value can be a tty device name of C<hostname:port> for a TCP connection. This parameter is required.

=item filehandle

The name of an existing filehandle to be used instead of the 'device'
parameter.

=item baud

The baud rate for the tty device.  The default is C<9600>.

=item port

The port for a TCP device.  There is no default port

=back

=cut

sub new {
    my ($pkg, %p) = @_;

    my $self = bless {
        _buf => '',
        _q => [],
        baud => 115200,
        device => '',
        %p
    }, $pkg;


    if (exists $p{filehandle}) {   # do not open device when a filehandle
        delete $self->{device};    #  was defined (this is for testing purposes)
    } else {
        $self->_open();
    }

    return $self;

}

=method C<device()>

Returns the device used to connect to the equipment.  If a filehandle
was provided this method will return undef.

=cut

sub device { shift->{device} }

=method C<baud()>

Returns the baud rate. Only makes sense when connected over serial.

=cut

sub baud { shift->{baud} }

=method C<port()>

Returns the TCP port for the device. Only makes sense when using this type
of connection of course.

=cut

sub port { shift->{port} }

=method C<filehandle()>

This method returns the file handle for the device.

=cut

sub filehandle { shift->{filehandle} }

sub _open {
  my $self = shift;
  if ($self->{device} =~ m![/\\]!) {
    $self->_open_serial_port(@_);
  } else {
    if ($self->{device} eq 'discover') {
      my $devices = $self->discover;
      my ($ip, $port) = @{$devices->[0]};
      $self->{port} = $port;
      $self->{device} = $ip.':'.$port;
    }
    $self->_open_tcp_port(@_);
  }
}

sub _open_tcp_port {
  my $self = shift;
  my $dev = $self->{device};
  print STDERR "Opening $dev as tcp socket\n" if DEBUG;
  require IO::Socket::INET; import IO::Socket::INET;
  if ($dev =~ s/:(\d+)$//) {
    $self->{port} = $1;
  }
  my $fh = IO::Socket::INET->new($dev.':'.$self->port) or
    croak "TCP connect to '$dev' failed: $!";
  return $self->{filehandle} = $fh;
}

sub _open_serial_port {
  my $self = shift;
  $self->{type} = 'ISCP';
  my $fh = gensym();
  my $s = tie (*$fh, 'Device::SerialPort', $self->{device}) ||
    croak "Could not tie serial port to file handle: $!\n";
  $s->baudrate($self->baud);
  $s->databits(8);
  $s->parity("none");
  $s->stopbits(1);
  $s->datatype("raw");
  $s->write_settings();

  sysopen($fh, $self->{device}, O_RDWR|O_NOCTTY|O_NDELAY) or
    croak "open of '".$self->{device}."' failed: $!\n";
  $fh->autoflush(1);
  return $self->{filehandle} = $fh;
}

=head1 ACKNOWLEDGEMENTS

The code of this module is heavily based on code examples by Mark Hindess (Device::Onkyo), thanks Mark!
The initial Perl Plugwise interface code for firmware v1 was written by Jfn.

=cut

1;
