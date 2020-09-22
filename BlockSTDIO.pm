use strict;

package BlockSTDIO;

open STDIN, '</dev/null';
open STDOUT, '>/dev/null';
open STDERR, '>&STDOUT';

1;
