use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Spec;
use Test::More tests => 6;

use InLoop;
use UNIXInLoop;

my $tmpdir = tempdir(CLEANUP => 1);
my $sock_path = File::Spec->catfile($tmpdir, 'test.sock');

my $server_received = [];
my $clients_responded = 0;

my $server = unixServer($sock_path, evLine {
  my $h = shift;
  chomp;
  push @$server_received, $_;
  $h->say("unix_echo:$_");
});

ok(defined $server, 'unixServer started successfully');
ok(-S $sock_path, 'UNIX domain socket file created on filesystem');

# Connect 2 clients concurrently
my $c1_received = '';
my $c1 = unixClient($sock_path, evLine {
  $c1_received .= $_;
  $clients_responded++;
});
$c1->say("client1_data");

my $c2_received = '';
my $c2 = unixClient($sock_path, evLine {
  $c2_received .= $_;
  $clients_responded++;
});
$c2->say("client2_data");

setTimeout {
  is(scalar(@$server_received), 2, 'server received messages from both clients');
  is($clients_responded, 2, 'both clients received responses from unixServer');
  like($c1_received, qr{unix_echo:client1_data}, 'client 1 received correct echo');
  like($c2_received, qr{unix_echo:client2_data}, 'client 2 received correct echo');
  exitInLoop();
} 150;
