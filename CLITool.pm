use strict;

package CLITool;
use lib '.';
use InLoop;
use TellAll;

use Exporter 'import';
our @EXPORT = qw(subCli);
use constant HELPKEY => '(help|\?)( |$)';
use constant PROMPT => '> ';

my $ignore = [sub { 1; }];

sub new {
  my $cli = addHelp({ # bless
    '(exit|quit)$' => [sub {
      my $h = shift;
      (fileno $h->{fh}) == 0 ? exitInLoop : $h->evOff;
      2; # don't show prompt
    }, 'exit/quit - leave the program (terminate on console)'],
    'restart$' => [sub {
      exitInLoop;
      exec($^X, $0, @ARGV);
    }, 'restart - re-exec self'],
    'echo( |$)' => [sub { CORE::say; }], # undocumented echo command, not sure what for
    '$' => $ignore,
    '\.\.$' => $ignore,
    '\.\.\.$' => $ignore,
  });
  $cli->add($_[1]);
}

sub processCli {
  my $cli = shift;
  my $cc = $_;
  my $success;
  foreach my $cmd (keys %$cli) {
    $_ = $cc;
    last if s/^$cmd// && ($success = $cli->{$cmd}->[0]->(@_));
  }
  $_ = $cc;
  $success;
}

sub addHelp {
  my $cli = bless shift;
  my $cmd = $_[0] ? "$_[0] " : '';
  $cli->{&HELPKEY} = [sub {
    my $h = $_[0];
    if (/^$/ or /^\?/ ) {
      $h->say($_[1]->{prompt}->()."usage:");
      $h->say($_->[1]) foreach sort { $a->[1] cmp $b->[1] } grep { $_->[1] ne '' } values %$cli;
      $h->say(".. - go back one level\n... - top level") if !$_[1]->{isAccum}->();
    } else {
      my $cmd = $_;
      $_ .= ' ?';
      $h->say("No help for '$cmd'") if !$cli->processCli(@_);
    }
    1;
  }, 'help, ? - show help'] if !$cli->{&HELPKEY};
  $cli->{'$'} = [sub { $_[1]->{set}->(); } ] if !$cli->{'$'};
  $cli->{'\.\.$'} = [sub { $_[1]->{leave}->(); }] if !$cli->{'\.\.$'};
  $cli->{'\.\.\.$'} = [sub { $_[1]->{top}->(); }] if !$cli->{'\.\.\.$'};
  $cli;
}

sub subCli { # Exported
  my ($cli, $cmd) = @_;
  addHelp($cli, $cmd); # bless
  return sub {
    $_[1]->{accumulate}->($cli, $cmd);
    $cli->processCli(@_);
  };
}

sub newProcessor {
  my @clis = ( shift );
  my @prompts = ( '' );
  my (@cliAccum, @promptAccum);
  my $methods;
  $methods = {
    'accumulate' => sub {
       unshift @cliAccum, $_[0];
       unshift @promptAccum, ($promptAccum[0] || $prompts[0]).$_[1].' ';
    }, 'set' => sub {
       unshift @clis, @cliAccum;
       unshift @prompts, @promptAccum;
       1;
    }, 'leave' => sub {
       return 0 if @promptAccum || @prompts == 1;
       shift @clis;
       shift @prompts;
       1;
    }, 'top' => sub {
       return 0 if @promptAccum || @prompts == 1;
       shift @clis while (@clis > 1);
       shift @prompts while (@prompts > 1);
       1;
    }, 'prompt' => sub {
       $promptAccum[0] || $prompts[0];
    }, 'isAccum' => sub {
       @promptAccum || @prompts == 1;
    }, 'process' => sub {
       my $h = shift;
       @cliAccum = ();
       @promptAccum = ();
       chomp; s/\s*$//; s/^\s*//; s/\s+/ /g;
       my $success = $clis[0]->processCli($h, $methods);
       $h->say("Unknow command '$_'.") if !$success;
       $h->write($prompts[0].PROMPT) if $success != 2;
    },
  };
}

sub processLine {
  my ($cli, $connected) = @_;
  return evLine {
    my $h = shift;
    $h->{CLIMethods}->{process}->($h);
  } evOut {
    my $h = shift;
    $h->{CLIMethods} = newProcessor($cli);
    $h->write(PROMPT);
    $connected->add($h) if $connected;
    1;
  } evHup {
    TellAll->removeAll(shift);
  };
}

sub del {
  my ($cli, $del) = @_;
  delete $cli->{$_} foreach keys %$del;
  $cli;
}

sub add {
  my ($cli, $new) = @_;
  @{$cli}{keys %$new} = values %$new if $new;
  $cli;
}

sub console {
  my ($cli, $connected) = @_;
  $| = 1;
  evOn {
    my $h = shift;
    $_ = *STDIN;
    $h->{out} = *STDOUT;
    1;
  } evHup { # Override evHup from processLine
    print "\n";
    exitInLoop();
    0;
  } $cli->processLine($connected);
}

1;
