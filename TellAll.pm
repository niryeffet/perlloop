use strict;

package TellAll;
use lib '.';
use InLoop;

our @all;

sub new {
  $all[@all] = bless {};
}

sub writeRef {
  my ($this, $msg, $ignore) = @_;
  $_->writeRef($msg) foreach $ignore ?
    grep { $_ != $ignore } values %$this : values %$this;
}

sub write {
  my ($this, $msg, $ignore) = @_;
  $this->writeRef(\$msg, $ignore);
}

sub say {
  my ($this, $msg, $ignore) = @_;
  $this->writeRef(\"$msg\n", $ignore);
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

sub removeAll {
  my ($this, $h) = @_;
  $_->remove($h) foreach @all;
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
