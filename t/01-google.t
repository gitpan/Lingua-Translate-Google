#!/usr/bin/perl

use strict;
use warnings;

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

my $xl8r = Lingua::Translate::Google->new(
    src              => 'en',
    dest             => 'de',
    save_auto_lookup => 0,
);

can_ok( $xl8r, @methods );

ok( UNIVERSAL::isa($xl8r, 'Lingua::Translate::Google'),
   'Lingua::Translate::Google->new()' );

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

            die 'wrong API key sent: ' . $req->uri()
                if $req->uri() =~ m/key=/ && $req->uri() !~ m/$API_Key/;

            my $res = HTTP::Response->new( 200 );

            if ( $req->uri() =~ m/GlangDetect/xms ) {
                $res->content( qq({"responseData": {"language":"es"}, "responseStatus": 200}) );
            }
            elsif ( $req->uri() =~ m{ translate[.]google[.]com/[#] }xms ) {

                my $html = qq{
                    <select class=sllangdropdown name=sl id="old_sl" tabindex=0 >
                        <option value="en">
                        <option value="es">
                        <option value="ja">
                        <option value="de">
                    </select>
                    <select class=tllangdropdown name=tl id="old_tl" tabindex=0 >
                        <option value="en">
                        <option value="es">
                        <option value="ja">
                        <option value="de">
                    </select>
                };

                $res->content($html);
            }
            else {
                $res->content( qq({"responseData": {"translatedText":"$Text_Out"}, "responseDetails": null, "responseStatus": 200}) );
            }

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
        referer => 'http://mock.tld/dir',
        format  => 'text',
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
        fail("didn't croak on bogus option");
    };
    like($@, qr/not a recognized option/, 'croaks on bogus option');
}

1;
