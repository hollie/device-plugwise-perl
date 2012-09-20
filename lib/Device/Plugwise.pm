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
use Digest::CRC qw(crc);

#use constant DEBUG => $ENV{DEVICE_PLUGWISE_DEBUG};
use constant DEBUG => 1;     # Print debug information on the module itself
use constant XPL_DEBUG => 0; # Print debug information on the plugwise protocol
use constant PHY_DEBUG => 0; # Print debug information on the physical link

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

The port for a TCP device.  There is no default port.

=back

=cut

sub new {
    my ($pkg, %p) = @_;

    my $self = bless {
        _buf => '',
        _q => [],
        _response_queue => {},
        _connected => 0,
        baud => 115200,
        device => '',
        %p
    }, $pkg;


    if (exists $p{filehandle}) {   # do not open device when a filehandle
        delete $self->{device};    #  was defined (this is for testing purposes)
    } else {
        $self->_open();
    }

    $self->_stick_init();          # connect to the USB stick

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

=method C<read([$timeout])>

This method blocks until a new message has been received by the
device.  When a message is received the message string is returned.
An optional timeout (in seconds) may be provided.

=cut

sub read {
  my ($self, $timeout) = @_;
  my $res = $self->read_one(\$self->{_buf});
  return $res if (defined $res);
  my $fh = $self->filehandle;
  my $sel = IO::Select->new($fh);
  READ_RESPONSE: do {
    my $start = $self->_time_now;
    $sel->can_read($timeout) or return;
    my $bytes = sysread $fh, $self->{_buf}, 2048, length $self->{_buf};
    $self->{_last_read} = $self->_time_now;
    $timeout -= $self->{_last_read} - $start if (defined $timeout);
    croak defined $bytes ? 'closed' : 'error: '.$! unless ($bytes);
    $res = $self->read_one(\$self->{_buf});
    $self->_write_now() if (defined $res && !$self->{_awaiting_stick_response});
    return $res if (defined $res);
  } while (1);
}

=method C<read_one(\$buffer, [$do_not_write])>

This method attempts to remove a single message from the buffer
passed in via the scalar reference.  When a message is removed a data
structure is returned that represents the data received.  If insufficient
data is available then undef is returned.

By default, a received message triggers sending of the next queued message
if the C<$do_no_write> parameter is set then writes are not triggered.

=cut

sub read_one {
  my ($self, $rbuf, $no_write) = @_;
  return unless ($$rbuf);

  print STDERR "rbuf=", _hexdump($$rbuf), "\n" if PHY_DEBUG;

  return unless ($$rbuf =~ s/\x05\x05\x03\x03(\w+)\r\n//);
  my $body = $self->_process_response($1);

  # If we received an 'ack' then we need to try to read the next message
  if ($body eq 'ack') {
    return unless ($$rbuf =~ s/\x05\x05\x03\x03(\w+)\r\n//);
    $body = $self->_process_response($1);
  }

  $self->_write_now unless ($no_write || $self->{_awaiting_stick_response});
  return $body;

}


=method C<write($command, $callback)>

This method queues a command for sending to the connected device.
The first write will be written immediately, subsequent writes are
queued until a response to the previous message is received.

=cut

sub write {
  my ($self, $cmd, $cb) = @_;
  print STDERR "Queuing: $cmd\n" if XPL_DEBUG;
  my $packet = "\05\05\03\03" . $cmd . $self->_plugwise_crc($cmd) . "\r\n";
  push @{$self->{_q}}, [$packet, $cmd, $cb];
  $self->_write_now unless ($self->{_waiting});
  1;
}

sub _write_now {
  my $self = shift;
  my $rec = shift @{$self->{_q}};
  my $wait_rec = delete $self->{_waiting};
  if ($wait_rec && $wait_rec->[1]) {
    my ($str, $cmd, $cb) = @{$wait_rec->[1]};
    $cb->() if ($cb);
  }
  return unless (defined $rec);
  $self->_real_write(@$rec);
  $self->{_waiting} = [ $self->_time_now, $rec ];
}

sub _real_write {
  my ($self, $str, $desc, $cb) = @_;
  print STDERR "Sending: $desc\n"   if XPL_DEBUG;
  print STDERR _hexdump($str), "\n" if PHY_DEBUG;
  syswrite $self->filehandle, $str, length $str;
  $self->{_awaiting_stick_response} = 1;
}

sub _stick_init {

  my $self = shift();
  $self->write("000A");

  return 1;
}


#This is a helper function that returns the CRC for communication with the USB stick.
sub _plugwise_crc
{
    my ($self, $data) = @_;
    sprintf ("%04X", crc($data, 16, 0, 0, 0, 0x1021, 0, 0));
}


# This function processes a response received from the USB stick.
#
# In a first step, the ACK response from the stick is handled. This means that the
# communication sequence number is captured, and a new entry is made in the response queue.
#
# Second step, if we receive an error response from the stick, pass this message back
#
# Finally, of course, decode actual useful messages and return their value to the caller
#
# The input to this function is the message with CRC, with the header and trailing part removed
sub _process_response {
  my ($self, $frame) = @_;

  print STDERR "Processing '$frame'\n" if XPL_DEBUG;

  # The default xpl message is a plugwise.basic trig, can be overwritten when required.
  my %xplmsg = (
      message_type => 'xpl-stat',
      schema => 'plugwise.basic',
      );

  # Check if the CRC matches
  if (! ($self->_plugwise_crc( substr($frame, 0, -4)) eq substr($frame, -4, 4))) {
      # Send out notification...
      #$xpl->ouch("PLUGWISE: received a frame with an invalid CRC");
      $xplmsg{schema} = 'log.basic';
      $xplmsg{body} = [ 'type' => 'err', 'text' => "Received frame with invalid CRC", 'code' => $frame ];
      return \%xplmsg;
  }

  # Strip CRC, we already know it is correct
  $frame =~ s/(.{4}$)//;

  # After a command is sent to the stick, we first receive an 'ACK'. This 'ACK' contains a sequence number that we want to track and that notifies us of errors.
  if ($frame =~ /^0000([[:xdigit:]]{4})([[:xdigit:]]{4})$/) {
  #      ack          |  seq. nr.     || response code |
    if ($2 eq "00C1") {
      $self->{_response_queue}->{hex($1)}->{received_ok} = 1;
      $self->{_response_queue}->{hex($1)}->{type} = $self->{_response_queue}->{last_type};
      # TODO: we might need to re-init the stick here. Check this in real life.
      return "ack"; # We received ACK from stick, we should not send an xPL message out for this response
    } elsif ($2 eq "00C2"){
      # We sometimes get this reponse on the initial init request, re-init in this case
      $self->write("000A");
      return "no_xpl_message_required";
    } else {
      #$xpl->ouch("Received response code with error: $frame\n");
      $xplmsg{schema} = 'log.basic';
      $xplmsg{body} = [ 'type' => 'err', 'text' => "Received error response", 'code' => $self->{_last_pkt_to_uart} . ":" . $2 ];
      delete $self->{_response_queue}->{hex($1)};
      $self->{_awaiting_stick_response} = 0;

      return \%xplmsg;

    }
  }

  $self->{_awaiting_stick_response} = 0;

  #     init response |  seq. nr.     || stick MAC addr || don't care    || network key    || short key
  if ($frame =~ /^0011([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{4})/) {
    # Extract info
    $self->{_plugwise}->{stick_MAC}   = substr($2, -6, 6);
    $self->{_plugwise}->{network_key} = $4;
    $self->{_plugwise}->{short_key}   = $5;
    $self->{_plugwise}->{connected}   = 1;

    # Update the response_queue, remove the entry corresponding to this reply
    delete $self->{_response_queue}->{hex($1)};

    print STDERR "PLUGWISE: Received a valid response to the init request from the Stick. Connected!\n" if DEBUG;
    return "connected";
  }

  #   circle off resp|  seq. nr.     |    | circle MAC
  if ($frame =~/^0000([[:xdigit:]]{4})00DE([[:xdigit:]]{16})$/) {
    my $saddr = $self->_addr_l2s($2);
    my $msg_type = $self->{_response_queue}->{hex($1)}->{type} || "control.basic";

    if ($msg_type eq 'control.basic') {
        $xplmsg{schema} = 'sensor.basic';
        $xplmsg{body} = ['device'  => $saddr, 'type' => 'output', 'current' => 'LOW'];
    } else {
        $xplmsg{body} = ['device'  => $saddr, 'type' => 'output', 'onoff' => 'off'];
    }
    # Update the response_queue, remove the entry corresponding to this reply
    delete $self->{_response_queue}->{hex($1)};

    print STDERR "PLUGWISE: Stick reported Circle " . $saddr . " is OFF\n" if DEBUG;
    return \%xplmsg;
  }

  #   circle on resp |  seq. nr.     |    | circle MAC
  if ($frame =~/^0000([[:xdigit:]]{4})00D8([[:xdigit:]]{16})$/) {
    my $saddr = $self->_addr_l2s($2);
    my $msg_type = $self->{_response_queue}->{hex($1)}->{type} || "control.basic";

    if ($msg_type eq 'control.basic') {
        $xplmsg{schema} = 'sensor.basic';
        $xplmsg{body} = ['device'  => $saddr, 'type' => 'output', 'current' => 'HIGH'];
    } else {
        $xplmsg{body} = ['device'  => $saddr, 'type' => 'output', 'onoff' => 'on'];
    }

    # Update the response_queue, remove the entry corresponding to this reply
    delete $self->{_response_queue}->{hex($1)};
    print STDERR "PLUGWISE: Stick reported Circle " . $saddr . " is ON\n" if DEBUG;
    return \%xplmsg;
  }

  # Process the response on a powerinfo request
  # powerinfo resp   |  seq. nr.     ||  Circle MAC    || pulse1        || pulse8        | other stuff we don't care about
  if ($frame =~/^0013([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{4})([[:xdigit:]]{4})/) {
    my $saddr = $self->_addr_l2s($2);
    my $pulse1 = $3;
    my $pulse8 = $4;

    # Assign the values to the data hash
    $self->{_plugwise}->{circles}->{$saddr}->{pulse1} = $pulse1;
    $self->{_plugwise}->{circles}->{$saddr}->{pulse8} = $pulse8;

    # Ensure we have the calibration info before we try to calc the power,
    # if we don't have it, return an error reponse
    if (!defined $self->{_plugwise}->{circles}->{$saddr}->{gainA}){
        #$xpl->ouch("Cannot report the power, calibration data not received yet for $saddr\n");
        $xplmsg{schema} = 'log.basic';
        $xplmsg{body} = [ 'type' => 'err', 'text' => "Report power failed, calibration data not retrieved yet", 'device' => $saddr ];
        delete $self->{_response_queue}->{hex($1)};

        return \%xplmsg;
    }

    # Calculate the live power
    my ($pow1, $pow8) = $self->calc_live_power($saddr);

    # Update the response_queue, remove the entry corresponding to this reply
    delete $self->{_response_queue}->{hex($1)};

    # Create the corresponding xPL message
    $xplmsg{body} = ['device'  => $saddr, 'type' => 'power', 'current' => $pow1/1000, 'current8' => $pow8/1000, 'units' => 'kW'];

    print STDERR "PLUGWISE: Circle " . $saddr . " live power 1/8 is: $pow1/$pow8 W\n" if DEBUG;
    return \%xplmsg;
  }

  # Process the response on a query known circles command
  # circle query resp|  seq. nr.     ||  Circle+ MAC   || Circle MAC on  || memory position
  if ($frame =~/^0019([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{2})$/) {
    # Store the node in the object
    if ($3 ne "FFFFFFFFFFFFFFFF") {
        $self->{_plugwise}->{circles}->{substr($3, -6, 6)} = {}; # Store the last 6 digits of the MAC address for later use
        # And immediately queue a request for calibration info
        $self->queue_packet_to_stick("0026".$3, "Request calibration info");
    }

    # Update the response_queue, remove the entry corresponding to this reply
    delete $self->{_response_queue}->{hex($1)};

    # Only when we have walked the complete list
    return "no_xpl_message_required" if ($4 ne sprintf("%02X", $self->{_plugwise}->{list_circles_count} - 1));

    my @xpl_body = ('command' => 'listcircles');
    my $count = 0;

    foreach my $device_id (keys %{$self->{_plugwise}->{circles}}){
        my $device_string = sprintf("device%02i", $count++);
        push @xpl_body, ($device_string => $device_id);
    }

    # Construct the complete xpl message
    $xplmsg{body} = [@xpl_body];
    $xplmsg{message_type} = 'xpl-stat';

    return \%xplmsg;
  }

  # Process the response on a status request
  # status response  |  seq. nr.     ||  Circle+ MAC   || year,mon, min || curr_log_addr || powerstate
  if ($frame =~/^0024([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{8})([[:xdigit:]]{8})([[:xdigit:]]{2})/){
    my $saddr = $self->_addr_l2s($2);
    my $onoff = $5 eq '00'? 'off' : 'on';
    my $current = $5 eq '00' ? 'LOW' : 'HIGH';
    $self->{_plugwise}->{circles}->{$saddr}->{onoff} = $onoff;
    $self->{_plugwise}->{circles}->{$saddr}->{curr_logaddr} = (hex($4) - 278528) / 8;
    my $msg_type = $self->{_response_queue}->{hex($1)}->{type} || "sensor.basic" ;

    my $circle_date_time = $self->tstamp2time($3);

    print STDERR "PLUGWISE: Received status response for circle $saddr: ($onoff, logaddr=" . $self->{_plugwise}->{circles}->{$saddr}->{curr_logaddr} . ", datetime=$circle_date_time)\n" if DEBUG;

    if ($msg_type eq 'sensor.basic') {
        $xplmsg{schema} = $msg_type;
        $xplmsg{body} = ['device' => $saddr, 'type' => 'output', 'current' => $current];
    } else {
        $xplmsg{body} = ['device' => $saddr, 'type' => 'output', 'onoff' => $onoff, 'address' => $self->{_plugwise}->{circles}->{$saddr}->{curr_logaddr}, 'datetime' => $circle_date_time];
    }
    # Update the response_queue, remove the entry corresponding to this reply
    delete $self->{_response_queue}->{hex($1)};

    return \%xplmsg;
  }

  # Process the response on a calibration request
  if ($frame =~/^0027([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{8})([[:xdigit:]]{8})([[:xdigit:]]{8})([[:xdigit:]]{8})$/){
  # calibration resp |  seq. nr.     ||  Circle+ MAC   || gainA         || gainB         || offtot        || offruis
    #print "Received for $2 calibration response!\n";
    my $saddr = $self->_addr_l2s($2);
    #print "Short address  = $saddr\n";
    print STDERR "PLUGWISE: Received calibration reponse for circle $saddr\n" if DEBUG;

    $self->{_plugwise}->{circles}->{$saddr}->{gainA}   = $self->_hex2float($3);
    $self->{_plugwise}->{circles}->{$saddr}->{gainB}   = $self->_hex2float($4);
    $self->{_plugwise}->{circles}->{$saddr}->{offtot}  = $self->_hex2float($5);
    $self->{_plugwise}->{circles}->{$saddr}->{offruis} = $self->_hex2float($6);

    # Update the response_queue, remove the entry corresponding to this reply
    delete $self->{_response_queue}->{hex($1)};

    return "no_xpl_message_required";
  }

  # Process the response on a historic buffer readout
  if ($frame =~/^0049([[:xdigit:]]{4})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{16})([[:xdigit:]]{8})$/){
  # history resp     |  seq. nr.     ||  Circle+ MAC   || info 1         || info 2         || info 3         || info 4         || address
    my $s_id     = $self->_addr_l2s($2);
    my $log_addr = (hex($7) - 278528) / 8 ;
    #print "Received history response for $2 and address $log_addr!\n";

    # Assign the values to the data hash
    $self->{_plugwise}->{circles}->{$s_id}->{history}->{logaddress} = $log_addr;
    $self->{_plugwise}->{circles}->{$s_id}->{history}->{info1} = $3;
    $self->{_plugwise}->{circles}->{$s_id}->{history}->{info2} = $4;
    $self->{_plugwise}->{circles}->{$s_id}->{history}->{info3} = $5;
    $self->{_plugwise}->{circles}->{$s_id}->{history}->{info4} = $6;

    # Ensure we have the calibration info before we try to calc the power,
    # if we don't have it, return an error reponse
    if (!defined $self->{_plugwise}->{circles}->{$s_id}->{gainA}){
        #$xpl->ouch("Cannot report the power, calibration data not received yet for $s_id\n");
        $xplmsg{schema} = 'log.basic';
        $xplmsg{body} = [ 'type' => 'err', 'text' => "Report power failed, calibration data not retrieved yet", 'device' => $s_id ];
        delete $self->{_response_queue}->{hex($1)};

        return \%xplmsg;
    }
    my ($tstamp, $energy) = $self->report_history($s_id);

    # If the timestamp is no good, we tried to retrieve a field that contains no valid data, generate an error response
    if ($tstamp eq "000000000000") {
        #$xpl->ouch("Cannot report the power for interval $log_addr of circle $s_id, it is in the future\n");
        $xplmsg{schema} = 'log.basic';
        $xplmsg{body} = [ 'type' => 'err', 'text' => "Report power failed, no valid data in time interval", 'device' => $s_id ];
        delete $self->{_response_queue}->{hex($1)};
        return \%xplmsg;
    }

    $xplmsg{body} = ['device' => $s_id, 'type' => 'energy', 'current' => $energy, 'units' => 'kWh', 'datetime' => $tstamp];

    print STDERR "PLUGWISE: Historic energy for $s_id"."[$log_addr] is $energy kWh on $tstamp\n" if DEBUG;

    # Update the response_queue, remove the entry corresponding to this reply
    delete $self->{_response_queue}->{hex($1)};

    return \%xplmsg;
  }

  # We should not get here unless we receive responses that are not implemented...
  #$xpl->ouch("Received unknown response: '$frame'");
  return "no_xpl_message_required";

}

=method C<status()>

This method returns the status of the internal _plugwise
hash.
This can be used to extract network information and for debugging.
Hash entries include

=over

=item connected   : is the software connected to the USB stick

=item stick_MAC   : Zigbee MAC address of the stick

=item network_key : Full zigbee network ID

=item short_key   : Short version of the network ID

=back

=cut

sub status {
  my ($self) = @_;
  return $self->{_plugwise};
}

=method C<command($command, $target)>

This method sends a command to the stick.

Supported C<$command>s without a target id are:

=over

=item listcircles : get a list of connected Circles, respond with their ID's

=back

Supported C<$command>s with a target id are:

=over

=item on        : switch a circle on

=item off       : switch a circle off

=item status    : request the current switch state, internal clock, live power consumption

=item livepower : request the current power measured by the Circle

=item history   : TODO: request the energy consumption for a specific logaddress

=back

C<$target> can either be a single short hardware MAC address or a
comma-separated list of devices if multiple devices need to receive
the same command.

=cut

sub command {
    my ($self, $command, $target) = @_;

    print STDERR "Sending command '$command' to '$target'\n" if DEBUG;

    # Commands that have no specific device
    if ($command eq 'listcircles') {
        #$self->_query_connected_circles();
        return 1;
    }

    my $packet = "";

    if (defined $target) {
        # Commands that target a specific device might need to be sent multiple times
        # if multiple devices are defined
        foreach my $circle (split /,/, $target) {
            $circle = uc($circle);

            if ($command eq 'on') {
                $packet = "0017" . $self->_addr_s2l($circle) . "01";
            } elsif ($command eq 'off') {
                $packet = "0017" . $self->_addr_s2l($circle) . "00";
            } elsif ($command eq 'status') {
                $packet = "0023" . $self->_addr_s2l($circle);
            } elsif ($command eq 'livepower') {
                # Ensure we have the calibration readings before we send the read command
                # because the processing of the response of the read command required the
                # calibration readings output to calculate the actual power
                if (!defined($self->{_plugwise}->{circles}->{$circle}->{offruis})) {
                    my $longaddr = $self->_addr_s2l($circle);
                    $self->write("0026". $longaddr); #, "Request calibration info");
                }
                $packet = "0012" . $self->_addr_s2l($circle);
            #} elsif ($command eq 'history') {
                # Ensure we have the calibration readings before we send the read command
                # because the processing of the response of the read command required the
                # calibration readings output to calculate the actual power
                # if (!defined($self->{_plugwise}->{circles}->{$circle}->{offruis})) {
                #     my $longaddr = $self->_addr_s2l($circle);
                #     $self->write("0026". $longaddr); #, "Request calibration info");
                # }
                # my $address = $msg->field('address') * 8 + 278528;
                # $packet = "0048" . $self->_addr_s2l($circle) . sprintf("%08X", $address);
            } else {
                #$xpl->info("internal: Received invalid command '$command'\n");
            }

            # Send the packet to the stick!
            $self->write($packet) if (defined $packet);

        }
    }

    return 1;
}

# Interrogate the network coordinator (Circle+) for all connected Circles
# This sub will generate the requests, and then the response parser function
# will generate a hash with all known circles
# When a circle is detected, a calibration request is sent to ge the relevant info
# required to calculate the power information.
# Circle info goes into a global hash like this:
#   $object->{_plugwise}->{circles}
#      A single circle entry contains the short id and the following info:
#         short_id => { gainA   => xxx,
#                       gainB   => xxx,
#                       offtot  => xxx,
#                       offruis => xxx }
sub _query_connected_circles {

    my ($self) = @_;

    # In this code we will scan all connected circles to be able to add them to the $self->{_plugwise}->{circles} hash
    my $index = 0;

    # Interrogate the Circle+ and add its info into the circles hash
    $self->{_plugwise}->{coordinator_MAC} = $self->_addr_l2s($self->{_plugwise}->{network_key});
    $self->{_plugwise}->{circles} = {}; # Reset known circles hash
    $self->{_plugwise}->{circles}->{$self->{_plugwise}->{coordinator_MAC}} = {}; # Add entry for Circle+
    $self->write("0026".$self->_addr_s2l($self->{_plugwise}->{coordinator_MAC})); #, "Calibration request for Circle+");

    # Interrogate the first x connected devices
    while ($index < $self->{_plugwise}->{list_circles_count}) {
        my $strindex = sprintf("%02X", $index++);
        my $packet   = "0018" . $self->_addr_s2l($self->{_plugwise}->{coordinator_MAC}) . $strindex;
        $self->write($packet); #, "Query connected device $strindex");
    }

    return;
}

# Convert the long Circle address notation to short
sub _addr_l2s {
    my ($self,$address) = @_;
    my $saddr = substr($address, -8, 8);
    # We will return at least 6 bytes, more if required
    # This is to keep compatibility with existing code that only supports 6 byte short addresses
    return sprintf("%06X", hex($saddr));
}

# Convert the short Circle address notation to long
sub _addr_s2l {
    my ($self,$address) = @_;
    return "000D6F00" . sprintf("%08X", hex($address));
}

# Convert hex values to float for power readout
sub _hex2float {
    my ($self, $hexstr) = @_;
    my $floater = unpack('f', reverse pack('H*', $hexstr));
    return $floater;
}

# Return the time
sub _time_now {
  Time::HiRes::time
}

# Print the data in hex
sub _hexdump {
  my $s = shift;
  my $r = unpack 'H*', $s;
  $s =~ s/[^ -~]/./g;
  $r.' '.$s;
}


=head1 ACKNOWLEDGEMENTS

The code of this module is heavily based the code by Mark Hindess (Device::Onkyo), thanks Mark!
The initial Perl Plugwise interface code for firmware v1 was written by Jfn.

=cut

1;
 
