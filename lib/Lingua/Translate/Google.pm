#!/usr/bin/perl -Tw

# Copyright (c) 2008, Dylan Doxey.  All rights reserved. This program
# is free software; you may use it under the same terms as Perl
# itself.
#
# Revised copy of Lingua::Translate::Babelfish by Sam Vilain
# <enki@snowcra.sh>
#
package Lingua::Translate::Google;

$VERSION = '0.08';

use strict;
use warnings;
{
    use Carp;
    use LWP::UserAgent;
    use HTTP::Request::Common qw( GET );
    use Unicode::MapUTF8 qw( to_utf8 );
    use I18N::LangTags qw( is_language_tag );
}

# package globals:
use vars qw( $VERSION %config %valid_langs );

my (
    $URI, $LANG_DETECT_URL, $TRANSLATE_URI, $DEFAULT_KEY,
    $DEFAULT_AGENT, $DEFAULT_CHUNK_SIZE, $DEFAULT_RETRIES
);
{
    use Readonly;

    Readonly $DEFAULT_KEY        => 'notsupplied';
    Readonly $URI                => 'http://ajax.googleapis.com/ajax/services/language/translate?';
    Readonly $TRANSLATE_URI      => 'http://translate.google.com/translate_t#';
    Readonly $LANG_DETECT_URL    => 'http://www.google.com/uds/GlangDetect?';
    Readonly $DEFAULT_AGENT      => __PACKAGE__ . "/$VERSION";
    Readonly $DEFAULT_CHUNK_SIZE => 1000;
    Readonly $DEFAULT_RETRIES    => 2;
}

sub new {
    my ( $class, %options ) = (@_);

    my $self = bless {%config}, $class;

    croak 'Must supply destination language'
        unless defined $options{dest};

    $self->{src}  = exists $options{src} ? delete $options{src} : 'auto';
    $self->{dest} = delete $options{dest};

    if ( $self->{src} ne 'auto' ) {

        is_language_tag( $self->{src} )
            or croak "$self->{src} is not a valid RFC3066 language tag";

        $self->available( $self->{src} )
            or croak "$self->{src} is not available on Google translate";
    }

    is_language_tag( $self->{dest} )
        or croak "$self->{dest} is not a valid RFC3066 language tag";

    $self->available( $self->{dest} )
        or croak "$self->{dest} is not available on Google translate";

    $self->config(%options);

    return $self;
}

sub translate {
    my $self = shift;

    UNIVERSAL::isa( $self, __PACKAGE__ )
      or croak __PACKAGE__ . '::translate() called as function';

    my $text = shift;

    # TODO Determine if chunkification is necessary for Google.
    my @chunks = (
        $text =~ m/\G\s*   # strip excess white space
			     (
			         # some non-whitespace, then some data
			         \S.{0,$self->{chunk_size}}

			         # either a full stop or the end of
			         # string
			         (?:[\.;:!\?]|$)
			     )
        /xsg
    );
    die 'Could not break up given text into chunks'
        if ( pos($text) and pos($text) < length($text) );

    if ( $self->{src} eq 'auto' ) {

        my %params = (
            context  => 22,
            v        => '1.0',
            key      => $self->{api_key},
            callback => 'google.language.callbacks.id100',
            q        => $chunks[0],
        );
        my $query = join '&', map { "$_=$params{$_}" } keys %params;

        my $req = GET "$LANG_DETECT_URL$query";

        my $res = $self->agent->request($req);

        my $json = $res->content() || "";

        if ( $json =~ m/ "language" : "( \w+ )" /xms ) {

            $self->{src} = $1;
        }
        else {
            warn "sorry, couldn't auto detect language\n";
            return;
        }
    }

    my ( @translated, $error );

    CHUNK:
    for my $chunk (@chunks) {

        my $req;

        my %params = (
            v        => '1.0',
            q        => $chunk,
            langpair => $self->{src} . '%7C' . $self->{dest},
        );

        if ( $self->{api_key} ) {

            $params{key} = $self->{api_key};
        }

        my $query = join '&', map { "$_=$params{$_}" } keys %params;

        $req = GET "$self->{google_uri}$query";

        $self->{referer} ||= $URI;

        $req->header( 'Referer',        $self->{referer} );
        $req->header( 'Accept-Charset', 'UTF-8' );

        # try several times to reach google
        RETRY:
        for my $attempt ( 1 .. $self->{retries} + 1 ) {

            my $res = $self->agent->request($req);

            if ( $res->is_success ) {

                my $output = $self->_extract_text(
                    $res->content(),
                    $res->header('Content-Type')
                );

                # google errors
                # TODO Get the correct message text
                next RETRY
                    if $output =~ m/ Out \s+ of \s+ commission /msx;

                # trim
                $output =~ s/(?: \A \s* | \s* \z )//msxg;

                push @translated, $output;

                next CHUNK;

            }
            else {
                $error .= "Request $attempt:" . $res->status_line . '; ';
            }
        }

        # give up
        die "Request timed out more than $self->{retries} times ($error)";
    }

    return join ' ', @translated;
}

