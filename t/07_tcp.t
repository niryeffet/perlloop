use strict;
use warnings;
use Socket;
use Test::More tests => 12;

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

# Test dual-stack server listening on default wildcard (no address specified)
my $default_v4_received = '';
my $default_v6_received = '';
my $server_default = tcpServer(0, undef, evLine {
  my $h = shift;
  $h->say("default_echo:$_");
});
my $port_default = $server_default ? $server_default->{port} : 0;
ok($port_default > 0, "default server listening on dynamic dual-stack port $port_default");

# Connect IPv4 client to default dual-stack server
my $c_def_v4 = tcpClient($port_default, '127.0.0.1', evLine {
  $default_v4_received .= $_;
});
$c_def_v4->say("from_v4_client");

# Connect IPv6 client to the SAME default dual-stack server
my $c_def_v6 = tcpClient($port_default, '::1', evLine {
  $default_v6_received .= $_;
});
$c_def_v6->say("from_v6_client");

# Test 'loopback' mode (listens on both ::1 and 127.0.0.1 on the same port)
my $loopback_v4_received = '';
my $loopback_v6_received = '';
my $server_loopback = tcpServer(0, 'loopback', evLine {
  my $h = shift;
  $h->say("loopback_echo:$_");
});
my $port_loopback = $server_loopback ? $server_loopback->{port} : 0;
ok($port_loopback > 0, "loopback server listening on dynamic port $port_loopback");

# Connect IPv4 client to loopback server
my $c_lb_v4 = tcpClient($port_loopback, '127.0.0.1', evLine {
  $loopback_v4_received .= $_;
});
$c_lb_v4->say("from_loopback_v4");

# Connect IPv6 client to loopback server
my $c_lb_v6 = tcpClient($port_loopback, '::1', evLine {
  $loopback_v6_received .= $_;
});
$c_lb_v6->say("from_loopback_v6");

# Connect client to an invalid unresolvable address
my $failed_connected = 0;
my $c_bad = tcpClient(9999, 'invalid.domain.that.does.not.exist.example', evOnce, evLine {
  $failed_connected = 1;
});
ok(defined $c_bad, 'tcpClient with invalid address created handle without crashing');

setTimeout {
  is(scalar(@$server_received), 2, 'IPv4 server received messages from both clients');
  is($clients_responded, 2, 'both IPv4 clients received echoes from server');
  like($default_v4_received, qr{default_echo:from_v4_client}, 'default server accepted IPv4 client');
  like($default_v6_received, qr{default_echo:from_v6_client}, 'default server accepted IPv6 client');
  like($loopback_v4_received, qr{loopback_echo:from_loopback_v4}, 'loopback server accepted IPv4 client on 127.0.0.1');
  like($loopback_v6_received, qr{loopback_echo:from_loopback_v6}, 'loopback server accepted IPv6 client on ::1');
  is($failed_connected, 0, 'invalid client did not connect');
  pass('TCP communication and error handling completed cleanly');
  exitInLoop();
} 150;
