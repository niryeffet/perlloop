package Epoll;
use strict;

use Exporter 'import';

our @EXPORT = qw(epoll_ctl epoll_wait
                 EPOLLIN EPOLLOUT EPOLLERR EPOLLHUP EPOLLONESHOT
                 EPOLL_CTL_ADD EPOLL_CTL_DEL EPOLL_CTL_MOD);

BEGIN { require 'syscall.ph'; }

use constant EPOLL_CLOEXEC => 1<<19;
use constant {
  EPOLLIN          => 1,
  EPOLLOUT         => 4,
  EPOLLERR         => 8,
  EPOLLHUP         => 16,
  EPOLLONESHOT     => 1<<30,
  EPOLL_CTL_ADD    => 1,
  EPOLL_CTL_DEL    => 2,
  EPOLL_CTL_MOD    => 3,
  epoll_fd         => syscall(SYS_epoll_create1(), EPOLL_CLOEXEC),
  SYS_epoll_ctl    => SYS_epoll_ctl(),
  SYS_epoll_wait   => SYS_epoll_wait(),
};

sub epoll_ctl {
  syscall(SYS_epoll_ctl, epoll_fd, $_[0] + 0, $_[1] + 0, pack("LLL", $_[2], $_[1], 0));
}

our $epoll_wait_events;
our $epoll_wait_size = 0;
sub epoll_wait {
  if ($_[0] > $epoll_wait_size) {
    $epoll_wait_size = $_[0];
    $epoll_wait_events = "\0" x 12 x $epoll_wait_size;
  }
  my $ct = syscall(SYS_epoll_wait, epoll_fd, $epoll_wait_events, $_[0] + 0, $_[1] + 0);
  @{$_[2]->[$_]}[1,0] = unpack("LL", substr($epoll_wait_events, 12 * $_, 8)) for (0..$ct-1);
  return $ct;
}

1;
