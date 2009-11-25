package Lingua::Translate::Google;

# Copyright (c) 2008, Dylan Doxey.  All rights reserved. This program
# is free software; you may use it under the same terms as Perl
# itself.
#
# Revised copy of Lingua::Translate::Babelfish by Sam Vilain
# <enki@snowcra.sh>
#

our $VERSION = '0.10';

use strict;
use warnings;
{
    use Carp;
    use LWP::UserAgent;
    use Unicode::MapUTF8 qw( to_utf8 );
    use HTTP::Request::Common qw( GET );
    use URI::Escape qw( uri_escape_utf8 );
}

# package globals:
use vars qw( %valid_langs );

my (
    $AJAX_URI,
    $LANG_DETECT_URI,
    $TRANSLATE_URI,
    %OPTION_DEFAULTS,
);
{
    use Readonly;

    Readonly $AJAX_URI        => 'http://ajax.googleapis.com/ajax/services/language/translate';
    Readonly $TRANSLATE_URI   => 'http://translate.google.com/#';
    Readonly $LANG_DETECT_URI => 'http://www.google.com/uds/GlangDetect';

    Readonly %OPTION_DEFAULTS => (
        api_key          => 'notsupplied',
        agent            => __PACKAGE__ . "/$VERSION",
        retries          => 2,
        src              => 'auto',
        save_auto_lookup => 1,
        _src_is_auto     => 0,
    );
}

# hack to allow 'auto' as a valid lang tag
BEGIN {

    use Lingua::Translate;

    my $is_language_tag_rc = \&Lingua::Translate::is_language_tag;

    no warnings 'redefine';

    *Lingua::Translate::is_language_tag = sub {
        my ($tag) = @_;
        return 1
            if $tag eq 'auto';
        return $is_language_tag_rc->($tag);
    };
}

{
    # package options

    my %_options;

    sub _set_option {
        my ($key,$val) = @_;
        $_options{$key} = $val;

        return $val;
    }

    sub _get_option {
        my ($key) = @_;
        return $_options{$key};
    }

    sub _get_options {
        return \%_options;
    }
}

sub new {

    my ( $class, %config ) = @_;

    my $self = bless {%config}, $class;

    return $self;
}

sub translate {
    my ($self,$text) = @_;

    UNIVERSAL::isa( $self, __PACKAGE__ )
        or croak __PACKAGE__ . '::translate() called as function';

    $self->_refresh_options();

    croak "no dest language specified\n"
        if !defined $self->{dest};

    croak "$self->{dest} is not available on Google translate"
        if !$self->available( $self->{dest}, 'fresh_options' );

    if ( $self->{src} ne 'auto' ) {

        croak "$self->{src} is not available on Google translate"
            if !$self->available( $self->{src}, 'fresh_options' );
    }

    $self->{langpair} = $self->{src} . '%7C' . $self->{dest};

    if ( $self->{src} eq 'auto' ) {

        my %params = (
            context  => 22,
            v        => '1.0',
            key      => $self->{api_key},
            callback => 'google.language.callbacks.id100',
            q        => $text,
        );
        my $query = join '&', map { "$_=" . uri_escape_utf8( $params{$_} ) } keys %params;

        my $req = GET "$LANG_DETECT_URI?$query";

        my $res = $self->agent->request($req);

        my $json = $res->content() || "";

        if ( $json =~ m/ "language" \s* : \s* "( \w+ )" /xms ) {

            my $src = $1;

            $self->{langpair} = $src . '%7C' . $self->{dest};

            if ( $self->{save_auto_lookup} ) {

                $self->{src} = $src;
                _set_option( '_src_is_auto', 1 );
            }
        }
        else {
            warn "couldn't auto detect language\n";
            return;
        }
    }

    my %params = (
        v        => '1.0',
        langpair => $self->{langpair},
        key      => $self->{api_key},
        q        => uri_escape_utf8( $text ),
    );

    my $query = join '&', map { "$_=$params{$_}" } keys %params;

    my $req = GET "$AJAX_URI?$query";

    $self->{referer} ||= $AJAX_URI;

    $req->header( 'Referer',        $self->{referer} );
    $req->header( 'Accept-Charset', 'UTF-8' );

    my ( @translated, $error );

    RETRY:
    for my $attempt ( 1 .. $self->{retries} + 1 ) {

        my $res = $self->agent->request($req);

        if ( $res->is_success ) {

            my $output = $self->_extract_text(
                $res->content(),
                $res->header('Content-Type')
            );

            # trim
            $output =~ s/(?: \A \s* | \s* \z )//msxg;

            push @translated, $output;

            last RETRY;
        }
        else {
            $error .= "Request $attempt:" . $res->status_line . '; ';
        }
    }

    die "Translation failed after $self->{retries} attempts ($error)"
        if !@translated;

    return join ' ', @translated;
}

