use strict;
use warnings;
use Socket;
use Test::More tests => 5;

use InLoop;

socketpair(my $reader, my $writer, AF_UNIX, SOCK_STREAM, PF_UNSPEC)
  or die "socketpair failed: $!";

my $received = '';

evOn {
  my $h = shift;
  $h->{fh} = $reader;
  1;
} evLine {
  $received .= $_;
};

my $wh = evOn {
  my $h = shift;
  $h->{fh} = $writer;
  $h->{out} = $writer;
  1;
} evOnce;

# Test say() without argument under warnings
my $warn_msg = '';
local $SIG{__WARN__} = sub { $warn_msg .= $_[0]; };
$wh->say();
is($warn_msg, '', 'say() without arguments produces no warning');

# Write a large payload that exceeds the socket buffer
my $total_bytes = 256 * 1024;
my $chunk = "A" x 1024 . "\n"; # 1025 bytes per line
my $repeat = int($total_bytes / length($chunk));
my $payload = $chunk x $repeat;
my $expected_len = length($payload) + 1; # +1 for the say() newline

$wh->write($payload);

# Wait for buffer to drain
setTimeout {
  is(length($received), $expected_len, 'all bytes delivered through buffered write');
  is(substr($received, 0, 1), "\n", 'first line was empty newline from say()');
  is(substr($received, 1), $payload, 'payload content matches perfectly');
  ok(defined $wh->{fh}, 'writer handle stayed active throughout stream');
  exitInLoop();
} 150;
