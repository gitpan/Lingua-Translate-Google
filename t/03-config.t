#!/usr/bin/perl

use strict;
use warnings;

use Test::More qw( no_plan );
use Lingua::Translate;

my $Expected_LangPair;
my $Submitted_LangPair;
my $Detected_Lang;

# Override LWP::UserAgent::request
# and verify correct output for mocked translation service.
{
    no warnings qw( once redefine );

    # Intercepts the network request and returns a sensible value.
    *LWP::UserAgent::request = sub {
        my ($self,$req) = @_;

        my $uri = $req->uri();

        my ($src,$dest) = $req->content() =~ m{ \W langpair = ( \w+ ) %7C ( \w+ ) & }xms;
        my ($txt)       = $req->content() =~ m{ \W q = ( .+? ) & }xms;

        if ( $uri eq 'http://translate.google.com/#' ) {

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

            my $res = HTTP::Response->new( 200 );
            $res->content( $html );

            return $res;
        }
        elsif ( $uri eq 'http://www.google.com/uds/Gtranslate' ) {

            my $lang
                = $txt =~ m{japanese} ? 'ja'
                : $txt =~ m{english}  ? 'en'
                :                       'xx';

            my $json = qq{"detectedSourceLanguage": "$lang"};

            my $res = HTTP::Response->new( 200 );
            $res->content( $json );
            return $res;
        }
        elsif ( $uri eq 'http://ajax.googleapis.com/ajax/services/language/translate' ) {

            $Submitted_LangPair = "$src|$dest";

            my $json = qq{"translatedText" : "mock translation"};

            my $res = HTTP::Response->new( 200 );
            $res->header( 'Content-Type' => 'text/json; charset=UTF-8' );
            $res->content( $json );
            return $res;
        }
        else {

            die "unexpected URI:$uri\n";
        }
        return;
    };
}

use Lingua::Translate::Google;

my $xl8r = Lingua::Translate->new(
    back_end => 'Google',
    src      => 'auto',
    dest     => 'de',
);

my $result;
{
    $Expected_LangPair = 'en|de';
    $Submitted_LangPair = undef;

    $result = $xl8r->translate('mock english');
    is( $result, 'mock translation', 'mock translation completed' );

    is( $Submitted_LangPair, $Expected_LangPair, 'correct langpair submitted' );
}

{
    $Expected_LangPair = 'es|de';
    $Submitted_LangPair = undef;

    $xl8r->config( src => 'es' );

    $result = $xl8r->translate('hola mundo');
    is( $result, 'mock translation', 'mock translation completed' );

    is( $Submitted_LangPair, $Expected_LangPair, 'correct langpair submitted' );
}

{
    $Expected_LangPair = 'ja|de';
    $Submitted_LangPair = undef;

    $xl8r->config( src => 'auto', save_auto_lookup => 1 );

    $result = $xl8r->translate('mock japanese');
    is( $result, 'mock translation', 'mock translation completed' );

    is( $Submitted_LangPair, $Expected_LangPair, 'correct langpair submitted' );

    $result = $xl8r->translate('same auto src as before');
    is( $result, 'mock translation', 'mock translation completed' );

    is( $Submitted_LangPair, $Expected_LangPair, 'correct langpair submitted' );
}

{
    $Expected_LangPair = 'en|es';
    $Submitted_LangPair = undef;

    $xl8r->config( src => 'en', dest => 'es' );

    $result = $xl8r->translate('mock english');
    is( $result, 'mock translation', 'mock translation completed' );

    is( $Submitted_LangPair, $Expected_LangPair, 'correct langpair submitted' );
}

1;