# Extracts the translated text from the given Google response text.
sub _extract_text {
    my ( $self, $response_text, $contenttype ) = @_;

    my $translated;

    # AJAX JSON (googleapis.com) response
    # {"responseData": {"translatedText":"hello world"}, "responseDetails": null, "responseStatus": 200}
    if ( $response_text =~ m/"translatedText":"([^"]*)"/ ) {
        $translated = $1;
    }

    # Fallback (/translate_a?) type response
    # "hello world"
    elsif ( $response_text =~ m/^"([^"]*)"$/ ) {
        $translated = $1;
    }

    # JS unicode escapes to plain text
    $translated =~ s/\\u([\d]{4})/chr( sprintf( '%d', hex($1) ) )/eg;

    # HTML entities to plain text
    $translated =~ s/&#([\d]+);/chr( $1 )/eg;

    die 'Google response unparsable, brain needed'
        if !$translated;

    my ($encoding) = ( $contenttype =~ m/charset=(\S*)/ );

    if ( $encoding =~ /^utf-?8$/i ) {
        return $translated;
    }
    else {
        return to_utf8( { -string => $translated, -charset => $encoding } );
    }
}

# Returns the available language translation pairs.
sub available {
    my $self = shift;
    my ($lang_inquiry) = @_;

    UNIVERSAL::isa( $self, __PACKAGE__ )
      or croak __PACKAGE__ . '::available() called as function';

    my $uri = $self->{google_translate_uri};

    # return a cached result
    if ( my $ok_langs = $valid_langs{ $uri } ) {

        return $self->_has_language( $lang_inquiry )
            if $lang_inquiry;

        return keys %{ $ok_langs };
    }

    # create a new request
    my $req = GET $uri;
    $req->header( 'Referer', $uri );
    $req->header( 'Accept-Charset', 'UTF-8' );

    my $res = $self->agent->request($req);

    die 'Google fetch failed; ' . $res->status_line()
        unless $res->is_success();

    # extract out the languages
    my $page = $res->content();

    my @source_langs;
    if ( $page =~ m{<select \s+ name=sl [^>]+ > ( .*? ) </select>}msx ) {

        my $options = $1;

        while ( $options =~ m{<option \s+ value="([^"]+)">}msxg ) {

            my $lang = $1;
            push @source_langs, $lang;
        }
    }
    my @list;
    if ( $page =~ m{<select \s+ name=tl [^>]+ > ( .*? ) </select>}msx ) {

        my $options = $1;

        while ( $options =~ m{<option \s+ value="([^"]+)">}msxg ) {

            my $dest = $1;

            # Presumably any source language is paired with any to language.
            LANG:
            for my $src (@source_langs) {

                next LANG
                    if $src eq 'auto';

                my $pair = "$src\_$dest";

                unless ( is_language_tag($src) and is_language_tag($dest) ) {
                    warn "Don't recognise '$pair' as a valid language pair";
                    next;
                }
                push @list, $pair;
            }
        }
    }

    if ( @list > 0 ) {

        # save the result
        %{ $valid_langs{ $uri } } = map { $_ => 1 } @list;

        return $self->_has_language( $lang_inquiry )
            if $lang_inquiry;

        return @list;
    }
    warn "unable to parse valid language tokens from $uri";
    return;
}

