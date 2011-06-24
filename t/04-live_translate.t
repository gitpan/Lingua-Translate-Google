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

    my @expect = qw( hola mundo );

    my $expect = @expect;
    my $got    = grep {$_} map { -1 != ( index $result, $_ ) ? 1 : 0 } @expect;

    is( $got, $expect, 'live translation: auto en to es works' );
}

# auto es to en
{
    $xl8r->config( dest => 'en', src => 'auto' );

    my $result = lc $xl8r->translate('Mi aerodeslizador está lleno de anguilas');

    my @expect = qw( my hovercraft is full of eels );

    my $expect = @expect;
    my $got    = grep {$_} map { -1 != ( index $result, $_ ) ? 1 : 0 } @expect;

    is( $got, $expect, 'live translation: auto es to en works' );
}

# ja to en
{
    $xl8r->config( dest => 'en', src => 'ja' );

    my $result = lc $xl8r->translate('こんにちは世界');

    my @expect = qw( hello world );

    my $expect = @expect;
    my $got    = grep {$_} map { -1 != ( index $result, $_ ) ? 1 : 0 } @expect;

    is( $got, $expect, 'live translation: ja to en works' );
}
