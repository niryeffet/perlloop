use strict;

package InLoop::methods;
use Errno qw(EAGAIN);

sub evOff { InLoop::evOff(shift); }

sub getOpenTime { $_[0]->{openTime}; }

sub _evWriter {
  my $h = shift;
  my $dataOut = $h->{dataOut};
  while (@$dataOut) {
    my $d = $dataOut->[0];
    my $l = syswrite($_, $d);
    if ($l && $l < length($d)) {
      $dataOut->[0] = substr($d, $l);
      $! = EAGAIN;
    }
    return if $!;
    shift @$dataOut;
  }
  delete $h->{dataOut};
  1;
}

sub write {
  my ($h, $d) = @_;
  my $out = $h->{out};
  return if !$out;
  my $dataOut = $h->{dataOut};
  return push(@$dataOut, $d) if $dataOut;
  my $l = syswrite($out, $d);
  if ($l && $l < length($d)) {
    $d = substr($d, $l);
    $! = EAGAIN;
  }
  if ($!) {
    if ($!{EAGAIN}) {
      $h->{dataOut} = [$d];
      InLoop::evOutRef(\&_evWriter, $h);
    } else {
      InLoop::_hangup($h);
    }
  }
}

sub say {
  my ($h, $d) = @_;
  InLoop::methods::write($h, "$d\n");
}

1;
