#!/usr/bin/perl
use strict;
use warnings;
use File::Basename 'dirname';
use Cwd 'abs_path';
use lib dirname(dirname(abs_path(__FILE__))) . '/lib';

use InLoop;
use TCPInLoop;
use TellAll;

our $system = 'system';
our $connected = TellAll->new();
our %byName;

sub sysOut {
  my ($h, $msg) = @_;
  $h->say("$system: $msg");
}

sub welcome {
  my ($h) = @_;
  sysOut($h, 'please setup your name with /name command');
}

sub cmd_name {
  my ($h, $new_name) = @_;
  $new_name =~ s/^\s+|\s+$//g;
  if ($new_name eq '' || exists $byName{$new_name}) {
    sysOut($h, 'unable to change name');
    return;
  }
  if ($h->{name}) {
    $connected->say("$system: $h->{name} is now known as $new_name");
    $system = $new_name if $h->{name} eq $system;
    delete $byName{$h->{name}};
  } else {
    $connected->add($h);
    $connected->say("$system: $new_name is now connected");
  }
  $h->{name} = $new_name;
  $byName{$new_name} = $h;
}

sub cmd_msg {
  my ($h, $args) = @_;
  return welcome($h) unless $h->{name};
  my ($target, $text) = split(/\s+/, $args, 2);
  if (defined $target && defined $text && exists $byName{$target}) {
    $byName{$target}->say("$h->{name}(privately): $text");
  } else {
    sysOut($h, "couldn't msg " . ($target // ''));
  }
}

sub cmd_ban {
  my ($h, $target) = @_;
  $target =~ s/^\s+|\s+$//g;
  if ($target ne '' && exists $byName{$target} && $target ne $system) {
    my $target_h = delete $byName{$target};
    $connected->remove($target_h);
    $connected->say("$system: $target was banned by $h->{name}");
    $target_h->evOff;
  } else {
    sysOut($h, "can't ban $target");
  }
}

sub cmd_bye {
  my ($h) = @_;
  return if ($h->{name} // '') eq $system;
  if ($h->{name} && exists $byName{$h->{name}}) {
    my $name = $h->{name};
    delete $byName{$name};
    $connected->remove($h);
    $connected->say("$system: $name disconnected");
  }
  $h->evOff;
}

sub cmd_op {
  my ($h, $target, $val) = @_;
  $target =~ s/^\s+|\s+$//g;
  if ($target ne '' && exists $byName{$target} && ($val || $target ne $system)) {
    $byName{$target}->{op} = $val;
    my $action = $val ? "op'ed" : "deop'ed";
    sysOut($byName{$target}, "$h->{name} $action you");
  } else {
    my $action = $val ? 'op' : 'deop';
    sysOut($h, "can't $action $target");
  }
}

my %user_commands;
my %op_commands;

sub show_help {
  my ($h) = @_;
  my @help;
  for my $name (sort keys %user_commands) {
    next if $name eq 'bye' && ($h->{name} // '') eq $system;
    next if $name =~ /^(who am i|msg)$/ && !$h->{name};
    push @help, "  /$name - $user_commands{$name}->{desc}";
  }
  if ($h->{op}) {
    for my $name (sort keys %op_commands) {
      next if ($name eq 'shutdown' || $name eq 'quit') && ($h->{name} // '') ne $system;
      push @help, "  /$name - $op_commands{$name}->{desc}";
    }
  }
  $h->say('Available commands:');
  $h->say($_) for sort @help;
}

%user_commands = (
  'help' => {
    desc => 'show available commands',
    run  => sub { show_help($_[0]); },
  },
  'who' => {
    desc => 'show who is in the room',
    run  => sub { sysOut($_[0], join(', ', sort keys %byName)); },
  },
  'who am i' => {
    desc => 'show own name',
    run  => sub { $_[0]->say($_[0]->{name} || 'anonymous'); },
  },
  'name' => {
    desc => '<name> - set/change own name',
    run  => sub { cmd_name($_[0], $_[1]); },
  },
  'msg' => {
    desc => '<name> ... - send private message',
    run  => sub { cmd_msg($_[0], $_[1]); },
  },
  'bye' => {
    desc => 'leave chat',
    run  => sub { cmd_bye($_[0]); },
  },
);

%op_commands = (
  'nclients' => {
    desc => 'show connected client count',
    run  => sub { sysOut($_[0], $connected->count()); },
  },
  'ban' => {
    desc => '<name> - kick someone out',
    run  => sub { cmd_ban($_[0], $_[1]); },
  },
  'op' => {
    desc => '<name> - turn <name> into op',
    run  => sub { cmd_op($_[0], $_[1], 1); },
  },
  'deop' => {
    desc => '<name> - remove <name> op flag',
    run  => sub { cmd_op($_[0], $_[1], 0); },
  },
  'ops' => {
    desc => 'list ops',
    run  => sub { sysOut($_[0], join(', ', sort grep { $byName{$_}->{op} } keys %byName)); },
  },
  'shutdown' => {
    desc => 'turn off chat',
    run  => sub { exitInLoop() if ($_[0]->{name} // '') eq $system; },
  },
  'quit' => {
    desc => 'turn off chat',
    run  => sub { exitInLoop() if ($_[0]->{name} // '') eq $system; },
  },
);

sub dispatch_command {
  my ($h, $line) = @_;
  my ($cmd, $args);
  if ($line =~ /^who\s+am\s+i$/i) {
    $cmd = 'who am i';
    $args = '';
  } else {
    ($cmd, $args) = split(/\s+/, $line, 2);
    $cmd = lc($cmd // '');
    $args = '' unless defined $args;
  }

  if ($h->{op} && exists $op_commands{$cmd}) {
    return $op_commands{$cmd}->{run}->($h, $args);
  }
  if (exists $user_commands{$cmd}) {
    return $user_commands{$cmd}->{run}->($h, $args);
  }
  sysOut($h, "not sure what to do with '/$line'. try '/help'");
}

our $evLine = evLine {
  my $h = shift;
  s/\r//g;
  chomp;
  if (s/^\///) {
    s/\s+$//;
    dispatch_command($h, $_);
  } elsif ($h->{name}) {
    $connected->say("$h->{name}: $_", $h) if $_ ne '';
  } else {
    welcome($h);
  }
};

my $port = $ENV{CHATROOM_PORT} // 23456;
our $server;

if ($port >= 0) {
  $server = tcpServer($port, undef, (
    $evLine,
    evOut {
      welcome(shift);
      1;
    },
    evHup {
      my $h = shift;
      $connected->remove($h);
      if ($h->{name} && exists $byName{$h->{name}}) {
        $connected->say("$system: $h->{name} disconnected");
        delete $byName{$h->{name}};
      }
    }
  ));
}

if ($ENV{CHATROOM_CONSOLE} // 1) {
  evOn {
    my $h = shift;
    $h->{fh} = *STDIN;
    $h->{out} = *STDOUT;
    $h->{name} = $system;
    $connected->add($byName{$system} = $h);
    $h->{op} = 1;
    1;
  } evOut {
    my $actual_port = $server ? $server->{port} : $port;
    shift->say("chatroom console. try \"/help\". Others can join on port $actual_port.");
    1;
  } $evLine;
}

1;
