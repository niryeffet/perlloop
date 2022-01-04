use strict;

package HidUsbRelay;
use InLoop;

use constant UPDATE_AFTER => 60; # seconds

sub new {
  my ($package, $boardId, $sw) = @_;
  my $this = bless {
    boardId => $boardId,
    sw => $sw,
    state => {},
  };
  $this->_updateState();
  $this;
}

sub _updateState {
  my $this = shift;
  $this->{update} = time() + UPDATE_AFTER;
  my $b = $this->{boardId};
  evLine {
    $this->{state}->{$1} = $2 if /^$b\_(\d)\=([1|0])/;
  } __exec();
}

sub __exec { # don't use $this
  my $params = shift;
  evOn {
    open($_, "/usr/bin/usbrelay $params 2>/dev/null|");
  } evOnce;
}

sub _sw {
  my $this = shift;
  my $sw = shift;
  $sw = $this->{sw}->{$sw} || $sw;
  ($this, $sw, @_);
}

sub on {
  my ($this, $sw) = &_sw;
  __exec("$this->{boardId}_$sw=1");
  $this->{state}->{$sw} = 1;
}

sub off {
  my ($this, $sw) = &_sw;
  __exec("$this->{boardId}_$sw=0");
  $this->{state}->{$sw} = 0;
}

sub state {
  my ($this, $sw, $cb) = &_sw;
  my $ret = $this->{state}->{$sw};
  return &$cb($ret) if defined($ret) and time() < $this->{update};
  evHup {
    &$cb($this->{state}->{$sw});
  } $this->_updateState();
}

sub button {
  my ($this, $sw) = &_sw;
  evHup {
    setTimeout {
      __exec("$this->{boardId}_$sw=0");
    } 250;
  } __exec("$this->{boardId}_$sw=1");
}

1;
