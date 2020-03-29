use strict;

package InLoop::methods;
sub evOff { InLoop::evOff(shift); }
sub getOpenTime { $_[0]->{openTime}; }

1;
