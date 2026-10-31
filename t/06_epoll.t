use strict;
use warnings;
use Test::More tests => 6;

use Epoll;

pipe(my $r, my $w) or die "pipe: $!";

my $fn = fileno($r);
ok($fn >= 0, 'valid fileno for pipe reader');

# 1. Add reader to epoll
my $ret = epoll_ctl(EPOLL_CTL_ADD, $fn, EPOLLIN);
is($ret, 0, 'epoll_ctl ADD succeeded');

# 2. epoll_wait before write (should timeout with 0 events)
my @evs;
my $ct = epoll_wait(1, 10, \@evs);
is($ct, 0, 'epoll_wait returned 0 before write');

# 3. Write data to pipe
syswrite($w, "ping\n");

# 4. epoll_wait after write (should return 1 event)
$ct = epoll_wait(1, 100, \@evs);
is($ct, 1, 'epoll_wait returned 1 event after write');
is($evs[0]->[0], $fn, 'event fd matches reader fd');

# 5. Clean up with 2 arguments (EPOLL_CTL_DEL without event argument)
my $warn_msg = '';
local $SIG{__WARN__} = sub { $warn_msg .= $_[0]; };
my $del_ret = epoll_ctl(EPOLL_CTL_DEL, $fn);
is($warn_msg, '', 'epoll_ctl with 2 arguments produces no uninitialized warning');

close($r);
close($w);
