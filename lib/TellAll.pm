use strict;
use warnings;

package TellAll;
our $VERSION = '0.02';
use Scalar::Util qw(refaddr weaken);

our @all;

sub new {
  my $self = bless {};
  push @all, $self;
  weaken($all[-1]);
  $self;
}

sub writeRef {
  my ($this, $msg, $ignore) = @_;
  if ($ignore) {
    my $ign_id = ref($ignore) ? refaddr($ignore) : $ignore;
    foreach my $id (keys %$this) {
      $this->{$id}->writeRef($msg) if $id ne $ign_id;
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

sub count {
  my $this = shift;
  return scalar keys %$this;
}

sub size {
  my $this = shift;
  return $this->count();
}

sub _key {
  my $h = shift;
  return unless defined $h;
  return refaddr($h) if ref $h;
  return $h;
}

sub add {
  my ($this, $h) = @_;
  my $k = _key($h);
  return unless defined $k;
  $this->{$k} = $h;
  1;
}

sub is {
  my ($this, $h) = @_;
  my $k = _key($h);
  return 0 unless defined $k;
  exists $this->{$k};
}

sub remove {
  my ($this, $h) = @_;
  my $k = _key($h);
  return unless defined $k;
  delete $this->{$k};
  1;
}

sub removeAll {
  my ($this, $h) = @_;
  return unless defined $h;
  @all = grep { defined } @all;
  $_->remove($h) foreach @all;
}

1;
