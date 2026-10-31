use strict;
use warnings;

package InLoop;
our $VERSION = '0.02';
use File::Basename 'dirname';
use Cwd 'abs_path';
use lib dirname(abs_path(__FILE__));
use Epoll;
use Time::HiRes 'time';
use Linux::FD::Timer;
use IO::Handle;
use Fcntl;
use InLoop::methods;
use Errno qw(EAGAIN);
use Scalar::Util 'looks_like_number';

use Exporter 'import';
our @EXPORT = qw(setTimeout setInterval nonblock exitInLoop
                 evOn evLine evHup evIn evOut evOnce evLineOnly evEmpty
                 evMaxLine evReopen);

use constant {
 REOPEN => 1000, # reopen attempt after n ms
 SUBOK => sub { 1; },
 SUBNOP => sub { }
};

my (@fds, @evs);
my $fds = 0;

#ignore some signals, event will rise
$SIG{HUP} = $SIG{PIPE} = 'IGNORE';

sub getOpenTime {
  $_[0]->{openTime};
}

sub _createTimer {
  my ($value, $interval, $func, @opts) = @_;
  evOn(sub {
    $_ = Linux::FD::Timer->new('monotonic') or return 0;
    defined($interval) ? $_->set_timeout($value, $interval) : $_->set_timeout($value);
    1;
  }, evInRef($func), @opts);
}

sub setTimeout (&$) {
  my ($func, $ms) = @_;
  my $secs = ($ms && $ms > 0) ? ($ms / 1000) : 0.001;
  _createTimer($secs, undef, sub {
    my $h = shift;
    &$func;
    evOff($h);
    1;
  }, evOnce());
}

