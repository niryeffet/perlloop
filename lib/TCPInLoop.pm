use strict;
use warnings;

package TCPInLoop;
use Socket qw(:DEFAULT TCP_NODELAY SOMAXCONN SO_KEEPALIVE);
use File::Basename 'dirname';
use Cwd 'abs_path';
use lib dirname(abs_path(__FILE__));
use InLoop;

use Exporter 'import';
our @EXPORT = qw(tcpServer tcpClient evLine evHup evIn evOut);
use constant IPPROTO_TCP => (getprotobyname('tcp'))[2];

sub tcpClient {
  my $port = shift;
  my $address = shift;
  evOn {
    my $ip = inet_aton($address) or return 0;
    socket($_, PF_INET, SOCK_STREAM, IPPROTO_TCP) or return 0;
    setsockopt($_, IPPROTO_TCP, TCP_NODELAY, 1);
    setsockopt($_, SOL_SOCKET, SO_KEEPALIVE, 1);
    connect(nonblock($_), sockaddr_in($port, $ip));
  } @_;
}

sub tcpServer {
  my $port = shift() + 0;
  my $address = shift || '0.0.0.0';
  my $evMethods = evOnce ({}, @_);

  evOn {
    my $h = shift;
    socket($_, PF_INET, SOCK_STREAM, IPPROTO_TCP) or return 0;
    setsockopt($_, SOL_SOCKET, SO_REUSEADDR, 1) and
    bind($_, pack_sockaddr_in($port, inet_aton($address))) and
    ($h->{port} = $port || (sockaddr_in(getsockname($_)))[0]) and
    listen($_, SOMAXCONN) or (print(STDERR "can't bind or listen: $!\n"), close($_), return 0);
  } evIn {
    while (accept(my $s, $_)) {
      setsockopt($s, IPPROTO_TCP, TCP_NODELAY, 1);
      setsockopt($s, SOL_SOCKET, SO_KEEPALIVE, 1);
      evOn { $_ = $s; 1; } $evMethods;
    }
    1;
  };
}

1;
