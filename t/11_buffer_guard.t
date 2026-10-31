use strict;
use warnings;
use Test::More tests => 3;

use InLoop;

pipe(my $reader, my $writer) or die "pipe: $!";

my $received_lines = [];
my $hung_up = 0;

my $h = evOn {
  my $h = shift;
  $h->{fh} = $reader;
  1;
} evMaxLine 100, evLine {
  push @$received_lines, $_;
} evHup {
  $hung_up = 1;
};

# Send a valid line (under 100 bytes)
syswrite($writer, "valid short line\n");

setTimeout {
  is(scalar(@$received_lines), 1, 'received valid line under maxLine limit');
  is($received_lines->[0], "valid short line\n", 'line content matches');

  # Now flood with 200 bytes without any newline
  syswrite($writer, "X" x 200);
} 50;

setTimeout {
  ok($hung_up, 'handle was hung up after exceeding maxLine limit');
  exitInLoop();
} 150;
