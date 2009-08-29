#!/usr/bin/perl

use strict;
use warnings;

use Test::More qw( no_plan );
use Lingua::Translate;

my $xl8r;

eval {

    $xl8r = Lingua::Translate->new(
        back_end => 'Google',
        src      => 'auto',
        dest     => 'de',
    );
};

like( $@, qr{not \s a \s valid \s RFC3066}xms, 'auto identified as invalid' );

ok( !$xl8r, "didn't create an auto src translator" );
