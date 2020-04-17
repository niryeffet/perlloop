# Event driven / asynchronous using Perl

Using these tools one can easily
* react to: IR, log lines (tail -F), external devices, ETC. events
* write CLI to control the program and devices
* write simple RESTful API
* route data to listeners and log files
* not worry about disconnects (it will auto-reconnect)

### Requirements:
Linux. On Ubuntu, install liblinux-fd-perl:

`sudo apt-get install liblinux-fd-perl`

## Why Perl? The default variable.

Also, it was initially written long time ago (before epoll), when perl was still popular...

The default input and pattern-searching variable ($_) makes it super easy to write code and focus only on the application logic, with zero boiler-plate code. Example: easily mapping Panasonic TV remote to control audio even when the TV if off.

```
use strict;
use Socket;
use IPC::Open2;
use lib '.';
use InLoop;

my $lircd = '/var/run/lirc/lircd';
my ($cecNum, $cecActive, $tv);

my $cec = evOn {
  my $h = shift;
  open2($h->{fh}, $h->{'out'}, 'cec-client -r -t p');
} evLine {
  if (/TV/ && /power status changed/) {
    if (/to 'standby'/) {
      $tv = 'off';
    } elsif (/to 'on'/) {
      $tv = 'on';
    }
  } elsif (/\((.*?)\): vendor = Pulse Eight/) {
    $cecNum = $1;
  } elsif (/>> (.)f:82:/) {
    $cecActive = $1;
  }
};

evOn {                                        # $_ is the filehandler
  socket($_, PF_UNIX, SOCK_STREAM, 0);
  connect(nonblock($_), sockaddr_un($lircd));
} evLine {                                    # $_ is the line input
  if (/Panasonic_TC-21E1R/ && $tv eq 'off') {
    if (/ (..) \+ / && (hex($1) % 3 == 0)) {
      $cec->say('tx '.$cecNum.'5:44:41');
    } elsif (/ (..) - / && (hex($1) % 3 == 0)) {
      $cec->say('tx '.$cecNum.'5:44:42');
    } elsif (/ 00 pause /) {
      $cec->say('tx '.$cecNum.$cecActive.':44:46');
    } elsif (/ 00 track_up /) {
      $cec->say('tx '.$cecNum.$cecActive.':44:4b');
    } elsif (/ 00 track_down /) {
      $cec->say('tx '.$cecNum.$cecActive.':44:4c');
    }
  }
};

1;
```
