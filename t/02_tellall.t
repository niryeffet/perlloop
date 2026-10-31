use strict;
use warnings;
use Test::More tests => 22;

use TellAll;

my $ta = TellAll->new();
isa_ok($ta, 'TellAll');

# Mock handle with writeRef
package MockHandle {
  sub new {
    my ($class, $id, $fh) = @_;
    bless { fh => $fh, buf => '' }, $class;
  }
  sub writeRef {
    my ($self, $ref) = @_;
    $self->{buf} .= $$ref;
  }
}

my $h1 = MockHandle->new(1, "FH_1");
my $h2 = MockHandle->new(2, "FH_2");

# Test count on empty instance
is($ta->count(), 0, 'empty TellAll count is 0');
is($ta->size(), 0, 'empty TellAll size is 0');

# Test add and is
$ta->add($h1);
ok($ta->is($h1), 'h1 is in TellAll');
ok(!$ta->is($h2), 'h2 is not in TellAll');
is($ta->count(), 1, 'count is 1 after adding h1');

$ta->add($h2);
ok($ta->is($h2), 'h2 is in TellAll');
is($ta->count(), 2, 'count is 2 after adding h2');

# Test say
$ta->say('hello');
is($h1->{buf}, "hello\n", 'h1 received say message');
is($h2->{buf}, "hello\n", 'h2 received say message');

# Test ignore in say
$ta->say('world', $h1);
is($h1->{buf}, "hello\n", 'h1 ignored second message');
is($h2->{buf}, "hello\nworld\n", 'h2 received second message');

# Test remove
$ta->remove($h1);
ok(!$ta->is($h1), 'h1 removed from TellAll');
is($ta->count(), 1, 'count is 1 after removing h1');

# Test removeAll across multiple instances
my $ta2 = TellAll->new();
$ta2->add($h2);
ok($ta2->is($h2), 'h2 is in ta2');
TellAll->removeAll($h2);
ok(!$ta2->is($h2), 'h2 removed from ta2 via removeAll');

# Test handles where fh is undef (e.g. before open or after _del)
my $warn_msg = '';
local $SIG{__WARN__} = sub { $warn_msg .= $_[0]; };

my $h_nofh = MockHandle->new(3, undef);
$ta->add($h_nofh);
ok($ta->is($h_nofh), 'handle with undef fh added without warning');
is($warn_msg, '', 'no warning on adding handle with undef fh');

# Test deleting fh then removing
delete $h_nofh->{fh};
$ta->remove($h_nofh);
ok(!$ta->is($h_nofh), 'handle removed cleanly after fh deleted');
is($warn_msg, '', 'no warning on removing handle after fh deleted');

# Test garbage collection of scoped TellAll instance
my $before_count = scalar(grep { defined } @TellAll::all);
{
  my $scoped = TellAll->new();
  is(scalar(grep { defined } @TellAll::all), $before_count + 1, 'scoped instance tracked while alive');
}
# Outside scope, the weak reference in @all should now be undef
is(scalar(grep { defined } @TellAll::all), $before_count, 'scoped instance garbage-collected cleanly');
