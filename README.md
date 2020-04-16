# Event driven / asynchronous using Perl

Using these tools one can easily
* react to: IR, log lines (tail -f), external devices, ETC. events
* write CLI to control the program and devices
* write REST API
* route data to listeners and log files

### Requirements:
Linux. On Ubuntu, install liblinux-fd-perl:

`sudo apt-get install liblinux-fd-perl`

## Why Perl? The default variable.

Also, it was initially written long time ago (before epoll), when perl was still popular...

The default input and pattern-searching variable ($_) makes it super easy to write code and focus only on the application logic, with zero boiler-plate code. Example: easily mapping Panasonic TV remote to control audio even when the TV if off.

```
  if (/Panasonic_TC-21E1R/ && $tv eq 'off') {
    if (/ (..) \+ / && (hex($1) % 3 == 0)) {
      cecOut('tx '.$cecNum.'5:44:41');
    } elsif (/ (..) - / && (hex($1) % 3 == 0)) {
      cecOut('tx '.$cecNum.'5:44:42');
    } elsif (/ 00 pause /) {
      cecOut('tx '.$cecNum.$cecActive.':44:46');
    } elsif (/ 00 track_up /) {
      cecOut('tx '.$cecNum.$cecActive.':44:4b');
    } elsif (/ 00 track_down /) {
      cecOut('tx '.$cecNum.$cecActive.':44:4c');
    }
  }
```