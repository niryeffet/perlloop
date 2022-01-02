use strict;

package HidUsbRelay;
use InLoop;

sub new {
  my ($package, $boardId, $sw, $cb) = @_;
  bless {
    boardId => $boardId ne '' ? " ID=$boardId" : '',
    sw => $sw,
    cb => $cb || sub { }
  };
}

sub _exec {
  my ($this, $params) = @_;
  evOn {
    open($_, "hidusb-relay-cmd$this->{boardId} $params|");
  };
}

sub _sw {
  my $this = shift;
  my $sw = shift;
  $sw = $this->{sw}->{$sw} || $sw;
  ($this, $sw, @_);
}

sub _cmd {
  my $this = shift;
  my $params = "@_";
  evOnce evLine {
    $this->{cb}->($_);
  } $this->_exec($params);
}

sub on {
  my ($this, $sw) = &_sw;
  $this->_cmd('on', $sw);
}

sub off {
  my ($this, $sw) = &_sw;
  $this->_cmd('off', $sw);
}

sub state {
  my ($this, $sw, $cb) = &_sw;
  my $bit = 1 << $sw - 1;
  evOnce evLine {
    # Board ID=[T39NB] State: 02 (hex)
    s/.*?State: (..).*/$1/;
    $_ = hex($_);
    &$cb($bit ? $_ & $bit : $_);
  } $this->_exec("state");
}

sub button {
  my ($this, $sw) = &_sw;
  evHup {
    setTimeout {
      $this->_cmd('off', $sw);
    } 250;
  } $this->_cmd('on', $sw);
}

1;
