use strict;

package InLoop::methods;
use Errno qw(EAGAIN);

sub evOff {
  my $h = shift;
  return InLoop::evOff($h) unless $h->{dataOut};
  $h->{off} = 1;
}

sub getOpenTime { $_[0]->{openTime}; }

sub _evWriter {
  my $h = shift;
  my $dataOut = $h->{dataOut} || [];
  while (@$dataOut) {
    my $d = $dataOut->[0];
    my $l = syswrite($_, $$d);
    if ($l && $l < length($$d)) {
      $dataOut->[0] = \substr($$d, $l);
      $! = EAGAIN;
    }
    return if $!;
    shift @$dataOut;
  }
  delete $h->{dataOut};
  InLoop::evOff($h) if $h->{off};
  1;
}

sub writeRef {
  my ($h, $d) = @_;
  my $dataOut = $h->{dataOut};
  return push(@$dataOut, $d) if $dataOut;
  my $out = $h->{out};
  if (!$out) {
    $h->{outEv} = \&_evWriter;
    return $h->{dataOut} = [$d];
  }
  my $l = syswrite($out, $$d);
  if ($l && $l < length($$d)) {
    $d = \substr($$d, $l);
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

sub write {
  my ($h, $d) = @_;
  writeRef($h, \$d);
}

sub say {
  my ($h, $d) = @_;
  writeRef($h, \"$d\n");
}

1;
