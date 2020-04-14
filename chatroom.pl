#!/usr/bin/perl
use strict;
use lib '.';
use InLoop;
use TCPInLoop;
use TellAll;

my $system = 'system';
my $connected = TellAll->new();
my %byName;

sub sysOut {
  my ($h, $msg) = @_;
  $h->say("$system: $msg");
}

sub welcome {
  sysOut(shift, 'please setup your name with /name command');
}

my $evLine = evLine {
  my $h = shift;
  s/\r//; chomp;
  if (s/^\///) {
    my @help;
    s/ *$//;
    if ($h->{op}) {
      if (/^nclients$/) {
        my $size = keys %$connected;
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
        push @help, '  /shutdown, /quit - turn off chat'
          if $h->{name} eq $system;
        push @help, ('  /ban <name> - kick someone out',
                     '  /op <name> - turn <name> into op',
                     '  /ops - list ops',
                     '  /deop <name> - remove <name> op flag');
      }
    }
    if (/^help$/) {
      push @help, ('  /bye - leave chat') if $h->{name} ne $system;
      push @help, ('  /who - show who is in the room',
                   '  /name <name> - set/change own name');
      push @help, ('  /msg <name> ... - send private message',
                   '  /who am i - show own name') if $h->{name};
      $h->say('Available commands:');
      $h->say($_) foreach sort @help;
    } elsif (/^msg +([^ ]*) +(.+)/ && $h->{name}) {
      if ($byName{$1}) {
        $byName{$1}->say("$h->{name}(privately): $2");
      } else {
        sysOut($h, "couldn't msg $1");
      }
    } elsif (/^who +am +i/i && $h->{name}) {
      $h->say("$h->{name}");
    } elsif (/^who$/i) {
      sysOut($h, join(', ', keys %byName));
    } elsif (/^name +(.*)$/i) {
      if ($1 eq '' or $byName{$1}) {
        sysOut($h, 'unable to change name');
      } else {
        if ($h->{name}) {
          $connected->say("$system: $h->{name} is now known as $1");
          $system = $1 if $h->{name} eq $system;
          delete $byName{$h->{name}};
        } else {
          $connected->add($h);
          $connected->say("$system: $1 is now connected");
        }
        $byName{$h->{name} = $1} = $h;
      }
    } elsif (/^bye$/ && $h->{name} ne $system) {
      shutdown($h->{fh}, 2);
    } else {
      sysOut($h, "not sure what to do with '/$_'. try '/help'");
    }
  } elsif ($h->{name}) {
    $connected->say("$h->{name}: $_", $h) if $_ ne '';
  } else {
    welcome($h);
  }
};

tcpServer(23456, undef, ($evLine, evOut {
  welcome(shift);
  1;
} evHup {
  my $h = shift;
  $connected->remove($h);
  if ($h->{name}) {
    $connected->say("$system: $h->{name} diconnected");
    delete $byName{$h->{name}};
  }
}));

evOn {
  my $h = shift;
  $h->{fh} = *STDIN;
  $h->{out} = *STDOUT;
  $h->{name} = $system;
  $connected->add($byName{$system} = $h);
  $h->{op} = 1;
  1;
} $evLine;

1;
