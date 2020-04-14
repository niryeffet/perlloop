use strict;

package TellAll;
use lib '.';
use InLoop;

sub new {
  bless {};
}

sub write {
  my ($this, $msg, $ignore) = @_;
  $_->write($msg) foreach $ignore ?
    grep { $_ != $ignore } values %$this : values %$this;
}

sub say {
  my ($this, $msg, $ignore) = @_;
  $_->say($msg) foreach $ignore ?
    grep { $_ != $ignore } values %$this : values %$this;
}

sub add {
  my ($this, $h) = @_;
  $this->{$h->{fh}} = $h;
  1;
}

sub remove {
  my ($this, $h) = @_;
  delete $this->{$h->{fh}};
  1;
}

sub evMethods {
  my $this = shift;
  return evOut {
    $this->add(shift);
  } evHup {
    $this->remove(shift);
  } @_;
}
 
1;
