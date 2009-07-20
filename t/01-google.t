#!/usr/bin/perl

use strict;

use Test::More qw( no_plan );
use I18N::LangTags qw( is_language_tag );

my $Text_In  = 'My hovercraft is full of eels.';
my $Text_Out = 'Mein Luftkissenfahrzeug ist voller Aale.';
my $API_Key  = 'notsupplied';

my $module = 'Lingua::Translate::Google';
my @methods = qw(
    new
    translate
    available
    agent
    config
);

use_ok($module);

my $xl8r = Lingua::Translate::Google->new( src => 'en', dest => 'de' );

can_ok( $xl8r, @methods );

ok(UNIVERSAL::isa($xl8r, 'Lingua::Translate::Google'),
   'Lingua::Translate::Google->new()');

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

# live translation (may fail if network access is unavailable)
{
    $xl8r->config( dest => 'es' );

    my $result = $xl8r->translate('hello world');

    is( $result, 'hola mundo', 'live translation works' );

    $xl8r->config( dest => 'en', src => 'auto' );

    $result = $xl8r->translate('Mi aerodeslizador está lleno de anguilas');

    is( $result, 'My hovercraft is full of eels', 'change to auto detect src' );
}

# live translation with auto src
{
    $xl8r->config( dest => 'en', src => 'auto' );

    my $hello_world = $xl8r->translate('hola mundo');

    is( $hello_world, 'hello world', 'auto src live translation works' );
}

# Override LWP::UserAgent::request
# and verify correct output for mocked translation service.
{
    no warnings qw( once redefine );

    # Intercepts the network request and returns a sensible value.
    # Thus, the test assumes that LWP::UserAgent::request and Google
    # working correctly.
    local *LWP::UserAgent::request = sub {
        my $self = shift;
        my ($req) = @_;

        if ( $req->uri() !~ m/google(?:apis)?[.]com/ ) {

            # Any non-google URL is a bad request
            my $res = HTTP::Response->new( 404, 'Bad hostname' );
            return $res;
        }
        else {

            my $query_regex = $Text_In;
            $query_regex =~ s/ /%20/g;

            # Check for various bad ways to invoke the Google service
            # and die to simulate Google barfing on the request.

            die 'unexpected value sent to google'
                if $req->uri() !~ m/$query_regex/;

            die 'wrong API key sent: ' . $req->uri()
                if $req->uri() =~ m/key=/ && $req->uri() !~ m/$API_Key/;

            die 'wrong URI'
                if $req->uri() !~ m/googleapis\.com/;

            my $res = HTTP::Response->new( 200 );
            $res->content( qq({"responseData": {"translatedText":"$Text_Out"}, "responseDetails": null, "responseStatus": 200}) );
            $res->header( 'Content-Type' => 'text/json;charset=UTF-8' );
            return $res;
        }
    };

    my $translated_result;

    # test basic translation with no API key
    $translated_result = $xl8r->translate($Text_In);
    like(
        $translated_result,
        qr/Mein \s+ Luftkissenfahrzeug \s+ ist \s+ voller \s+ Aale\./msx,
        'Lingua::Translate::Google->translate [en -> de] without API key'
    );

    # test translation with API key
    $API_Key = 'mock_api_key';
    $xl8r->config(
        api_key => $API_Key,
        referer => 'http://mock.tld/dir'
    );
    $translated_result = $xl8r->translate($Text_In);
    like(
        $translated_result,
        qr/Mein \s+ Luftkissenfahrzeug \s+ ist \s+ voller \s+ Aale\./msx,
        'Lingua::Translate::Google->translate [en -> de] with API key'
    );

    # test to a bogus URL
    eval {
        $xl8r->config(
            google_uri => 'http://badbadbad/translate?'
        );
        $xl8r->translate('Something');
        fail("Translation with bad URI didn't die");
    };
    like($@, qr/Bad hostname|Request timed out/, 'dies with bad URI');
}

1;
