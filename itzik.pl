#!/usr/bin/perl
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
  print "Received unexpected: $_";
});

sub tellAll {
  my $msg = shift;
  $_->say($msg) foreach values %connected;
}

# test
setInterval {
  tellAll("Hello world");
} 1000;

tcpClient(23456, '127.0.0.1', evLine { print; });

1;
