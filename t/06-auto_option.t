#!/usr/bin/perl

use strict;
use warnings;

use Test::More qw( no_plan );
use Lingua::Translate::Google;

my $xl8r = Lingua::Translate->new(
    back_end => 'Google',
    src      => 'auto',
    dest     => 'de',
);

ok( $xl8r, 'created an auto src translator' );
