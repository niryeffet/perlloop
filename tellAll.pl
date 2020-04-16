#!/usr/bin/perl
use strict;
use lib '.';
use InLoop;
use TCPInLoop;
use TellAll;

my $connected = TellAll->new();

tcpServer(23456, '127.0.0.1', evLine {
  $connected->write($_, shift); # write to all except self;
} $connected->evMethods);

setInterval {
  $connected->say("Hello world");
} 1000;

tcpClient(23456, '127.0.0.1', evLine { print; });

1;
