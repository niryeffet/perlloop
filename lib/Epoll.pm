package Epoll;
use strict;
use warnings;
our $VERSION = '0.02';
use POSIX;
use Exporter 'import';

our @EXPORT = qw(epoll_ctl epoll_wait
                 EPOLLIN EPOLLOUT EPOLLERR EPOLLHUP EPOLLONESHOT
                 EPOLL_CTL_ADD EPOLL_CTL_DEL EPOLL_CTL_MOD);

my ($sys_create1, $sys_ctl, $sys_wait, $sys_pwait, $use_pwait, $arch);

BEGIN {
  eval { require 'syscall.ph'; 1 };

  $arch = (POSIX::uname())[4];

  sub _get_syscall_nr {
    my ($name, $fallbacks) = @_;
    my $val = eval "$name()";
    return $val if defined $val;
    return $fallbacks->{$arch} if exists $fallbacks->{$arch};
    if ($arch =~ /^arm/) { return $fallbacks->{arm} if exists $fallbacks->{arm}; }
    return undef;
  }

  $sys_create1 = _get_syscall_nr('SYS_epoll_create1', {
    x86_64 => 291, aarch64 => 20, arm => 357, i386 => 329, i686 => 329,
  }) or die "Cannot determine SYS_epoll_create1";

  $sys_ctl = _get_syscall_nr('SYS_epoll_ctl', {
    x86_64 => 233, aarch64 => 21, arm => 251, i386 => 255, i686 => 255,
  }) or die "Cannot determine SYS_epoll_ctl";

  $sys_wait = _get_syscall_nr('SYS_epoll_wait', {
    x86_64 => 232, arm => 250, i386 => 256, i686 => 256,
  });

  $sys_pwait = _get_syscall_nr('SYS_epoll_pwait', {
    x86_64 => 281, aarch64 => 22, arm => 346, i386 => 319, i686 => 319,
  });

  $use_pwait = !$sys_wait;
}

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
  EPOLL_FD       => syscall($sys_create1, EPOLL_CLOEXEC),
  SYS_EPOLL_CTL  => $sys_ctl,
  SYS_EPOLL_WAIT => $sys_wait || $sys_pwait,
};

sub epoll_ctl1 {
  syscall(SYS_EPOLL_CTL, EPOLL_FD, $_[0] + 0, $_[1] + 0, pack("LLL", $_[2] || 0, $_[1] + 0, 0));
}
sub epoll_ctl2 {
  syscall(SYS_EPOLL_CTL, EPOLL_FD, $_[0] + 0, $_[1] + 0, pack("LLLL", $_[2] || 0, 0, $_[1] + 0, 0));
}

our $epoll_wait_events;
our $epoll_wait_size = 0;

sub epoll_wait1 {
  if ($_[0] > $epoll_wait_size) {
    $epoll_wait_size = $_[0];
    $epoll_wait_events = "\0" x 12 x $epoll_wait_size;
  }
  my $ct = $use_pwait
    ? syscall(SYS_EPOLL_WAIT, EPOLL_FD, $epoll_wait_events, $_[0] + 0, $_[1] + 0, 0, 0)
    : syscall(SYS_EPOLL_WAIT, EPOLL_FD, $epoll_wait_events, $_[0] + 0, $_[1] + 0);
  if ($ct < 0) {
    if ($!{EINTR}) {
      $! = 0;
      return 0;
    }
    return $ct;
  }
  @{$_[2]->[$_]}[1, 0] = unpack("LL", substr($epoll_wait_events, 12 * $_, 8)) for (0 .. $ct-1);
  return $ct;
}

sub epoll_wait2 {
  if ($_[0] > $epoll_wait_size) {
    $epoll_wait_size = $_[0];
    $epoll_wait_events = "\0" x 16 x $epoll_wait_size;
  }
  my $ct = $use_pwait
    ? syscall(SYS_EPOLL_WAIT, EPOLL_FD, $epoll_wait_events, $_[0] + 0, $_[1] + 0, 0, 0)
    : syscall(SYS_EPOLL_WAIT, EPOLL_FD, $epoll_wait_events, $_[0] + 0, $_[1] + 0);
  if ($ct < 0) {
    if ($!{EINTR}) {
      $! = 0;
      return 0;
    }
    return $ct;
  }
  @{$_[2]->[$_]}[1, 2, 0] = unpack("LLL", substr($epoll_wait_events, 16 * $_, 12)) for (0 .. $ct-1);
  return $ct;
}

if ($arch =~ m/^(arm|aarch64|riscv)/) {
  *epoll_ctl = \&epoll_ctl2;
  *epoll_wait = \&epoll_wait2;
} else {
  *epoll_ctl = \&epoll_ctl1;
  *epoll_wait = \&epoll_wait1;
}

1;
