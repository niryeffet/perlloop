use strict;
use warnings;

package HTTPResponse;
use File::Basename 'dirname';
use Cwd 'abs_path';
use lib dirname(abs_path(__FILE__));
use parent 'InLoop::methods';
use POSIX qw(strftime);
use JSON::PP;

our %status = (
  200 => '200 Ok',
  204 => '204 No Content',
  400 => '400 Bad Request',
  404 => '404 Not Found',
  408 => '408 Request Timeout',
  413 => '413 Payload Too Large',
  431 => '431 Request Header Fields Too Large',
  501 => '501 Not Implemented',
);

sub httpResponse {
  my ($h, $status, $data, $ctype, $header) = @_;
  my $status_code = $status;
  $status = $status{$status} || $status;
  $data = $status."\n" if !defined($data) && ($status_code !~ /^204\b/);
  if (!defined($ctype)) {
    if ((ref $data) =~ /^(HASH|ARRAY)$/) {
      $ctype = 'application/json';
      $data = eval { encode_json($data) } || $data;
    } else {
      $ctype = 'text/plain';
    }
  }
  my $close = $h->{close};
  my $conn_hdr = $close ? 'close' : 'keep-alive';
  $header = defined($header) ? $header : '';
  $header .= "\r\n" if $header ne '' and $header !~ /\r\n$/;
  $h->write(
    "HTTP/1.1 $status\r\n".
    "Server: HTTPInLoop\r\n".
    "Date: ${\strftime('%a, %d %b %Y %T GMT', gmtime())}\r\n".
    "Content-Type: $ctype\r\n".
    "Content-Length: ${\(length($data) + 0)}\r\n".
    "Connection: $conn_hdr\r\n$header\r\n");
  $h->writeRef(\$data) unless ($h->{method} // '') eq 'HEAD';
  $h->evOff if $close;
}

sub say {
  my ($h, $text) = @_;
  $h->httpResponse(200, $text);
}

sub redirect {
  my ($h, $l) = @_;
  $h->httpResponse(301, '', undef, "Location: $l");
}

package HTTPServer;
use File::Basename 'dirname';
use Cwd 'abs_path';
use lib dirname(abs_path(__FILE__));
use InLoop;
use TCPInLoop;
use JSON::PP;

use Exporter 'import';
our @EXPORT = qw(httpServer);

use constant MAX_HEADER_SIZE => 128 * 1024; # 128KB max header

sub _parseCookie {
  my $cookie = {};
  foreach (split('; ', shift)) {
    my ($name, $value) = split /=/;
    $cookie->{$name} = $value;
  }
  return $cookie;
}

sub _parseQuerystring {
  my $qs = {};
  my $raw = shift;
  return $qs unless defined $raw && length($raw);
  for (split('&', $raw)) {
    my ($name, $value) = split(/=/, $_, 2);
    $value = '' unless defined $value;
    for ($name, $value) {
      s/\+/ /g;
      s/%([a-fA-F0-9]{2})/pack("C", hex($1))/eg;
    }
    if ($name =~ s/\[\]$// || defined($qs->{$name})) {
      if (ref $qs->{$name} eq 'ARRAY') {
        push @{$qs->{$name}}, $value;
      } elsif (defined($qs->{$name})) {
        $qs->{$name} = [$qs->{$name}, $value];
      } else {
        $qs->{$name} = [$value];
      }
    } else {
      $qs->{$name} = $value;
    }
  }
  return $qs;
}

sub _resetIdleTimer {
  my ($h, $timeout_ms) = @_;
  $h->{_idleTimer}->evOff if $h->{_idleTimer};
  $h->{_idleTimer} = setTimeout {
    $h->httpResponse(408) if $h->{fh};
    $h->evOff;
  } $timeout_ms;
}

sub httpServer {
  my ($port, $address, $router, $options) = @_;
  $options ||= {};
  my $maxHeader   = $options->{maxHeader} || MAX_HEADER_SIZE;
  my $idleTimeout = $options->{idleTimeout};

  return tcpServer($port, $address, evOut {
    my $h = shift;
    bless $h, 'HTTPResponse';
    _resetIdleTimer($h, $idleTimeout) if $idleTimeout;
    1;
  } evLine {
    my $h = $_[0];
    _resetIdleTimer($h, $idleTimeout) if $idleTimeout;
    $h->{data} = '' unless defined $h->{data};
    $h->{data} .= $_;
    my $rest;
    do {
      $h->{data} =~ s/^(?:\r?\n)+//;
      ($_, $rest) = split("\r\n\r\n", $h->{data}, 2);
      if (!defined($rest)) { # EOH not found yet
        if (length($h->{data}) > $maxHeader) {
          $h->httpResponse(431);
          $h->evOff;
        }
        return;
      }
      if ($_ eq '') {
        $h->{data} = $rest;
        next;
      }
      my $cl_match = (split(/^content-length:\s*/mi, $_, 2))[1];
      my $cl = defined($cl_match) ? int($cl_match) : 0;
      my $body = substr($rest, 0, $cl, '');
      return if length($body) < $cl; # waiting for body
      $h->{data} = $rest;
      $h->{body} = /^content-type:\s*application\/json\b/mi ? eval { decode_json($body); } || $body : $body;

      my $ref = ref $router;
      my $status = 501;
      my $r = $router;
      my $header = $_;
      $h->{close} = (/^connection:\s*close/mi || (/^[A-Z]+ \S+ HTTP\/1\.0/mi && !/^connection:\s*keep-alive/mi)) ? 1 : 0;
      my ($next, $qs);
      ($next, $_) = split /[ \r]/, $header, 3;
      if (!defined($next) || $next eq '') {
        $h->httpResponse(400);
        last;
      }
      $h->{method} = $next;
      $_ = '' unless defined $_;
      ($_, $qs) = split /\?/, $_, 2;
      while (1) {
        $ref = ref $r;
        if ($ref eq 'HASH') {
          my $target = $r->{$next};
          if (!defined($target) && $next eq 'HEAD' && defined($r->{GET})) {
            $target = $r->{GET};
          }
          defined($r = $target) or last;
          $status = 404;
          s/^\/([^\/]*)//;
          $next = $1;
          if (defined $next) {
            $next =~ s/\+/ /g;
            $next =~ s/%([a-fA-F0-9]{2})/pack("C", hex($1))/eg;
          }
        } elsif ($ref eq 'CODE' && /^\/?$/) {
          $h->{query} = _parseQuerystring($qs) if defined($qs);
          $_ = $header;
          $h->{cookie} = _parseCookie($1) if /^Cookie: ([^\r]*)/mi;
          $status = 0;
          $r->($h);
          delete $h->{query};
          delete $h->{cookie};
          last;
        } else { last; }
      }
      $h->httpResponse($status) if $status;
      delete $h->{body};
    } while ($h->{data} ne '');
  } evHup {
    my $h = shift;
    $h->{_idleTimer}->evOff if $h->{_idleTimer};
  });
}

1;
