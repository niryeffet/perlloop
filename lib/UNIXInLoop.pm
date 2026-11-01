use strict;
use warnings;

package UNIXInLoop;
our $VERSION = '0.02';
use Socket qw(AF_UNIX SOCK_STREAM sockaddr_un SOMAXCONN);
use File::Basename 'dirname';
use Cwd 'abs_path';
use lib dirname(abs_path(__FILE__));
use InLoop;

use Exporter 'import';
our @EXPORT = qw(unixServer unixClient evLine evHup evIn evOut);

our @created_sockets;

sub unixClient {
  my $path = shift;
  evOn {
    socket($_, AF_UNIX, SOCK_STREAM, 0) or return 0;
    connect(nonblock($_), sockaddr_un($path));
  } @_;
}

sub unixServer {
  my $path = shift;
  my $evMethods = evOnce ({}, @_);

  evOn {
    my $h = shift;
    unlink($path) if -e $path || -S $path; # Clear stale socket file
    push @created_sockets, $path;
    $h->{path} = $path;
    socket($_, AF_UNIX, SOCK_STREAM, 0) or return 0;
    bind($_, sockaddr_un($path)) and
    listen($_, SOMAXCONN) or (print(STDERR "can't bind or listen to $path: $!\n"), close($_), return 0);
  } evIn {
    while (accept(my $s, $_)) {
      evOn { $_ = $s; 1; } $evMethods;
    }
    1;
  } evHup {
    my $h = shift;
    unlink($h->{path}) if $h->{path} && (-e $h->{path} || -S $h->{path});
  };
}

END {
  unlink($_) foreach grep { -e $_ || -S $_ } @created_sockets;
}

1;
