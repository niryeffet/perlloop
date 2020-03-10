use strict;
use lib '.';
use InLoop;
use TCPInLoop;

my %connected;

tcpServer(23456, '127.0.0.1', evOut {
  my $h = shift;
  $connected{$h->{fh}} = $h;
  1;
} evHup {
  delete $connected{shift->{fh}};
} evLine {
  print "Recieved unexpected: $_";
});

# example of output to all
setInterval {
  # writing to a socket may fail
  eval { print { $_->{fh} } "Hello world!\n" } foreach values %connected;
} 1000;

tcpClient(23456, '127.0.0.1', evLine { print; });

1;
