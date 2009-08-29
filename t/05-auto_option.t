#!/usr/bin/perl

use strict;
use warnings;

use Test::More qw( no_plan );
use Lingua::Translate;

Lingua::Translate::config(
    back_end => 'Google',
);

my $xl8r = Lingua::Translate->new(
    src      => 'auto',
    dest     => 'de',
);

ok( $xl8r, 'created an auto src translator' );
