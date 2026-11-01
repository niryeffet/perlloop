use strict;
use warnings;
use Test::More tests => 18;

my @modules = qw(InLoop Epoll TCPInLoop UNIXInLoop TellAll CLITool HTTPServer HidUsbRelay BlockSTDIO);

for my $mod (@modules) {
  use_ok($mod);
  no strict 'refs';
  is(${"${mod}::VERSION"}, '0.02', "$mod VERSION is 0.02");
}
