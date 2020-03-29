use strict;

package CLITool;
use lib '.';
use InLoop;

use Exporter 'import';
our @EXPORT = qw(subCli);

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
  my %cli = %{$cli};
  my $cc = $_;
  my $success;
  foreach my $cmd (keys %cli) {
    $_ = $cc;
    last if s/^$cmd// && ($success = $cli{$cmd}->[0]->(@_));
  }
  $_ = $cc;
  $success;
}

sub addHelp {
  my $cli = bless shift;
  my $cmd = $_[0] ? "$_[0] " : '';
  my $helpKey = '(help|\?)( |$)';
  $cli->{$helpKey} = [sub {
    if (/^$/ or /^\?/ ) {
      print $_[1]->{prompt}->()."usage:\n";
      print "$_->[1]\n" foreach sort { $a->[1] cmp $b->[1] } grep { $_->[1] ne '' } values %$cli;
      print ".. - go back one level\n... - top level\n" if !$_[1]->{isAccum}->();
    } else {
      my $cmd = $_;
      $_ .= ' ?';
      print "No help for '$cmd'\n" if !$cli->processCli(@_);
    }
    1;
  }, 'help, ? - show help'] if !$cli->{$helpKey};
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

sub processLine {
  my @clis = ( shift );
  my @prompts = ( '' );
  my (@cliAccum, @promptAccum);
  my $methods = {
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
    },
  };
  return evLine {
    @cliAccum = ();
    @promptAccum = ();
    my $h = shift;
    my $fd = select($h->{out} || $h->{fh});
    chomp; s/\s*$//; s/^\s*//; s/\s+/ /g;
    my $success = $clis[0]->processCli($h, $methods);
    print "Unknow command '$_'.\n" if !$success;
    print $prompts[0].'> ' if $success != 2;
    select($fd);
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
  my $cli = shift;
  $| = 1;
  evOn {
    my $h = shift;
    $_ = *STDIN;
    $h->{out} = *STDOUT;
    print '> ';
    1;
  } evHup { # hup (ctrl-d)
    print "\n";
    exitInLoop();
    0;
  } $cli->processLine;
}

1;
