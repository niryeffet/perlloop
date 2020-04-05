use strict;

package InLoop;
use lib '.';
use Epoll;
use Time::HiRes 'time';
use Linux::FD::Timer;
use IO::Handle;
use Fcntl;
use InLoop::methods;

use Exporter 'import';
our @EXPORT = qw(setTimeout setInterval nonblock exitInLoop
                 evOn evLine evHup evIn evOut evOnce evOpen);

use constant REOPEN => 1000; # reopen attempt after n ms
my @fds;

#ignore some signals, event will rise
$SIG{HUP} = $SIG{PIPE} = $SIG{CHLD} = 'IGNORE';

sub getOpenTime {
  $_[0]->{openTime};
}

sub _createTimer {
  my ($value, $interval, $func) = @_;
  evOn(sub {
    $_ = Linux::FD::Timer->new('monotonic') or return 0;
    $_->set_timeout($value, $interval);
    1;
  }, evLineRef($func));
}

sub setTimeout (&$) {
  my ($func, $ms) = @_;
  _createTimer($ms / 1000, undef, sub {
    &$func;
    &evOff;
  });
}

sub setInterval (&$) {
  my ($func, $ms) = @_;
  my $secs = $ms / 1000;
  _createTimer($secs, $secs, $func);
}

sub _agEv {
  my $h = shift || {};
  @{$h}{keys %$_} = values %$_ foreach @_;
  $h;
}

sub evOnRef {
  my $open = shift;
  my $h = _agEv({}, @_); # always new obj
  bless $h, "InLoop::methods";
  $h->{open} = $open;
  $h->{hup} = sub { 1; } if !$h->{hup};
  $h->{inEv} = sub { } if !$h->{inEv};
  _add($h);
  $h;
}

sub evLineRef {
  my $inEv = shift;
  my $h = &_agEv;
  $h->{inEv} = $inEv;
  $h->{inMode} = 0;
  $h;
}

sub evHupRef {
  my $hup = shift;
  my $h = &_agEv;
  $h->{hup} = $hup;
  $h;
}

sub evOutRef {
  my $outEv = shift;
  my $h = &_agEv;
  $h->{outEv} = $outEv;
  _epollCtl(EPOLL_CTL_MOD, $h) if $h->{fh};
  $h;
}

sub evInRef {
  my $inEv = shift;
  my $h = &_agEv;
  $h->{inEv} = $inEv;
  $h->{inMode} = 1;
  $h;
}

sub evOn (&;@) { goto &evOnRef; }
sub evLine (&;@) { goto &evLineRef; }
sub evHup (&;@) { goto &evHupRef; }
sub evOut (&;@) { goto &evOutRef; }
sub evIn (&;@) { goto &evInRef; }
sub evOnce (@) {
  my $h = &_agEv;
  $h->{tryOnce} = 1;
  $h;
}

sub evOff ($) {
  my $h = $_[0];
  delete $h->{open};
  delete $h->{outEv};
  delete $h->{out};
  kill 'TERM', $h->{child} if $h->{child};
  _del($h);
}

sub exitInLoop {
  evOff($_) foreach grep { defined } @fds;
  0;
}

sub _epollCtl {
  my ($op, $h) = @_;
  epoll_ctl($op, fileno $h->{fh}, $h->{outEv} ? EPOLLIN | EPOLLOUT | EPOLLONESHOT : EPOLLIN);
}

sub _del { # close, allow reopening
  my $h = $_[0];
  delete $h->{child};
  my $fh = delete $h->{fh};
  return 0 if !$fh;
  my $fn = fileno $fh;
  delete $fds[$fn];
  if ($fn > 2) {
    close($fh);
  } else {
    # never close stdin stdout stderr
    epoll_ctl(EPOLL_CTL_DEL, $fn);
  }
}

sub _schedAdd {
  my $h = $_[0];
  return if $h->{tryOnce};
  my $w = int(($h->{openTime} - time()) * 1000 + .5) + REOPEN;
  $w > 0 ? setTimeout { _add($h); } $w : &_add;
}

sub _reopen {
  &_del;
  &_schedAdd;
}

sub doBlock {
  my $fh = shift;
  fcntl($fh, F_SETFL, fcntl($fh, F_GETFL, 0) & ~O_NONBLOCK);
  $fh;
}

sub nonblock {
  my $fh = shift;
  fcntl($fh, F_SETFL, fcntl($fh, F_GETFL, 0) | O_NONBLOCK);
  $fh;
}

sub _add {
  my $h = $_[0];
  my $s = $h->{open};
  return if !$s;
  $h->{openTime} = time();
  my $child;
  undef $_;
  ($child = $s->($h)) or $!{EINPROGRESS} or return &_schedAdd;
  $h->{fh} = $_ if $_ and !$h->{fh};
  $h->{child} = $child if $child > 1; # pid of subprocess
  my $fh = nonblock($h->{fh});
  $fh->autoflush;
  my $fn = fileno $fh;
  $fds[$fn] = $h;
  _epollCtl(EPOLL_CTL_ADD, $h);
}

sub _event {
  my ($fn, $epev) = @{$_[0]};
  my $h = $fds[$fn];
  my $o = $h->{outEv};
  # err and hup are ignored - err are rare, and will fail also on read, hup anyway may have data to consume.
  if ($epev & EPOLLOUT) {
    $_ = $h->{out} || $h->{fh};
    if ($o->($h)) {
      evOutRef(undef, $h);
    } elsif ($!{EAGAIN}) {
      evOutRef($o, $h);
    } else {
      _reopen($h);
    }
    return;
  }
  my $e = $h->{inEv};
  my $res;
  if ($h->{inMode}) {
    $_ = $h->{fh};
    $res = $e->($h);
  } else {
    my $fh = $h->{fh};
    my $fn = fileno $fh;
    while (<$fh>) {
      $e->($h);
      return if !$fds[$fn]; # $h was deleted via evOff! bail.
    }
  }
  if (!$res and !$!{EAGAIN}) {
    if ($h->{hup}->($h) && !$h->{tryOnce}) {
      _reopen($h);
    } else {
      evOff($h);
    }
  } elsif ($o = $h->{outEv}) { # check outEv again, things might have shifted
    evOutRef($o, $h);
  }
}

# attempt to correct STDIN before exit
END {
  doBlock(*STDIN);
}

# most simple event loop
END {
  my @evs;
  epoll_wait(1, -1, \@evs) == 1 && _event(shift @evs) while (@fds);
}

1;
