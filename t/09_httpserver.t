use strict;
use warnings;
use Socket;
use Test::More tests => 21;

use InLoop;
use TCPInLoop;
use HTTPServer;

my $warn_count = 0;
local $SIG{__WARN__} = sub { $warn_count++; warn $_[0]; };

my $server_h;
$server_h = httpServer(0, '127.0.0.1', {
  GET => {
    'hello' => sub {
      my $h = shift;
      $h->say('Hello World');
    },
    'hello world' => sub {
      my $h = shift;
      $h->say('Found decoded path');
    },
    'json' => sub {
      my $h = shift;
      $h->httpResponse(200, { success => 1, message => 'ok' });
    },
    'query_test' => sub {
      my $h = shift;
      my $q = $h->{query};
      $h->httpResponse(200, {
        has_flag => exists $q->{flag} ? 1 : 0,
        flag_val => $q->{flag},
        name     => $q->{name},
      });
    },
  },
  POST => {
    'echo_json' => sub {
      my $h = shift;
      my $body = $h->{body};
      $h->httpResponse(200, { echoed => $body });
    },
  },
}, {
  idleTimeout => 100, # 100ms idle timeout for test
});

my $port = $server_h->{port};
ok($port > 0, "HTTP server listening on dynamic port $port");

my $client_res = '';

# Connect client 1: send valid GET /hello
my $c = tcpClient($port, '127.0.0.1', evLine {
  $client_res .= $_;
});
$c->write("GET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");

# Connect client 2: send oversized header (> 128KB without \r\n\r\n)
my $oversized_res = '';
my $c2 = tcpClient($port, '127.0.0.1', evLine {
  $oversized_res .= $_;
});
my $huge_header = "GET /test HTTP/1.1\r\nX-Long-Header: " . ("A" x (130 * 1024)) . "\r\n";
$c2->write($huge_header);

# Connect client 3: idle client that stays silent
my $idle_res = '';
my $c3 = tcpClient($port, '127.0.0.1', evLine {
  $idle_res .= $_;
});

# Connect client 4: send request with Connection: close
my $close_res = '';
my $client4_closed = 0;
my $c4 = tcpClient($port, '127.0.0.1', evLine {
  $close_res .= $_;
}, evHup {
  $client4_closed = 1;
});
$c4->write("GET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n");

# Connect client 5: POST with application/json; charset=utf-8
my $post_json_res = '';
my $json_payload = '{"user":"alice","num":42}';
my $c5 = tcpClient($port, '127.0.0.1', evLine {
  $post_json_res .= $_;
});
$c5->write(
  "POST /echo_json HTTP/1.1\r\n".
  "Host: 127.0.0.1\r\n".
  "Content-Type: application/json; charset=utf-8\r\n".
  "Content-Length: " . length($json_payload) . "\r\n\r\n".
  $json_payload
);

# Connect client 6: GET with querystring containing valueless flag & encoded space
my $query_res = '';
my $c6 = tcpClient($port, '127.0.0.1', evLine {
  $query_res .= $_;
});
$c6->write("GET /query_test?flag&name=John+Doe HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");

# Connect client 7: request with leading empty lines / CRLFs before request line
my $leading_crlf_res = '';
my $c7 = tcpClient($port, '127.0.0.1', evLine {
  $leading_crlf_res .= $_;
});
$c7->write("\r\n\r\n\r\nGET /hello HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");

# Connect client 8: GET with encoded path /hello%20world
my $path_res = '';
my $c8 = tcpClient($port, '127.0.0.1', evLine {
  $path_res .= $_;
});
$c8->write("GET /hello%20world HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");

# Connect client 9: HEAD /hello
my $head_res = '';
my $c9 = tcpClient($port, '127.0.0.1', evLine {
  $head_res .= $_;
});
$c9->write("HEAD /hello HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n");

setTimeout {
  like($client_res, qr{HTTP/1.1 200 Ok}, 'valid request status is 200');
  like($client_res, qr{Content-Type: text/plain}, 'content type is text/plain');
  like($client_res, qr{Hello World}, 'response body contains Hello World');

  like($oversized_res, qr{HTTP/1.1 431}, 'oversized header (> 128KB) rejected with 431');
  like($oversized_res, qr{Request Header Fields Too Large}, 'status text matches 431 description');

  like($idle_res, qr{HTTP/1.1 408}, 'idle client received 408 Request Timeout');
  like($idle_res, qr{Request Timeout}, 'status text matches 408 description');

  like($close_res, qr{Connection: close}, 'response has Connection: close header');
  ok($client4_closed, 'client was closed after response with Connection: close');

  like($post_json_res, qr{"echoed":\{.*"user":"alice"}, 'JSON payload decoded with charset directive');
  like($post_json_res, qr{"num":42}, 'JSON payload contains number attribute');
  like($query_res, qr{"has_flag":1}, 'valueless query parameter flag parsed');
  like($query_res, qr{"name":"John Doe"}, 'plus sign decoded to space in query parameter');

  like($leading_crlf_res, qr{HTTP/1.1 200 Ok}, 'request with leading CRLFs processed successfully');
  is($warn_count, 0, 'zero uninitialized warnings emitted during request processing');

  like($path_res, qr{Found decoded path}, 'URL-encoded path /hello%20world dispatched correctly');
  like($head_res, qr{HTTP/1.1 200 Ok}, 'HEAD request returned status 200');
  like($head_res, qr{Content-Length: 11}, 'HEAD request returned proper Content-Length');
  unlike($head_res, qr{\r\n\r\nHello World}, 'HEAD request omitted body');

  pass('HTTP server processed all requests correctly');
  exitInLoop();
} 250;
