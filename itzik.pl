#!/usr/bin/perl
use strict;
use lib '.';
use InLoop;
use TCPInLoop;
use TellAll;

my $connected = TellAll->new();

tcpServer(23456, '127.0.0.1', evLine {
  print "Received unexpected: $_";
} $connected->evMethods);

setInterval {
  $connected->say("Hello world");
} 1000;

tcpClient(23456, '127.0.0.1', evLine { print; });

1;
