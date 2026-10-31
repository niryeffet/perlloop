use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
  NAME          => 'InLoop',
  VERSION_FROM  => 'lib/InLoop.pm',
  AUTHOR        => 'Nir Yeffet',
  PREREQ_PM     => {
    'Linux::FD::Timer' => 0,
    'Time::HiRes'      => 0,
    'Scalar::Util'     => 0,
  },
  TEST_REQUIRES => {
    'Test::More' => 0,
  },
  test          => { TESTS => 't/*.t' },
);
