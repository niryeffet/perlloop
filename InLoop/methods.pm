use strict;

package InLoop::methods;

sub evOff { InLoop::evOff(shift); }

sub getOpenTime { $_[0]->{openTime}; }

sub write {
  my ($h, $d) = @_;
  my $out = $h->{out};
  if ($out) {
    syswrite($out, $d);
    InLoop::_hangup($h) if $!;
  }
}

sub say {
  my ($h, $d) = @_;
  InLoop::methods::write($h, "$d\n");
}

1;
