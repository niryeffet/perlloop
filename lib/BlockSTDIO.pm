use strict;
use warnings;

package BlockSTDIO;

open STDIN, '<', '/dev/null';
open STDOUT, '>', '/dev/null';
open STDERR, '>&', 'STDOUT';

1;
