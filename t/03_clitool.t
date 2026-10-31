use strict;
use warnings;
use Test::More tests => 7;

use CLITool;

package MockHandle {
  sub new {
    bless { buf => [] }, shift;
  }
  sub say {
    my ($self, $msg) = @_;
    push @{$self->{buf}}, $msg;
  }
  sub write {
    my ($self, $msg) = @_;
    push @{$self->{buf}}, $msg;
  }
}

my $cli = CLITool->new();
isa_ok($cli, 'CLITool');

my $h = MockHandle->new();

# Add commands
$cli->add({
  'test$' => [sub { my $h = shift; $h->say("test_ok"); 1; }, 'test - test command'],
});

# Test command processing
$_ = "test";
my $proc = CLITool::newProcessor($cli);
$proc->{process}->($h);

# Check output
is($h->{buf}->[0], 'test_ok', 'command executed successfully');
is($h->{buf}->[1], '> ', 'prompt shown after command');

# Test help command
$h->{buf} = [];
$_ = "help";
$proc->{process}->($h);
ok(grep(/usage:/, @{$h->{buf}}), 'help shows usage');
ok(grep(/test - test command/, @{$h->{buf}}), 'help lists test command');

# Test unknown command
$h->{buf} = [];
$_ = "nonexistent_cmd";
$proc->{process}->($h);
is($h->{buf}->[0], "Unknown command 'nonexistent_cmd'.", 'unknown command handled');
is($h->{buf}->[1], '> ', 'prompt shown after unknown command');