# Extracts the translated text from the given Google response text.
sub _extract_text {
    my ( $self, $response_text, $content_type ) = @_;

    my $translated;

    # AJAX JSON (googleapis.com) response
    # {"responseData": {"translatedText":"hello world"}, "responseDetails": null, "responseStatus": 200}
    if ( $response_text =~ m/"translatedText" \s* : \s* "([^"]*)"/xms ) {
        $translated = $1;
    }

    # Fallback (/translate_a?) type response
    # "hello world"
    elsif ( $response_text =~ m/^"([^"]*)"$/ ) {
        $translated = $1;
    }

    # Error response like:
    # {"responseData": null, "responseDetails": "invalid translation language pair", "responseStatus": 400}
    elsif (   $response_text =~ m/"responseData" \s* : \s* null,/xms
        && $response_text =~ m/"responseDetails" \s* : \s* "( [^"]* )"/xms )
    {
        my $details = $1;

        if ( $details =~ m/language \s pair/xms ) {
            $details .= "; $self->{langpair}";
        }

        die "Google error response: $details\n";
    }

    die "Google response unparsable: $response_text\n"
        if !$translated;

    # JS unicode escapes to plain text
    $translated =~ s/\\u([\d]{4})/chr( sprintf( '%d', hex($1) ) )/eg;

    # HTML entities to plain text
    $translated =~ s/&#([\d]+);/chr( $1 )/eg;

    my ($encoding) = ( $content_type =~ m/charset=(\S*)/ );

    if ( $encoding =~ /^utf-?8$/i ) {

        return $translated;
    }

    return to_utf8( { -string => $translated, -charset => $encoding } );
}

# Returns the available language translation pairs.
sub available {
    my ($self,$lang_inquiry,$fresh_options) = @_;

    UNIVERSAL::isa( $self, __PACKAGE__ )
        or croak __PACKAGE__ . '::available() called as function';

    if ( !$fresh_options ) {
        $self->_refresh_options();
    }

    # return a cached result
    if ( my $ok_langs = $valid_langs{ $TRANSLATE_URI } ) {

        return $self->_has_language( $lang_inquiry )
            if $lang_inquiry;

        return keys %{ $ok_langs };
    }

    # create a new request
    my $req = GET $TRANSLATE_URI;
    $req->header( 'Referer', $TRANSLATE_URI );
    $req->header( 'Accept-Charset', 'UTF-8' );

    my $res = $self->agent->request($req);

    die 'Google fetch failed; ' . $res->status_line()
        unless $res->is_success();

    my $page = $res->content();

    my @source_langs;
    if ( $page =~ m{<select .+? name=sl .+? > ( .*? ) </select>}msx ) {

        my $options = $1;

        while ( $options =~ m{<option \s+ value="([^"]+)">}msxg ) {

            my $lang = $1;
            push @source_langs, $lang;
        }
    }

    my @list;
    if ( $page =~ m{<select .+? name=tl .+? > ( .*? ) </select>}msx ) {

        my $options = $1;

        while ( $options =~ m{<option \s+ value="([^"]+)">}msxg ) {

            my $dest = $1;

            # Presumably any source language is paired with any to language.
            LANG:
            for my $src (@source_langs) {

                next LANG
                    if $src eq 'auto';

                my $pair = "$src\_$dest";

                unless (   Lingua::Translate::is_language_tag($src)
                        && Lingua::Translate::is_language_tag($dest) )
                {
                    warn "Don't recognise '$pair' as a valid language pair";
                    next LANG;
                }
                push @list, $pair;
            }
        }
    }

    if ( @list > 0 ) {

        # save the result
        %{ $valid_langs{ $TRANSLATE_URI } } = map { $_ => 1 } @list;

        return $self->_has_language( $lang_inquiry )
            if $lang_inquiry;

        return @list;
    }
    
    warn "unable to parse valid language tokens from $TRANSLATE_URI";
    return;
}

sub _has_language {
    my $self = shift;
    my ($lang_inquiry) = @_;

    my $lang_regex = qr{ (?: \A $lang_inquiry _ | _ $lang_inquiry \z ) }msx;

    for my $lang_pair (keys %{ $valid_langs{ $TRANSLATE_URI } }) {

        return 1
            if $lang_pair =~ $lang_regex;
    }
    return 0;
}

# Returns the LWP::UserAgent object.
sub agent {

    my $self;
    if ( UNIVERSAL::isa( $_[0], __PACKAGE__ ) ) {
        $self = shift;
    }

    my $ua = _get_option( 'ua' );

    unless ( $ua ) {
        $ua = LWP::UserAgent->new();
        $ua->agent( _get_option( 'agent' ) );
        $ua->env_proxy();
        _set_option( 'ua', $ua );
    }

    return $ua;
}

# set configuration options
sub config {

    my $self = shift
        if ref $_[0] eq __PACKAGE__;

    croak "uneven number of arguments given\n"
        if @_ % 2;

    my %args = @_;

    my %valid_option_for = (
        api_key              => 1,
        referer              => 1,
        ua                   => 1,
        agent                => 1,
        retries              => 1,
        src                  => 1,
        dest                 => 1,
        save_auto_lookup     => 1,
    );

    OPTION:
    for my $option (keys %args) {

        croak "$option is not a recognized option\n"
            if !exists $valid_option_for{$option};

        my $value = $args{$option};

        if ( $option eq 'src' ) {

            croak "$value is not a valid RFC3066 language tag"
                if $value ne 'auto' && !Lingua::Translate::is_language_tag( $value );

            _set_option( '_src_is_auto', 0 );
        }
        elsif ( $option eq 'dest' ) {

            croak "$value is not a valid RFC3066 language tag"
                if !Lingua::Translate::is_language_tag( $value );
        }

        _set_option( $option, $value );
    }
}

sub _refresh_options {
    my ($self) = @_;

    my $options_rh = _get_options();

    $self->{_src_is_auto} = delete $options_rh->{_src_is_auto} || 0;

    while ( my ($option,$value) = each %{ $options_rh }) {

        next
            if $option eq 'src' && $self->{_src_is_auto};

        $self->{$option} = $value;
    }

    while ( my ($option,$value) = each %OPTION_DEFAULTS ) {

        next
            if defined $self->{$option};

        $self->{$option} = $value;
    }

    return 1;
}

1;
