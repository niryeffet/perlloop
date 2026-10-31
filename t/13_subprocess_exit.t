use strict;
use warnings;
use Test::More tests => 2;

use InLoop;

my $code_zero;
my $code_custom;

# 1. Subprocess that exits 0
evOnce evOn {
  open($_, "-|", $^X, "-e", "exit 0");
} evHup {
  my $h = shift;
  $code_zero = $h->{exitCode};
};

# 2. Subprocess that exits 42
evOnce evOn {
  open($_, "-|", $^X, "-e", "exit 42");
} evHup {
  my $h = shift;
  $code_custom = $h->{exitCode};
};

setTimeout {
  is($code_zero, 0, 'successful subprocess exitCode captured as 0');
  is($code_custom, 42, 'custom subprocess exitCode captured as 42');
  exitInLoop();
} 150;
