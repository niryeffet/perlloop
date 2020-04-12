use strict;

package HTTPResponse;
use lib '.';
use parent 'InLoop::methods';
use POSIX qw(strftime);
use JSON::PP;

our %status = (
  200 => '200 Ok',
  204 => '204 No Content',
  404 => '404 Not Found',
  501 => '501 Not Implemented',
);

sub httpResponse {
  my ($h, $status, $data, $ctype, $header) = @_;
  $status = $status{$status} || $status;
  $data = $status."\n" if !defined($data) && $status != 204;
  if (!defined($ctype)) {
    if ((ref $data) =~ /^(HASH|ARRAY)$/) {
      $ctype = 'application/json';
      $data = eval { encode_json($data) } || $data;
    } else {
      $ctype = 'text/plain';
    }
  }
  $header .= "\r\n" if $header ne '' and !$header =~ /\r\n$/s;
  $h->write(
    "HTTP/1.1 $status\r\n".
    "Server: HTTPInLoop\r\n".
    "Date: ${\strftime('%a, %d %b %Y %T GMT', gmtime())}\r\n".
    "Content-Type: $ctype\r\n".
    "Content-Length: ${\(length($data) * 1)}\r\n".
    "Connection: keep-alive\r\n$header\r\n");
  $h->write($data);
}

package HTTPServer;
use lib '.';
use TCPInLoop;
use InLoop;
use JSON::PP;

use Exporter 'import';
our @EXPORT = qw(httpServer);

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
  foreach (split('&', shift)) {
    my ($name, $value) = split /=/;
    $value =~ s/%([a-fA-F0-9]{2})/pack("C", hex($1))/eg;
    $value =~ s/\+/ /g;
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

sub httpServer {
  my ($port, $address, $router) = @_;

  return tcpServer($port, $address, evOut {
    bless shift, 'HTTPResponse';
  } evLine {
    my $h = $_[0];
    $h->{data} .= $_;
    my $rest;
    do {
      ($_, $rest) = split("\r\n\r\n", $h->{data}, 2);
      return if !defined($rest); # EOH not found
      my $cl = (split(/^content-length: /mi, $_, 2))[1] * 1;
      my $body = substr($rest, 0, $cl, '');
      return if length($body) < $cl; # wating for body
      $h->{data} = $rest;
      $h->{body} = /^content-type: application\/json\r/mi ? eval { decode_json($body); } || $body : $body;

      my $ref = ref $router;
      my $status = 501;
      my $r = $router;
      my $header = $_;
      my ($next, $qs);
      ($next ,$_) = split /[ \r]/, $_, 3;
      ($_, $qs) = split /\?/;
      while (1) {
        $ref = ref $r;
        if ($ref eq 'HASH') {
          defined($r = $r->{$next}) or last;
          $status = 404;
          s/^\/([^\/]*)//;
          $next = $1;
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
  });
}

1;
