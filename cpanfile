requires 'perl', '5.010';
requires 'Linux::FD::Timer';
requires 'Time::HiRes';
requires 'Scalar::Util';
requires 'JSON::PP';

on 'test' => sub {
    requires 'Test::More';
};
