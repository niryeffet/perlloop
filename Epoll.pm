package Epoll;
use strict;
use POSIX;
use Exporter 'import';

our @EXPORT = qw(epoll_ctl epoll_wait
                 EPOLLIN EPOLLOUT EPOLLERR EPOLLHUP EPOLLONESHOT
                 EPOLL_CTL_ADD EPOLL_CTL_DEL EPOLL_CTL_MOD);

BEGIN { require 'syscall.ph'; }

use constant EPOLL_CLOEXEC => 1<<19;
use constant {
  EPOLLIN        => 1,
  EPOLLOUT       => 4,
  EPOLLERR       => 8,
  EPOLLHUP       => 16,
  EPOLLONESHOT   => 1<<30,
  EPOLL_CTL_ADD  => 1,
  EPOLL_CTL_DEL  => 2,
  EPOLL_CTL_MOD  => 3,
  EPOLL_FD       => syscall(SYS_epoll_create1(), EPOLL_CLOEXEC),
  SYS_EPOLL_CTL  => SYS_epoll_ctl(),
  # raspberry pi / bullseye / aarch64 is missing SYS_epoll_wait. epoll_pwait will do.
  SYS_EPOLL_WAIT => eval { SYS_epoll_wait() } || SYS_epoll_pwait(),
};

sub epoll_ctl1 {
  syscall(SYS_EPOLL_CTL, EPOLL_FD, $_[0] + 0, $_[1] + 0, pack("LLL", $_[2], $_[1], 0));
}
sub epoll_ctl2 {
  syscall(SYS_EPOLL_CTL, EPOLL_FD, $_[0] + 0, $_[1] + 0, pack("LLLL", $_[2], 0, $_[1], 0));
}

our $epoll_wait_events;
our $epoll_wait_size = 0;

sub epoll_wait1 {
  if ($_[0] > $epoll_wait_size) {
    $epoll_wait_size = $_[0];
    $epoll_wait_events = "\0" x 12 x $epoll_wait_size;
  }
  my $ct = syscall(SYS_EPOLL_WAIT, EPOLL_FD, $epoll_wait_events, $_[0] + 0, $_[1] + 0);
  @{$_[2]->[$_]}[1, 0] = unpack("LL", substr($epoll_wait_events, 12 * $_, 8)) for (0 .. $ct-1);
  return $ct;
}

sub epoll_wait2 {
  if ($_[0] > $epoll_wait_size) {
    $epoll_wait_size = $_[0];
    $epoll_wait_events = "\0" x 16 x $epoll_wait_size;
  }
  my $ct = syscall(SYS_EPOLL_WAIT, EPOLL_FD, $epoll_wait_events, $_[0] + 0, $_[1] + 0);
  @{$_[2]->[$_]}[1, 2, 0] = unpack("LLL", substr($epoll_wait_events, 16 * $_, 12)) for (0 .. $ct-1);
  return $ct;
}

if ((POSIX::uname())[4] =~ m/armv\d/) {
  *epoll_ctl = \&epoll_ctl2;
  *epoll_wait = \&epoll_wait2;
} else {
  *epoll_ctl = \&epoll_ctl1;
  *epoll_wait = \&epoll_wait1;
}

1;
