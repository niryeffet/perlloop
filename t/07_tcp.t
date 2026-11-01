use strict;
use warnings;
use Socket;
use Test::More tests => 8;

use InLoop;
use TCPInLoop;

my $server_received = [];
my $clients_responded = 0;

my $server_h = tcpServer(0, '127.0.0.1', evLine {
  my $h = shift;
  push @$server_received, $_;
  $h->say("echo:$_");
});

my $port = $server_h->{port};
ok($port > 0, "IPv4 server listening on dynamic port $port");

# Connect 2 IPv4 clients concurrently
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

# Test IPv6 server and client on ::1
my $v6_received = '';
my $server_v6 = tcpServer(0, '::1', evLine {
  my $h = shift;
  $h->say("v6_echo:$_");
});
my $port_v6 = $server_v6 ? $server_v6->{port} : 0;
ok($port_v6 > 0, "IPv6 server listening on dynamic port $port_v6");

my $c_v6 = tcpClient($port_v6, '::1', evLine {
  $v6_received .= $_;
});
$c_v6->say("hello_ipv6");

# Connect client to an invalid unresolvable address
my $failed_connected = 0;
my $c_bad = tcpClient(9999, 'invalid.domain.that.does.not.exist.example', evOnce, evLine {
  $failed_connected = 1;
});
ok(defined $c_bad, 'tcpClient with invalid address created handle without crashing');

setTimeout {
  is(scalar(@$server_received), 2, 'IPv4 server received messages from both clients');
  is($clients_responded, 2, 'both IPv4 clients received echoes from server');
  like($v6_received, qr{v6_echo:hello_ipv6}, 'IPv6 client communicated successfully over ::1');
  is($failed_connected, 0, 'invalid client did not connect');
  pass('TCP communication and error handling completed cleanly');
  exitInLoop();
} 150;
