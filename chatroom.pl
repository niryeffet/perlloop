#!/usr/bin/perl
use strict;
use lib '.';
use InLoop;
use TCPInLoop;

my $system = 'system';
my %connected;
my %byName;

sub output {
  my ($h, $msg) = @_;
  # writing to a socket may fail, ignore
  eval { print { $h->{out} || $h->{fh} } "$msg\n"; };
}

sub welcome {
  output(shift, "$system: please setup your name with /name command");
}

sub tellAll {
  my ($msg, $ignore) = @_;
  output($_, $msg) foreach grep { $_ != $ignore } values %connected;
}

my $evLine = evLine {
  my $h = shift;
  s/\r//; chomp;
  if (s/^\///) {
    if ($h->{name} eq $system) {
      if (/^ban +(.+)/) {
        if ($byName{$1} && $1 ne $system) {
          shutdown($byName{$1}->{fh}, 2);
          return;
        } else {
          output($h, "$system: can't ban $1");
          return;
        }
      } elsif (/^shutdown$/) {
        exitInLoop();
        return;
      }
    }
    if (/^msg +([^ ]*) +(.+)/ && $h->{name}) {
      if ($byName{$1}) {
        output($byName{$1}, "$h->{name}(privately): $2");
      } else {
        output($h, "$system: couldn't msg $1");
      }
    } elsif (/^who am i/i && $h->{name}) {
      output($h, "$h->{name}");
    } elsif (/^who$/i) {
      output($h, "$system: ".join(', ', keys %byName));
    } elsif (/^name (.*)$/i) {
      if ($1 eq '' or $byName{$1}) {
        output($h, "$system: unable to change name");
      } else {
        if ($h->{name}) {
          tellAll("$system: $h->{name} is now known as $1");
          $system = $1 if $h->{name} eq $system;
          delete $byName{$h->{name}};
        } else {
          $connected{$h->{fh}} = $h;
          tellAll("$system: $1 is now connected");
        }
        $byName{$h->{name} = $1} = $h;
      }
    } else {
      output($h, "$system: unknown command '$_'");
    }
  } elsif ($h->{name}) {
    tellAll("$h->{name}: $_", $h) if $_ ne '';
  } else {
    welcome($h);
  }
};

tcpServer(23456, undef, ($evLine, evOut {
  welcome(shift);
  1;
} evHup {
  my $h = shift;
  delete $connected{$h->{fh}};
  if ($h->{name}) {
    tellAll("$system: $h->{name} diconnected");
    delete $byName{$h->{name}};
  }
}));

evOn {
  my $h = shift;
  $h->{fh} = \*STDIN;
  $h->{out} = \*STDOUT;
  $byName{$h->{name} = $system} = $connected{$h->{fh}} = $h;
  1;
} $evLine;

1;
