use strict;
use warnings;
use Socket;
use Test::More tests => 6;

use InLoop;
use TCPInLoop;

my $server_received = [];
my $clients_responded = 0;

my $server_h;
$server_h = tcpServer(0, '127.0.0.1', evLine {
  my $h = shift;
  push @$server_received, $_;
  $h->say("echo:$_");
});

# Retrieve assigned ephemeral port
my $port = $server_h->{port};
ok($port > 0, "server listening on dynamic port $port");

# Connect 2 clients concurrently
my $c1 = tcpClient($port, '127.0.0.1', evLine {
  if (/^echo:client1_msg/) {
    $clients_responded++;
  }
});
$c1->say("client1_msg");

my $c2 = tcpClient($port, '127.0.0.1', evLine {
  if (/^echo:client2_msg/) {
    $clients_responded++;
  }
});
$c2->say("client2_msg");

# Connect client to an invalid unresolvable address
my $failed_connected = 0;
my $c_bad = tcpClient(9999, 'invalid.domain.that.does.not.exist.example', evOnce, evLine {
  $failed_connected = 1;
});
ok(defined $c_bad, 'tcpClient with invalid address created handle without crashing');

setTimeout {
  is(scalar(@$server_received), 2, 'server received messages from both clients');
  is($clients_responded, 2, 'both clients received echoes from server');
  is($failed_connected, 0, 'invalid client did not connect');
  pass('TCP communication and error handling completed cleanly');
  exitInLoop();
} 150;
