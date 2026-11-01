use strict;
use warnings;

package TCPInLoop;
our $VERSION = '0.02';
use Socket qw(:DEFAULT getaddrinfo getnameinfo AI_PASSIVE NI_NUMERICHOST NI_NUMERICSERV
              TCP_NODELAY SOMAXCONN SO_KEEPALIVE IPPROTO_IPV6 IPV6_V6ONLY);
use File::Basename 'dirname';
use Cwd 'abs_path';
use lib dirname(abs_path(__FILE__));
use InLoop;

use Exporter 'import';
our @EXPORT = qw(tcpServer tcpClient evLine evHup evIn evOut);
use constant IPPROTO_TCP => (getprotobyname('tcp'))[2];

sub _getPort {
  my $s = shift;
  my $name = getsockname($s) or return 0;
  my ($err, $host, $port) = getnameinfo($name, NI_NUMERICHOST | NI_NUMERICSERV);
  return int($port // 0);
}

sub tcpClient {
  my $port = shift;
  my $address = shift;
  evOn {
    my ($err, @res) = getaddrinfo($address, "$port", { socktype => SOCK_STREAM });
    return 0 if $err || !@res;
    my $ai = $res[0];
    socket($_, $ai->{family}, $ai->{socktype}, $ai->{protocol}) or return 0;
    setsockopt($_, IPPROTO_TCP, TCP_NODELAY, 1);
    setsockopt($_, SOL_SOCKET, SO_KEEPALIVE, 1);
    connect(nonblock($_), $ai->{addr});
  } @_;
}

sub tcpServer {
  my $port = shift() + 0;
  my $address = shift;
  my $evMethods = evOnce ({}, @_);

  my @bind_addrs;
  if (!defined($address) || $address eq '') {
    push @bind_addrs, undef;
  } elsif (lc($address) eq 'loopback') {
    push @bind_addrs, '::1', '127.0.0.1';
  } else {
    push @bind_addrs, $address;
  }

  my $first_port = $port;
  my $first_h;

  for my $bind_addr (@bind_addrs) {
    my $h = evOn {
      my $h = shift;
      my ($err, @res);
      if (!defined($bind_addr)) {
        # Try dual-stack IPv6 wildcard first (accepts both IPv6 :: and IPv4 0.0.0.0 on Linux)
        ($err, @res) = eval { getaddrinfo(undef, "$first_port", { socktype => SOCK_STREAM, flags => AI_PASSIVE, family => AF_INET6 }) };
      }
      if ($err || !@res) {
        my $addr = (defined($bind_addr) && length($bind_addr)) ? $bind_addr : '0.0.0.0';
        ($err, @res) = getaddrinfo($addr, "$first_port", { socktype => SOCK_STREAM, flags => AI_PASSIVE });
      }
      return 0 if $err || !@res;
      my $ai = $res[0];

      socket($_, $ai->{family}, $ai->{socktype}, $ai->{protocol}) or return 0;
      setsockopt($_, SOL_SOCKET, SO_REUSEADDR, 1);
      
      eval { setsockopt($_, IPPROTO_IPV6, IPV6_V6ONLY, 0); } if !defined($bind_addr) && $ai->{family} == AF_INET6;
      
      bind($_, $ai->{addr}) and
      ($h->{port} = $first_port || _getPort($_)) and
      listen($_, SOMAXCONN) or (print(STDERR "can't bind or listen: $!\n"), close($_), return 0);
      
      $first_port ||= $h->{port};
      1;
    } evIn {
      while (accept(my $s, $_)) {
        setsockopt($s, IPPROTO_TCP, TCP_NODELAY, 1);
        setsockopt($s, SOL_SOCKET, SO_KEEPALIVE, 1);
        evOn { $_ = $s; 1; } $evMethods;
      }
      1;
    };
    $first_h ||= $h;
  }

  return $first_h;
}

1;
