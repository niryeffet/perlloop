# Event driven / asynchronous I/O using Perl

Using these tools one can easily:
* react to: IR, log lines (tail -F), external devices, ETC. events
* write CLI to control the program and devices
* write simple RESTful API
* route data to listeners and log files
* not worry about disconnects (it will auto-reconnect)

Also benefits from:
* asynchronous writes (auto-buffering and event based writing)
* setTimeout and setInterval (javascript style)

### Requirements:
Linux. On Ubuntu, install liblinux-fd-perl:

`sudo apt-get install liblinux-fd-perl`

## Why Perl? The default variable.

Also, it was initially written long time ago, when perl was still popular.

The default input and pattern-searching variable ($\_) makes it super easy to write code and focus only on the application logic, with zero boiler-plate code. See example below.

# use Inloop;
## An easy to use event loop for perl

The event loop will start working when the program reaches perl's END block.

Most ev\* methods can be chained to form non blocking callback by events. The only exception is evEmpty. Example:

evOnce evOn { '/bin/ls -l|' } evLine { print };

Many ev\* methods' first argument is a code block. Code blocks first parameter is the ev handle, blessed by InLoop::methods. Always $h in this doc. There could be only one code block for each ev\* type. Calling a specific ev\* method again will override the previos code.

evOn { } ... - required. The code block should open() the communication and return the open() return data and $! should be set to the error from open(). The FILEHANDLE part of open MUST be either $\_ or $h->{fh}. If input and output has seperate fileno, like in open2(), $h->{fh} should be used for the input, and $h->{out} for the output. The open() above can ve also connect(), accept() and listen().
By default, evOn block will be called immediate again after the filehandle was closed. There is one second delay between recurring attemts. evOn returns a handle ($h) that is blessed by InLoop::methods.
If evOn code block returns a string that does not looks\_line\_number() it will be open()ed for input. See example above.

evOnce ... - optional. The evOn code block will not be executed again after it closed and the ev handle will not be useful anymore.

evLine { } ... - optional. The code block will be executed for each line received from the the filehandle that was opened in evOn code block. The data will be placed in $\_.

evIn { } ... - optional. This code block will be executed every time there is data to consume. $\_ will be the filehandle to read from. The return value from the code block should be non zero on success, zero on error and $! should indicate EAGAIN to continue reading data. Other error codes will cause the file handle to be closed.

There could be either evLine or evIn. If both are declared, evLine is ignored. 

evLineOnly ... - optional. In evLine mode only, do not call evLine code block if the data is not a complete line with \n at the end.

evOut { } ... - optional. This code block will be executed only once when epoll\_wait wakes up with EPOLLOUT. It is recommended to use $h-\>write(), $h-\>say() or $h-\>writeRef() instead of evOut directly as it will handle EAGAIN with addtional evOut automatically. Using evOut directly and $h-\>write() (or say() or writeRef()) simultanously will yield undesired results as there could be only one evOut.

evHup { } ... - optional. The code block will be called after the filehandle was closed. Usually used in combination with evOnce. Without evOnce, the return value from evHup code block will be considered - zero means do not call evOn code block again, similar to evOnce. A positive value is required to call evOn code block again.

The below methods are not to be chained with any of the above methods.

evEmpty - creats a pseudo handle that can sink $h-\>write(), $h-\>say() and $h-\>writeRef() calls. Not to use with combinations with any of the above.

exitInLoop - will close all filehandles and will exit the program.

nonblock filehandle - set filehandle nonblocking opration. This will be done automatically for evOn for $\_ or $h->{fh} and $h->{out}, however, in cases of connect(), in orde to prevent blocking the event loop, evOn code block should set the socket filehandle in nonblocking mode before calling connect() and EINPROGRESS will be handled by the event loop.

SetTimeout { } milliseconds - the code block will be executed once after milliseconds wait period. The return value is a handler blessed by InLoop::methods, normally to be able to cancel operation with $h-\>evOff.

SetInterval { } milliseconds - the code block will be executed after every milliseconds. The return value is a handler blessed by InLoop::methods, normally to be able to cancel operation with $h-\>evOff.

Examples:

evOnce evOn { open $\_, "/bin/ls |"; } evLine { ... }; # do this once.

evOn { open $\_, "tail -F /var/log/syslog |"; } evLine { ... }; # even if tail dies, it will be respwaned.

evOnce evOn { someIO } evHup { setTimeout { something; } 1000; }; # do something one second after someIO is done.

```
# Easily mapping Panasonic TV remote to control audio even when the TV if off.
use strict;
use Socket;
use IPC::Open2;
use lib '.';
use InLoop;

my $lircd = '/var/run/lirc/lircd';
my ($cecNum, $cecActive, $tv);

my $cec = evOn {
  my $h = shift;
  open2($h->{fh}, $h->{out}, 'cec-client -r -t p');
} evLine {
  if (/TV/ && /power status changed/) {
    if (/to 'standby'/) {
      $tv = 'off';
    } elsif (/to 'on'/) {
      $tv = 'on';
    }
  } elsif (/\((.)\): vendor = Pulse Eight/) {
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

# use TellAll;
TellAll is a simple broadcast mechanism. It allows output destinations to "register" (using the add() method) to receive communication. A newly created TellAll object, without add()ing destinations will ingore requests to write() or say(). Each destination added MUST be an object with writeRef() method implemented, normally an InLoop object, created by evOn method. A destination can be remove()ed or checked if existed using is().

TellAll keeps track of all TellAlls so a removeAll() call can make sure a destination was removed from all TellAlls.

BUGS:
TellAll can be chained, however, that is discouraged as it can also be looped which will result in memory overflow.

See chatroom.pl for example.
