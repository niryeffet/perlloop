use strict;
use warnings;

package BlockSTDIO;
our $VERSION = '0.02';

open STDIN, '<', '/dev/null';
open STDOUT, '>', '/dev/null';
open STDERR, '>&', 'STDOUT';

1;
