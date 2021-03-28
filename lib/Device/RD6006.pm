package Device::RD6006;

use 5.032001;
use strict;
use warnings;

use Carp;
use Time::HiRes qw( usleep );
use Device::Modbus::RTU::Client;

# use Data::Dumper; # debug


our $VERSION = '0.01';

sub new
{
  my ( $class, $tty, $addr ) = @_;
  my $self = {};
  bless( $self , $class );

  $self->{addr}      = $addr;
  $self->{tty}       = $tty;
  $self->{baudrate}  = 115200;
  $self->{n_try}     =     10;
  $self->{n_main_regs} =   20;

  $self->{v_scale}   =  100.0; # more for RD6006P ?
  $self->{i_scale}   = 1000.0;

  $self->{sleep_cmd_resp} =  50000; # sleep time in us between cmd and responce
  $self->{sleep_err}      = 500000; # sleep time in us after error

  $self->{data} = ();
  for( my $i=0; $i<$self->{n_main_regs}; ++$i ) {
    $self->{data}[$i] = 0;
  }

  $self->{dev} = Device::Modbus::RTU::Client->new( port  => $tty, baudrate => $self->{baudrate}, parity   => 'none' );

  return $self;
}

sub getDev
{
  my $self = shift;
  return $self->{dev};
}

# write one register
sub wr1
{
  my( $self, $reg, $val, $act_str ) = @_;

  my $req = $self->{dev}->write_single_register( unit => $self->{addr}, address  => $reg, value => $val );

  TRY:
  for my $i ( 0.. $self->{n_try} ) {

    my $rc;
    eval {
      $rc =  $self->{dev}->send_request( $req );
    };
    if( $@ ) {
      carp( "wr1 send trap " );
      $rc = 0;
    }

    if( ! $rc ) {
      carp( "wr1 send error: $act_str rc= $rc err= $! i= $i " );
      usleep( $self->{sleep_err} );
      next TRY;
    }

    usleep( $self->{sleep_cmd_resp} );

    $rc = 1;
    my $resp;
    eval {
      $resp = $self->{dev}->receive_response();
    };
    if( $@ ) {
      carp( "wr1 recv trap " );
      $rc = 0;
    }

    if( ! $rc ) {
      carp( "wr1 recv error: $act_str  err= $! i= $i " );
      usleep( $self->{sleep_err} );
      next TRY;
    }

    if( $resp->success ) {
      return $resp;
    }
    carp( "wr1 recv not success $act_str  err= $! i= $i " );

    usleep( $self->{sleep_err} );
  }

  return;
}

sub readRegs
{
  my( $self, $reg0, $nreg ) = @_;
  my $req = $self->{dev}->read_holding_registers( unit => $self->{addr}, address  => $reg0, quantity => $nreg );

  TRY:
  for my $i ( 0.. $self->{n_try} ) {

    my $rc;
    eval {
      $rc = $self->{dev}->send_request( $req );
    };
    if( $@ ) {
      carp( "read send trap " );
      $rc = 0;
    }

    if( ! $rc ) {
      carp( "Send read error: reg0= $reg0 nreg = $nreg err= $! i= $i " );
      usleep( $self->{sleep_err} );
      next TRY;
    }

    usleep( $self->{sleep_cmd_resp} );

    $rc = 1;
    my $resp;

    eval {
      $resp = $self->{dev}->receive_response();
    };
    if( $@ ) {
      carp( "Read resp trap " );
      $rc = 0;
    }

    if( ! $rc ) {
      carp( "Read recv error: err= $! i= $i " );
      usleep( $self->{sleep_err} );
      next TRY;
    }

    if( $resp->success() ) {
      return $resp->{message}->{values};
    }

    carp( "Recv read error: err= $! i= $i\n" );
    usleep( $self->{sleep_err} );
  }

  return;
}

sub readMainRegs
{
  my( $self, $xxx ) = @_;
  my $vals = $self->readRegs( 0, $self->{n_main_regs} );
  # print Dumper( $vals ); # debug
  if( ! $vals ) {
    return;
  }

  for( my $i=0; $i<$self->{n_main_regs}; ++$i ) {
    # print( STDERR $i, $vals->[$i] );
    $self->{data}[$i] = $vals->[$i];
  }
  return 1;
}

