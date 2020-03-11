package Epoll;
use strict;

use Exporter 'import';

our @EXPORT = qw(epoll_ctl epoll_create epoll_wait
                 EPOLLIN EPOLLOUT EPOLLERR EPOLLHUP EPOLLONESHOT
                 EPOLL_CTL_ADD EPOLL_CTL_DEL EPOLL_CTL_MOD);

use constant EPOLLIN       => 1;
use constant EPOLLOUT      => 4;
use constant EPOLLERR      => 8;
use constant EPOLLHUP      => 16;
use constant EPOLLONESHOT  => 1<<30;
use constant EPOLL_CTL_ADD => 1;
use constant EPOLL_CTL_DEL => 2;
use constant EPOLL_CTL_MOD => 3;

eval { require 'syscall.ph'; 1; } || require 'sys/syscall.ph';

sub epoll_create {
  syscall(&SYS_epoll_create, $_[0] + 0);
}

sub epoll_ctl {
  syscall(&SYS_epoll_ctl, $_[0] + 0, $_[1] + 0, $_[2] + 0, pack("LLL", $_[3], $_[2], 0));
}

our $epoll_wait_events;
our $epoll_wait_size = 0;
sub epoll_wait {
  if ($_[1] > $epoll_wait_size) {
    $epoll_wait_size = $_[1];
    $epoll_wait_events = "\0" x 12 x $epoll_wait_size;
  }
  my $ct = syscall(&SYS_epoll_wait, $_[0] + 0, $epoll_wait_events, $_[1] + 0, $_[2] + 0);
  for (0..$ct-1) {
    @{$_[3]->[$_]}[1,0] = unpack("LL", substr($epoll_wait_events, 12 * $_, 8));
  }
  return $ct;
}

1;