sub _has_language {
    my $self = shift;
    my ($lang_inquiry) = @_;

    my $lang_regex = qr{ (?: \A $lang_inquiry _ | _ $lang_inquiry \z ) }msx;

    for my $lang_pair (keys %{ $valid_langs{ $self->{google_translate_uri} } }) {

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
    else {
        $self = \%config;
    }

    unless ( $self->{ua} ) {
        $self->{ua} = LWP::UserAgent->new();
        $self->{ua}->agent( $self->{agent} );
        $self->{ua}->env_proxy();
    }

    $self->{ua};
}

# set configuration options
sub config {

    my $self;
    if ( UNIVERSAL::isa( $_[0], __PACKAGE__ ) ) {
        $self = shift;
    }
    else {
        $self = \%config;
    }

    while ( my ( $option, $value ) = splice @_, 0, 2 ) {

        if ( $option eq 'google_uri' ) {

            # set the Google URI
            ( $self->{google_uri} = $value ) =~ m/\?(.*&)?$/
              or croak "Google URI '$value' not a query URI";

        }
        elsif ( $option eq 'google_translate_uri' ) {

            $self->{google_translate_uri} = $value;
        }
        elsif ( $option eq 'api_key' ) {

            $self->{api_key} = $value;
        }
        elsif ( $option eq 'referer' ) {

            $self->{referer} = $value;
        }
        elsif ( $option eq 'ua' ) {

            $self->{ua} = $value;
        }
        elsif ( $option eq 'agent' ) {

            # set the user-agent
            $self->{agent} = $value;
            $self->{ua}->agent($value) if $self->{ua};
        }
        elsif ( $option eq 'chunk_size' ) {

            $self->{chunk_size} = $value;
        }
        elsif ( $option eq 'use_cache' ) {

            $self->{use_cache} = $value;
        }
        elsif ( $option eq 'retries' ) {

            $self->{retries} = $value;
        }
        elsif ( $option eq 'src' ) {

            $self->{src} = $value;
        }
        elsif ( $option eq 'dest' ) {

            $self->{dest} = $value;
        }
        else {

            croak "Unknown configuration option $option";
        }
    }
}

# set defaults
config( 'api_key'              => $DEFAULT_KEY        );
config( 'google_uri'           => $URI                );
config( 'google_translate_uri' => $TRANSLATE_URI      );
config( 'agent'                => $DEFAULT_AGENT      );
config( 'chunk_size'           => $DEFAULT_CHUNK_SIZE );
config( 'retries'              => $DEFAULT_RETRIES    );

1;


__END__

=head1 NAME

Lingua::Translate::Google - Translation back-end for Google's beta translation service.

=head1 SYNOPSIS

 use Lingua::Translate;

 Lingua::Translate::config
     (
         back_end => 'Google',
         api_key  => 'YoUrApIkEy',
         referer  => 'http://your.domain.tld/yourdir/',
     );

 my $xl8r = Lingua::Translate->new( src => 'de', dest => 'en' );

 # prints 'My hovercraft is full of eels'
 print $xl8r->translate('Mein Luftkissenfahrzeug ist voller Aale');

 # switch to auto detect for source language
 $xl8r->config( src => 'auto' );

 # prints 'My hovercraft is full of eels'
 $xl8r->translate('Mi aerodeslizador está lleno de anguilas');

=head1 DESCRIPTION

Lingua::Translate::Google is a translation back-end for Lingua::Translate
that contacts Google translation service to do the real work.
The Google translation API is currently at:
L<http://code.google.com/apis/ajaxlanguage/documentation/#Translation>

Lingua::Translate::Google is normally invoked by Lingua::Translate; there
should be no need to call it directly.  If you do call it directly, you will
lose the ability to easily switch your programs over to alternate back-ends
that are later produced.

=over

=item Please read:

By using Google services (either directly or via this module) you are
agreeing by their terms of service.

L<http://www.google.com/accounts/TOS>

=item Referer URL

Google asks that you include a meaningful referer value to identify the
API users.

=item API key

The API key is optional.

L<http://code.google.com/apis/ajaxfeeds/signup.html>

=back

=head1 CONSTRUCTOR

=head2 new( src => $lang, dest => $lang )

Creates a new translation handle. Determines whether the requested language
pair is available and will croak if not.

=over

=item src

Source language, in RFC-3066 form. See L<I18N::LangTags> for a discussion of
RFC-3066 language tags.

As of version 0.06 this option can be omitted or given a value 'auto'.

=item dest

Destination Language

=back

Other options that may be passed to the config() function (see below) may
also be passed as arguments to this constructor.

=head1 METHODS

The following methods may be called on Lingua::Translate::Google objects.

=head2 available() : @list

Returns a list of available language pairs, in the form of 'XX_YY', where XX
is the source language and YY is the destination. If you want the english
name of a language tag, call I18N::LangTags::List::name() on it.
See L<I18N::LangTags::List>.

This method contacts Google (at http://translate.google.com/translate_t) and
parses from the HTML the available language pairs. The list of language
pairs is cached for subsequent calls.

You may also use this method to see if a given language tag is available.

 die "doesn't have 'he'"
     if !$xl8tr->available('he');

=head2 translate($text) : $translated

Translates the given text, or die's on any kind of error.

It is assumed that the $text coming in is UTF-8 encoded, and that Google will
be returning UTF-8 encoded text. In the case that Google returns some other
encoding, then an attempt to convert the result to UTF-8 is made with
Unicode::MapUTF8::to_utf8. Observation has indicated that the fallback
service (at /translate_a/t) is inclined to return windows-1255 encoded text,
despite the value of the 'Accept-Charset' header sent in the request.
However, a non-windows user agent string seems to remedy this.

Google returns JSON which assumes the client is JavaScript running with an
HTML document. This being the case strings are double encoded. First special
characters are converted to HTML entities, and then the ampersands are
converted to unicode escape sequences. For example, the string "Harold's" is
encoded as "Harold\u0027#39;s". The translate function attempts to return
plain old UTF-8 encoded strings without any entities or escape sequences.

=head2 agent() : LWP::UserAgent

Returns the LWP::UserAgent object used to contact Google.

=head1 CONFIGURATION FUNCTIONS

=head2 config( option => $value, )

Use this to set any of these options:

=over

=item api_key

The API key is not required. But you're invited to use one as a secondary
means of identifying yourself.

See: L<http://code.google.com/apis/ajaxfeeds/signup.html>

=item referer

The value for the referer header in HTTP requests sent to the Google
translation service.

Google requests that you provide a valid referer string as the primary means
of identifying yourself. You will probably use the URL you specified when
you got your API key, or perhaps the URL where your application exists.

=item google_uri

The uri to use when contacting Google.

The default value is:
http://ajax.googleapis.com/ajax/services/language/translate?

For details see:
http://code.google.com/apis/ajaxlanguage/documentation/#fonje

=item agent

The User-Agent string to use when contacting Google.

The default value is:
Lingua::Translate::Google/0.07

=item chunk_size

The size to break chunks into before handing them off to Google.
The default value is 1000 bytes.

=item retries

The number of times to retry contacting Google if the first attempt fails.
The default value is 2.

=item src

The source language. Same as constructor src option.

=item dest

The destination language. Same as constructor dest option.

=back

=head1 TODO

The chunk_size attribute is a hold-over from the Babelfish algorithm.
It is TBD as to what chunk size ought to be set for Google.

There might be a better way to get the available language pairs.

=head1 SEE ALSO

L<Lingua::Translate>, L<Lingua::Translate::Babelfish>,
L<LWP::UserAgent>, L<Unicode::MapUTF8>

=head1 LICENSE

This is free software, and can be used/modified under the same terms as
Perl itself.

=head1 ACKNOWLEDGEMENTS

Sam Vilain (L<http://search.cpan.org/~samv/>) wrote
Lingua::Translate::Babelfish which served as the basis for this module.

Jerrad Pierce (L<http://search.cpan.org/~jpierce/>) for bug reporting.

=head1 AUTHOR

Dylan Doxey, <dylan.doxey@gmail.com>

=cut
