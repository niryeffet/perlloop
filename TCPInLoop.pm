use strict;

package TCPInLoop;
use Socket;
use lib '.';
use InLoop;

use Exporter 'import';
our @EXPORT = qw(tcpServer tcpClient);

sub tcpClient {
  my $port = shift;
  my $address = shift;
  evOn {
    socket($_, PF_INET, SOCK_STREAM, (getprotobyname('tcp'))[2]);
    connect(nonblock($_), sockaddr_in($port, inet_aton($address)));
  } @_;
}

sub tcpServer {
  my $port = shift() + 0;
  my $address = shift || '0.0.0.0';
  my $evMethods = evOnce ({}, @_);

  evOn {
    my $h = shift;
    socket($_, PF_INET, SOCK_STREAM, (getprotobyname('tcp'))[2]) or return 0;
    setsockopt($_, SOL_SOCKET, SO_REUSEADDR, 1) and
    bind($_, pack_sockaddr_in($port, inet_aton($address))) and
    ($h->{port} = $port || (sockaddr_in(getsockname($_)))[0]) and
    listen($_, 128) or (print(STDERR "can't bind or listen: $!\n"), close($_), return 0);
  } evIn {
    my $s;
    evOn { $_ = $s; 1; } $evMethods if accept($s, $_);
  };
}

1;
