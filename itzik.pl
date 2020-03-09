use strict;
use lib '.';
use InLoop;
use TCPInLoop;

my %connected;

tcpServer(23456, '127.0.0.1', evOut {
  my $h = shift;
  # save each connection
  $connected{$h->{fh}} = $h;
  1;
} evLine {
  print "Recieved unexpected: $_";
});

# example of output to all and cleanup disconnected ones

setInterval {
  foreach my $k (keys %connected) {
    my $fh = $connected{$k}->{fh};
    if ($fh) {
      print $fh "Hello world!\n";
    } else {
      delete $connected{$k};
    }
  }
} 1000;

tcpClient(23456, '127.0.0.1', evLine { print; });

1;
