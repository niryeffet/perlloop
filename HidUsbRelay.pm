use strict;

package HidUsbRelay;
use InLoop;

sub new {
  my ($package, $boardId, $sw) = @_;
  my $this = bless {
    boardId => $boardId,
    sw => $sw,
    state => {}
  };
  evLine {
    $this->{state}->{$1} = $2 if /^$boardId\_(\d)\=([1|0])/;
  } $this->_exec();
  $this;
}

sub _exec {
  my ($this, $params) = @_;
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
  $this->_exec("$this->{boardId}_$sw=1");
  $this->{state}->{$sw} = 1;
}

sub off {
  my ($this, $sw) = &_sw;
  $this->_exec("$this->{boardId}_$sw=0");
  $this->{state}->{$sw} = 0;
}

sub state {
  my ($this, $sw, $cb) = &_sw;
  my $ret = $this->{state}->{$sw};
  return &$cb($ret) if defined($ret);
  my $b = $this->{boardId};
  evLine {
    $this->{state}->{$sw} = $ret = $1 if /^$b\_$sw=([1|0])/;
  } evHup {
    &$cb($ret);
  } $this->_exec();
}

sub button {
  my ($this, $sw) = &_sw;
  evHup {
    setTimeout {
      $this->_exec("$this->{boardId}_$sw=0");
    } 250;
  } $this->_exec("$this->{boardId}_$sw=1");
}

1;
