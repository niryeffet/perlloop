use strict;

package HidUsbRelay;
use InLoop;

use constant UPDATE_AFTER => 60; # recache state after n seconds
use constant BUTTON_PRESS => 250; # milliseconds

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

sub _flip {
  my ($this, $sw, $state) = @_;
  $this->{state}->{$sw} = $state;
  __exec("$this->{boardId}_$sw=$state");
}

sub _sw {
  my $this = shift;
  my $sw = shift;
  $sw = $this->{sw}->{$sw} || $sw;
  ($this, $sw, @_);
}

sub on {
  my ($this, $sw) = &_sw;
  $this->_flip($sw, 1);
}

sub off {
  my ($this, $sw) = &_sw;
  $this->_flip($sw, 0);
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
      $this->_flip($sw, 0);
    } BUTTON_PRESS;
  } $this->_flip($sw, 1);
}

1;
