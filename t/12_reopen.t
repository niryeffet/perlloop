use strict;
use warnings;
use Test::More tests => 2;

use InLoop;

my $attempts = 0;
my $start_time = Time::HiRes::time();
my $second_attempt_time;

evOn {
  $attempts++;
  if ($attempts == 2) {
    $second_attempt_time = Time::HiRes::time();
  }
  # Fail open immediately to trigger reopen
  0;
} evReopen 50, evHup {
  # return 1 to allow retry
  1;
};

setTimeout {
  is($attempts >= 2, 1, 'handle attempted reopen after initial failure');
  my $elapsed = ($second_attempt_time - $start_time) * 1000;
  # Default REOPEN is 1000ms. With evReopen 50ms, it should reopen well under 300ms.
  ok($elapsed < 300, "reopened quickly within ${elapsed}ms (configured for 50ms)");
  exitInLoop();
} 150;
