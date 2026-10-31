use strict;
use warnings;
use File::Basename 'dirname';
use File::Spec;
use Cwd 'abs_path';
use Test::More tests => 10;

# Declare variables used across the script
our ($server, %byName);

# Configure test environment for chatroom
$ENV{CHATROOM_PORT} = 0;      # Dynamic ephemeral port
$ENV{CHATROOM_CONSOLE} = 0;   # Disable STDIN/STDOUT console

my $chatroom_script = abs_path(File::Spec->catfile(dirname(__FILE__), '..', 'eg', 'chatroom.pl'));
require $chatroom_script;

use InLoop;
use TCPInLoop;

my $port = $server->{port};
ok($port > 0, "chatroom server listening on port $port");

my $alice_buf = [];
my $bob_buf   = [];

# Helper to check if any message in buffer matches regex
sub match_buf {
  my ($buf, $regex) = @_;
  return grep { $_ =~ $regex } @$buf;
}

# Connect Alice
my $alice = tcpClient($port, '127.0.0.1', evLine {
  push @$alice_buf, $_;
});

# Connect Bob
my $bob = tcpClient($port, '127.0.0.1', evLine {
  push @$bob_buf, $_;
});

# Step 1: Set names
setTimeout {
  $alice->say('/name alice');
  $bob->say('/name bob');
} 50;

# Step 2: Test public chat & private message
setTimeout {
  ok(match_buf($alice_buf, qr/bob is now connected/), 'alice saw bob connect');

  $alice->say('hello chatroom');
  $alice->say('/msg bob secret_note');
} 150;

# Step 3: Test operator commands & ban
setTimeout {
  ok(match_buf($bob_buf, qr/alice: hello chatroom/), 'bob received public message');
  ok(match_buf($bob_buf, qr/alice\(privately\): secret_note/), 'bob received private message');

  # Grant op status to alice
  $byName{alice}->{op} = 1;

  # Alice ops bob and queries ops
  $alice->say('/op bob');
  $alice->say('/ops');
} 250;

# Step 4: Verify op status and test ban
setTimeout {
  ok(match_buf($bob_buf, qr/alice op'ed you/), 'bob received op notification');
  ok(match_buf($alice_buf, qr/alice, bob/), 'alice saw ops list');

  # Alice bans bob
  $alice->say('/ban bob');
} 350;

# Step 5: Verify bob banned, test /help, and test /who
setTimeout {
  ok(match_buf($alice_buf, qr/system: bob was banned by alice/), 'alice saw bob banned notification');

  $alice->say('/help');
  $alice->say('/who');
  $alice->say('/who am i');
} 450;

# Final verification and clean exit
setTimeout {
  ok(match_buf($alice_buf, qr/Available commands:/), 'alice received help text');
  ok(match_buf($alice_buf, qr/system: alice$/), 'who shows only alice');
  ok(match_buf($alice_buf, qr/^alice$/), 'who am i returns alice');

  $alice->say('/bye');
  exitInLoop();
} 550;
