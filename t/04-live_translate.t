#!/usr/bin/perl

use utf8;
use strict;
use warnings;

use Test::More qw( no_plan );

my $ua = LWP::UserAgent->new();
my $response = $ua->get('http://www.google.com/');
if (!$response->is_success) {
    local $TODO = 'network access is necessary for these tests';
    fail( $response->status_line() );
    exit;
}

use Lingua::Translate::Google;

my $xl8r = Lingua::Translate->new(
    back_end => 'Google',
    src      => 'auto',
    dest     => 'es',
);

# auto en to es
{
    my $result = lc $xl8r->translate('hello world');

    is( $result, 'hola mundo', 'live translation: auto en to es works' );
}

# auto es to en
{
    $xl8r->config( dest => 'en', src => 'auto' );

    my $result = lc $xl8r->translate('Mi aerodeslizador está lleno de anguilas');

    is( $result, 'my hovercraft is full of eels', 'live translation: auto es to en works' );
}

# ja to en
{
    $xl8r->config( dest => 'en', src => 'ja' );

    my $result = lc $xl8r->translate('こんにちは世界');

    is( $result, 'hello world', 'live translation: ja to en works' );
}
