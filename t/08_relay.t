use strict;
use warnings;
use File::Temp qw(tempfile);
use Test::More tests => 7;

use InLoop;
use HidUsbRelay;

# Create mock usbrelay executable
my ($fh, $mock_path) = tempfile(UNLINK => 1);
print $fh <<'EOF';
#!/bin/sh
if [ -z "$1" ]; then
  echo "TESTBOARD_1=0"
  echo "TESTBOARD_2=1"
else
  echo "$1"
fi
EOF
close($fh);
chmod(0755, $mock_path);

$HidUsbRelay::USBRELAY_BIN = $mock_path;

my $relay = HidUsbRelay->new('TESTBOARD', {
  POWER => 1,
  LIGHT => 2,
});
isa_ok($relay, 'HidUsbRelay');

# Wait for initial state to populate from mock
setTimeout {
  is($relay->{state}->{1}, '0', 'relay 1 initialized to 0');
  is($relay->{state}->{2}, '1', 'relay 2 initialized to 1');

  # Test synchronous state query without callback
  is($relay->state('POWER'), '0', 'synchronous state query returns 0 for POWER');
  is($relay->state('LIGHT'), '1', 'synchronous state query returns 1 for LIGHT');

  # Turn POWER on
  $relay->on('POWER');
  is($relay->{state}->{1}, '1', 'relay 1 switched to 1 via on()');

  # Press button (turns on then back off after BUTTON_PRESS ms)
  $relay->button('LIGHT');
} 50;

setTimeout {
  # After button press duration, LIGHT should be back off (0)
  is($relay->{state}->{2}, '0', 'relay 2 reset back to 0 after button press');
  exitInLoop();
} 400;