sub setInterval (&$) {
  my ($func, $ms) = @_;
  my $secs = ($ms && $ms > 0) ? ($ms / 1000) : 0.001;
  _createTimer($secs, $secs, sub {
    my $tmp;
    sysread($_, $tmp, 4096);
    &$func;
    1;
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
  $h->{hup} ||= SUBOK;
  $h->{inEv} ||= SUBNOP;
  _add($h, time());
  $h;
}

sub evEmpty {
  bless {}, "InLoop::methods";
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
sub evLineOnly (@) {
  my $h = &_agEv;
  $h->{lineOnly} = 1;
  $h;
}

sub evMaxLine ($@) {
  my $max = shift;
  my $h = &_agEv;
  $h->{maxLine} = $max;
  $h;
}

sub evReopen ($@) {
  my $ms = shift;
  my $h = &_agEv;
  $h->{reopen} = $ms;
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
  @evs = ();
  0;
}

sub _epoll_ctl {
  my ($op, $fn, $ev) = @_;
  # true when failed. Assume file - no epoll.
  epoll_ctl($op, $fn, $ev) && push @evs, [$fn, $ev];
}

sub _epollCtl {
  my ($op, $h) = @_;
  my $nfh = fileno $h->{fh};
  my $nout = fileno $h->{out};
  my $r = 0;
  if ($nfh == $nout) {
    $r = _epoll_ctl($op, $nfh, $h->{outEv} ? EPOLLIN | EPOLLOUT | EPOLLONESHOT : EPOLLIN);
  } elsif ($h->{outEv} || $op != EPOLL_CTL_MOD) {
    $r = _epoll_ctl($op, $nfh, EPOLLIN) if $op != EPOLL_CTL_MOD;
    _epoll_ctl($op, $nout, $h->{outEv} ? EPOLLOUT | EPOLLONESHOT : 0);
  }
  $h->{EOFErr} = $r ? 0 : EAGAIN;
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
      $h->{exitStatus} = $?;
      $h->{exitCode} = $? >> 8;
      $? = 0;
    } else {
      # never close stdin stdout stderr
      epoll_ctl(EPOLL_CTL_DEL, $nOut);
      doBlock($out)
    }
  }
  if ($nFh > 2) {
    close($fh);
    $h->{exitStatus} = $? unless exists $h->{exitStatus};
    $h->{exitCode} = $? >> 8 unless exists $h->{exitCode};
    $? = 0;
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
  return if $h->{tryOnce} || !$h->{open};
  my $t = time();
  my $reopen = defined($h->{reopen}) ? $h->{reopen} : REOPEN;
  my $w = int(($h->{openTime} - $t) * 1000 + .5) + $reopen;
  $w > 0 ? setTimeout { _add($h, time()); } $w : _add($h, $t);
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
  $h->{openTime} = $_[1];
  local $_;
  my $child = $s->($h);
  if (defined $child) {
    $child = open($h->{fh}, $child) if !looks_like_number($child) && $child ne '';
    $child or $!{EINPROGRESS} or return &_schedAdd;
    $h->{child} = $child if looks_like_number($child) && $child > 1; # pid of subprocess
  } else {
    $!{EINPROGRESS} or return &_schedAdd;
  }
  $h->{fh} ||= $_;
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
  _del($h);
  if ($h->{hup}->($h) && !$h->{tryOnce}) {
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
    my ($i, $r);
    my $d = \$h->{dataIn};
    $$d = '' unless defined $$d;
    my $maxLine = $h->{maxLine};
    while ($r = sysread($fh, $$d, 4096, length($$d))) {
      while($i = index($$d, "\n") + 1) {
        $_ = substr($$d, 0, $i, '');
        $e->($h);
        return if !$fds[$fn]; # $h was deleted via evOff! bail.
      }
      if ($maxLine && length($$d) > $maxLine) {
        $$d = '';
        _hangup($h);
        return;
      }
      if ($r < 4096) {
        $! = $h->{EOFErr};
        last;
      }
    }
    if (!$h->{lineOnly} && ($_ = $$d) ne '') {
      $$d = '';
      my $err = $!;
      $e->($h);
      $! = $err;
    }
  }
  if (!$res and !$!{EAGAIN}) {
    _hangup($h);
  } elsif ($o = $h->{outEv}) { # check outEv again, things might have shifted
    evOutRef($o, $h);
  }
}

# event loop
END {
  (@evs || epoll_wait(1, -1, \@evs) == 1) && _event() while ($fds);
}

1;

__END__

=head1 NAME

InLoop - Lightweight event-driven asynchronous I/O framework for Linux

=head1 SYNOPSIS

  use InLoop;

  # Read lines from a command pipe with automatic reconnection
  evOn {
    'tail -f /var/log/syslog|'
  } evLine {
    print "Log line: $_";
  };

  # One-shot timer
  setTimeout {
    print "Executed after 500ms\n";
  } 500;

  # Periodic interval
  my $timer = setInterval {
    print "Tick\n";
  } 1000;

  # Stop timer
  $timer->evOff;

  # Exit the event loop
  exitInLoop();

=head1 DESCRIPTION

InLoop provides an asynchronous event loop for Linux using direct Linux
epoll and timerfd primitives with zero external C dependencies.

Event monitoring begins as soon as handles are declared and starts running
automatically in an END block, avoiding boilerplate run-loop invocations.

=head1 FUNCTIONS

=over 4

=item B<evOn { ... } @methods>

Registers an asynchronous source. The code block executes to create the
filehandle or child process. Automatically reconnects on close unless
paired with C<evOnce>.

=item B<evLine { ... }>

Processes incoming input in line-buffered mode.

=item B<evLineOnly>

Optional modifier. Only dispatches complete newline-terminated lines.

=item B<evMaxLine($bytes)>

Optional modifier. Enforces a maximum buffer limit for lines without newlines.

=item B<evReopen($ms)>

Optional modifier. Configures reconnect delay in milliseconds.

=item B<setTimeout { ... } $ms>

Executes a callback once after the specified millisecond delay.

=item B<setInterval { ... } $ms>

Executes a callback repeatedly every C<$ms> milliseconds.

=item B<exitInLoop()>

Closes all active handles and terminates the event loop.

=back

=head1 AUTHOR

Nir Yeffet

=head1 LICENSE

Same as Perl itself.

=cut
