use strict;

package TellAll;

our @all;

sub new {
  $all[@all] = bless {};
}

sub writeRef {
  my ($this, $msg, $ignore) = @_;
  if ($ignore) {
    foreach (values %$this) {
      $_->writeRef($msg) if $_ != $ignore;
    }
  } else {
    $_->writeRef($msg) foreach values %$this;
  }
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

sub is {
  my ($this, $h) = @_;
  exists $this->{$h->{fh}};
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

1;
