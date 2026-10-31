use strict;
use warnings;
use Test::More tests => 5;

use InLoop;

my $timeout_fired = 0;
my $zero_timeout_fired = 0;
my $cancelled_fired = 0;
my $interval_count = 0;

# 1. Test setTimeout
setTimeout {
  $timeout_fired++;
} 10;

# 2. Test zero-delay next-tick setTimeout
setTimeout {
  $zero_timeout_fired++;
} 0;

# 3. Test cancelled setTimeout
my $to_cancel = setTimeout {
  $cancelled_fired++;
} 30;
$to_cancel->evOff;

# 4. Test setInterval and evOff
my $interval_timer;
$interval_timer = setInterval {
  $interval_count++;
  if ($interval_count >= 3) {
    $interval_timer->evOff;
  }
} 10;

# Check after all timers should have settled
setTimeout {
  is($zero_timeout_fired, 1, 'zero-delay setTimeout fired as next tick');
  is($timeout_fired, 1, 'setTimeout fired exactly once');
  is($cancelled_fired, 0, 'cancelled setTimeout did not fire');
  is($interval_count, 3, 'setInterval fired 3 times and was stopped');
  pass('event loop completed cleanly without hanging');
} 60;