sub readReg
{
  my( $self, $reg ) = @_;
  my $resp = $self->readRegs( $reg, 1 );
  if( ! $resp ) {
    return;
  }
  return $resp->[0];
}

sub OnOff
{
  my( $self, $on ) = @_;
  $on = $on ? 1 : 0;
  return $self->wr1( 18, $on, "OnOff" );
}

sub On
{
  my $self = shift;
  return $self->OnOff( 1 );
}

sub Off
{
  my $self = shift;
  return $self->OnOff( 0 );
}

sub set_V # ( V_volt )
{
  my( $self, $v ) = @_;
  return $self->wr1( 8, int( $v * $self->{v_scale} + 0.499 ), "set_V" );
}

sub set_I # ( I_amp )
{
  my( $self, $I ) = @_;
  return $self->wr1( 9, int( $I * $self->{i_scale} + 0.499 ), "set_I" );
}


sub get_V # after readMainRegs
{
  my $self = shift;
  return $self->{data}[10] / $self->{v_scale};
}

sub get_I # after readMainRegs
{
  my $self = shift;
  return $self->{data}[11] / $self->{i_scale};
}

sub get_V_set # after readMainRegs
{
  my $self = shift;
  return $self->{data}[8] / $self->{v_scale};
}

sub get_I_set # after readMainRegs
{
  my $self = shift;
  return $self->{data}[9] / $self->{i_scale};
}

sub get_W # after readMainRegs
{
  my $self = shift;
  return $self->{data}[13] / 100.0; # TODO: scale
}


sub get_OnOff # after readMainRegs
{
  my $self = shift;
  return $self->{data}[18] ? 1 : 0;
}

sub get_Error # after readMainRegs
{
  my $self = shift;
  return $self->{data}[16];
}



sub read_V
{
  my $self = shift;
  my $x = $self->readReg( 10 );
  if( defined( $x ) ) {
    return $x / $self->{v_scale};
  }
  return 0;
}

sub read_I
{
  my $self = shift;
  my $x = $self->readReg( 11 );
  if( defined( $x ) ) {
    return $x / $self->{i_scale};
  }
  return 0;
}

sub read_V_set
{
  my $self = shift;
  my $x = $self->readReg( 8 );
  if( defined( $x ) ) {
    return $x / $self->{v_scale};
  }
}

sub read_I_set
{
  my $self = shift;
  my $x = $self->readReg( 9 );
  if( defined( $x ) ) {
    return $x / $self->{i_scale};
  }
  return 0;
}

sub read_OnOff
{
  my $self = shift;
  my $x = $self->readReg( 10 );
  if( defined( $x ) ) {
    return $x;
  }
  return 0;
}

sub read_Error
{
  my $self = shift;
  my $x = $self->readReg( 16 );
  if( defined( $x ) ) {
    return $x;
  }
  return 0x80;
}


sub check_Signature
{
  my $self = shift;
  my $x = $self->readReg( 0 );
  if( !defined( $x ) ) {
    carp( "Fail to read signature" );
    return 0;
  }
  #my $s = sprintf( "Signature = %04X" , $x );
  #carp( $s );
  return ( $x == 0xEA9E );
}


sub DESTROY
{
  my $self = shift;
  if( !defined($self->{dev}) ) {
    return;
  }
  $self->{dev}->disconnect();
  # carp( "destroy err= $err\n" );
  return;
}


1;
__END__


=head1 NAME

Device::RD6006 - Perl extension to control RD6006 power source via Modbus RTU

=head1 SYNOPSIS

  use Device::RD6006;


=head1 DESCRIPTION

This module is in the alpha stage - so see code for now


=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Anton Guda, E<lt>atu@localdomainE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2021 by Anton Guda

This library is free software; you can redistribute it and/or modify
it under the same terms of GPLv3


=cut
# vim: shiftwidth=2
