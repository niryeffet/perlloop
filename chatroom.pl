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

sub sysOut {
  my ($h, $msg) = @_;
  output($h, "$system: $msg");
}

sub welcome {
  sysOut(shift, "please setup your name with /name command");
}

sub tellAll {
  my ($msg, $ignore) = @_;
  output($_, $msg) foreach grep { $_ != $ignore } values %connected;
}

my $evLine = evLine {
  my $h = shift;
  s/\r//; chomp;
  if (s/^\///) {
    my @help;
    s/ *$//;
    if ($h->{op}) {
      if (/^nclients$/) {
        my $size = keys %connected;
        sysOut($h, $size);
        return;
      } elsif (/^ban +(.+)/) {
        if ($byName{$1} && $1 ne $system) {
          shutdown($byName{$1}->{fh}, 2);
        } else {
          sysOut($h, "can't ban $1");
        }
        return;
      } elsif (/^shutdown$/ or /^quit$/ && $h->{name} eq $system) {
        exitInLoop();
        return;
      } elsif (/^op +(.+)/) {
        if ($byName{$1}) {
          $byName{$1}->{op} = 1;
          sysOut($byName{$1}, "$h->{name} op'ed you");
        } else {
          sysOut($h, "can't op $1");
        }
        return;
      } elsif (/^deop +(.+)/) {
        if ($byName{$1} && $1 ne $system) {
          $byName{$1}->{op} = 0;
          sysOut($byName{$1}, "$h->{name} deop'ed you");
        } else {
          sysOut($h, "can't deop $1");
        }
        return;
      } elsif (/^ops$/) {
        sysOut($h, join(', ', grep { $byName{$_}->{op} } keys %byName));
        return;
      } elsif (/^help$/) {
        push @help, "  /shutdown, /quit - turn off chat"
          if $h->{name} eq $system;
        push @help, ("  /ban <name> - kick someone out",
                     "  /op <name> - turn <name> into op",
                     "  /ops - list ops",
                     "  /deop <name> - remove <name> op flag");
      }
    }
    if (/^help$/) {
      push @help, ("  /bye - leave chat") if $h->{name} ne $system;
      push @help, ("  /who - show who is in the room",
                   "  /name <name> - set/change own name");
      push @help, ("  /msg <name> ... - send private message",
                   "  /who am i - show own name") if $h->{name};
      output($h, "Available commands:");
      output($h, $_) foreach sort @help;
    } elsif (/^msg +([^ ]*) +(.+)/ && $h->{name}) {
      if ($byName{$1}) {
        output($byName{$1}, "$h->{name}(privately): $2");
      } else {
        sysOut($h, "couldn't msg $1");
      }
    } elsif (/^who +am +i/i && $h->{name}) {
      output($h, "$h->{name}");
    } elsif (/^who$/i) {
      sysOut($h, join(', ', keys %byName));
    } elsif (/^name +(.*)$/i) {
      if ($1 eq '' or $byName{$1}) {
        sysOut($h, "unable to change name");
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
    } elsif (/^bye$/ && $h->{name} ne $system) {
      shutdown($h->{fh}, 2);
    } else {
      sysOut($h, "not sure what to do with '/$_'. try '/help'");
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
  $h->{fh} = *STDIN;
  $h->{out} = *STDOUT;
  $h->{name} = $system;
  $byName{$system} = $connected{$h->{fh}} = $h;
  $h->{op} = 1;
  1;
} $evLine;

1;
