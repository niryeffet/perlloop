use strict;

package HidUsbRelay;
use lib '.';
use InLoop;

use constant UPDATE_AFTER => 60; # recache state after n seconds
use constant BUTTON_PRESS => 250; # milliseconds
use constant REPORT_ERRORS => 3; # report after 3 consecutive errors

sub new {
  my ($package, $boardId, $sw) = @_;
  my $this = bless {
    boardId => $boardId,
    sw => $sw,
    state => {},
    error => 0,
  };
  $this->_updateState();
  $this;
}

sub _updateState {
  my ($this, $cb) = @_;
  my $b = $this->{boardId};
  my $newState = {};
  evLine {
    $newState->{$1} = $2 if /^$b\_(\d)\=([1|0])/;
  } evHup {
    if (%$newState || $this->{error}++ == REPORT_ERRORS) {
      $this->{state} = $newState;
      $this->{update} = time() + UPDATE_AFTER;
      $this->{error} = 0;
    }
    &$cb if $cb;
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
  $this->_updateState(sub {
    &$cb($this->{state}->{$sw});
  });
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
