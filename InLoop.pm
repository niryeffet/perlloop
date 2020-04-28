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
my (@fds, @evs);
my $fds = 0;

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
  }, evInRef($func));
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
  _createTimer($secs, $secs, sub {
    sysread($_, $a, 4096);
    &$func;
  });
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
  delete @$h{'open', 'outEv', 'dataOut', 'off'};
  kill 'TERM', $h->{child} if $h->{child};
  _del($h);
}

sub exitInLoop {
  evOff($_) foreach grep { defined } @fds;
  0;
}

sub _epoll_ctl {
  my ($op, $fn, $ev) = @_;
  # true when failed. Assume file, no epoll.
  epoll_ctl($op, $fn, $ev) && push @evs, [$fn, $op];
}

sub _epollCtl {
  my ($op, $h) = @_;
  my $nfh = fileno $h->{fh};
  my $nout = fileno $h->{out};
  if ($nfh == $nout) {
    _epoll_ctl($op, $nfh, $h->{outEv} ? EPOLLIN | EPOLLOUT | EPOLLONESHOT : EPOLLIN);
  } elsif ($h->{outEv} || $op != EPOLL_CTL_MOD) {
    _epoll_ctl($op, $nfh, EPOLLIN) if $op != EPOLL_CTL_MOD;
    _epoll_ctl($op, $nout, $h->{outEv} ? EPOLLOUT | EPOLLONESHOT : 0);
  }
}

sub _del { # close, allow reopening
  my $h = $_[0];
  my $fh = delete @$h{'fh'};
  return if !$fh;
  my $out = delete @$h{'child', 'out'};
  my ($nFh, $nOut) = (fileno $fh, fileno $out);
  if ($nOut != $nFh) {
    $fds[$nOut] = undef;
    if ($nOut > 2) {
      close($out);
    } else {
      # never close stdin stdout stderr
      epoll_ctl(EPOLL_CTL_DEL, $nOut);
      doBlock($out)
    }
  }
  if ($nFh > 2) {
    close($fh);
  } else {
    # never close stdin stdout stderr
    epoll_ctl(EPOLL_CTL_DEL, $nFh);
    doBlock($fh)
  }
  $fds[$nFh] = undef;
  --$fds;
}

sub _schedAdd {
  my $h = $_[0];
  return if $h->{tryOnce};
  my $w = int(($h->{openTime} - time()) * 1000 + .5) + REOPEN;
  $w > 0 ? setTimeout { _add($h); } $w : &_add;
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
  $h->{fh} = $_ if !$h->{fh};
  $h->{child} = $child if $child > 1; # pid of subprocess
  $fds[fileno nonblock($h->{fh})] = $h;
  ++$fds;
  if ($h->{out}) {
    $fds[fileno nonblock($h->{out})] = $h;
  } else {
    $h->{out} = $h->{fh};
  }
  _epollCtl(EPOLL_CTL_ADD, $h);
}

sub _hangup {
  my $h = shift;
  if ($h->{hup}->($h) && !$h->{tryOnce}) {
    _del($h);
    _schedAdd($h);
  } else {
    evOff($h);
  }
}

sub _event {
  my ($fn, $epev) = @{shift @evs};
  my $h = $fds[$fn];
  if ($epev & EPOLLERR) {
    return _hangup($h);
  }
  my $o = $h->{outEv};
  if (($epev & EPOLLOUT) && !($epev & EPOLLHUP) && $o) {
    $_ = $h->{out};
    if ($o->($h)) {
      evOutRef(undef, $h);
    } elsif ($!{EAGAIN}) {
      evOutRef($o, $h);
    } else {
      _hangup($h);
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
    my $i;
    my $d = \$h->{dataIn};
    while (sysread($fh, $$d, 4096, length($$d) + 0)) {
      while($i = index($$d, "\n") + 1) {
        $_ = substr($$d, 0, $i, '');
        $e->($h);
        return if !$fds[$fn]; # $h was deleted via evOff! bail.
      }
    }
  }

  if (!$res and !$!{EAGAIN}) {
    $e->($h) if ($_ = $h->{dataIn}) ne '';
    _hangup($h);
  } elsif ($o = $h->{outEv}) { # check outEv again, things might have shifted
    evOutRef($o, $h);
  }
}

# most simple event loop
END {
  (@evs || epoll_wait(1, -1, \@evs) == 1) && _event() while ($fds);
}

1;
