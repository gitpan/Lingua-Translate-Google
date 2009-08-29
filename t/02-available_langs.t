#!/usr/bin/perl

use strict;
use warnings;

use Test::More qw( no_plan );
use I18N::LangTags qw( is_language_tag );
use LWP::UserAgent;
use Lingua::Translate::Google;

my $ua = LWP::UserAgent->new();
my $response = $ua->get('http://www.google.com/');
if (!$response->is_success) {
    local $TODO = 'network access is necessary for these tests';
    fail( $response->status_line() );
    exit;
}

my $xl8r = Lingua::Translate::Google->new(
    src              => 'en',
    dest             => 'de',
    save_auto_lookup => 0,
);

# Validate the list of available languages
{
    my @available_langpairs = $xl8r->available();

    isa_ok( \@available_langpairs, 'ARRAY', 'available returns an array' );

    ok( @available_langpairs > 0, 'available returns results' );

    my %lang_tags;
    for my $langpair ( @available_langpairs ) {

        my ($sl,$tl) = split /_/, $langpair;

        $lang_tags{$sl} = 1;
        $lang_tags{$tl} = 1;
    }
    for my $lang_tag (keys %lang_tags) {

        ok( is_language_tag($lang_tag), "$lang_tag is a valid I18N language tag" );
    }
}

1;
