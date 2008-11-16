#!/usr/bin/perl -w

# Copyright (c) 2008, Dylan Doxey.  All rights reserved. This program
# is free software; you may use it under the same terms as Perl
# itself.
#
# Revised copy of Lingua::Translate::Babe lfish by Sam Vilain
# <enki@snowcra.sh>
#
package Lingua::Translate::Google;

our $VERSION = '0.01';

use strict;
use Carp;
use LWP::UserAgent;
use HTTP::Request::Common qw(GET);
use Unicode::MapUTF8 qw(to_utf8);
use I18N::LangTags qw(is_language_tag);

# package globals:
# %config is default values to use for new objects
# %valid_langs is a hash from a google URI to a hash of 'XX_YY'
# language pair tags to true values.
use vars qw($VERSION %config %valid_langs);

sub new {
    my ( $class, %options ) = (@_);

    my $self = bless {%config}, $class;

    croak 'Must supply source and destination language'
      unless ( defined $options{src} and defined $options{dest} );

    is_language_tag( $self->{src} = delete $options{src} )
      or croak "$self->{src} is not a valid RFC3066 language tag";

    is_language_tag( $self->{dest} = delete $options{dest} )
      or croak "$self->{dest} is not a valid RFC3066 language tag";

    $self->config(%options);

    return $self;
}

sub translate {
    my $self = shift;
    UNIVERSAL::isa( $self, __PACKAGE__ )
      or croak __PACKAGE__ . '::translate() called as function';

    my $text = shift;

    # TODO Determine if chunkification is necessary for Google.
    # chunkify the text.  Knowing how to do this properly is really
    # the job of an expert system, so I'll keep it simple and break on
    # English sentence terminators (which might be completely the
    # wrong thing to do for other languages.  Oh well)
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

    # the translated text
    my ( @translated, $error );

    CHUNK:
    for my $chunk (@chunks) {

        my $service_uri = $self->{google_uri};

        # for http://ajax.googleapis.com/ajax/services/language/translate?
        my %params = (
            v        => '1.0',
            key      => $self->{api_key},
            q        => $chunk,
            langpair => $self->{src} . '%7C' . $self->{dest},
        );

        # for http://www.google.com/uds/Gtranslate?
        ## my %params = (
        ##     v        => '1.0',
        ##     key      => $self->{api_key},
        ##     q        => $chunk,
        ##     langpair => $self->{src} . '%7C' . $self->{dest},
        ##     context  => 22
        ##     callback => 'google.language.callbacks.id101',
        ## );

        # for http://translate.google.com/translate_a/t?
        if ( !$self->{api_key} ) {

            %params = (
                text   => $chunk,
                sl     => $self->{src},
                tl     => $self->{dest},
                client => 't',
            );
            $service_uri = $self->{google_fallback_uri};

            # Note, for the fallback service might return windows-1255
            # encoding, unless User-Agent suggests a Linux client.
        }

        my $query = join '&', map { "$_=$params{$_}" } keys %params;

        # make a new request object
        my $req = GET "$service_uri$query";

        $req->header( 'Referer',        $self->{referer} );
        $req->header( 'Accept-Charset', 'UTF-8' );

      RETRY:

        # try several times to reach google
        for my $attempt ( 1 .. $self->{retries} + 1 ) {

            # go go gadget LWP::UserAgent
            my $res = $self->agent->request($req);

            if ( $res->is_success ) {

                my $output = $self->_extract_text(
                    $res->content(),
                    $res->header('Content-Type')
                );

                # google errors
                # FIXME Get the correct message text
                next RETRY
                  if $output =~ m/ We \s+ were \s+ unable \s+
                    to \s+ process \s+ your \s+ request \s+
                    within \s+ the \s+ available \s+ time/msx;

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
    UNIVERSAL::isa( $self, __PACKAGE__ )
      or croak __PACKAGE__ . '::available() called as function';

    # return a cached result
    if ( my $ok_langs = $valid_langs{ $self->{google_uri} } ) {
        return keys %$ok_langs;
    }

    # create a new request
    my $req = GET $self->{google_uri};

    # go get it
    my $res = $self->agent->request($req);
    die 'Google fetch failed; ' . $res->status_line
      unless $res->is_success;

    # extract out the languages
    my $page = $res->content;

    my @source_langs;
    if ( $page =~ m{<select \s+ name=sl [^>]+ > ( .*? ) </select>}msx ) {
        my $options = $1;
        while ( $options =~ m{<option \s+ value="([^"]+)">}msx ) {
            my $lang = $1;
            push @source_langs, $lang;
        }
    }
    my @list;
    if ( $page =~ m{<select \s+ name=tl [^>]+ > ( .*? ) </select>}msx ) {
        my $options = $1;
        while ( $options =~ m{<option \s+ value="([^"]+)">}msx ) {
            my $dest = $1;

            # Presumably any source language is paired with any to language.
            for my $src (@source_langs) {

                my $pair = "$src\_$dest";

                unless ( is_language_tag($src) and is_language_tag($dest) ) {
                    warn "Don't recognise '$pair' as a valid language pair";
                    next;
                }
                push @list, $pair;
            }
        }
    }

    # save the result
    $valid_langs{ $self->{google_uri} } = map { $_ => 1 } @list;

    return @list;
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

# Used to set configuration options.
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
        elsif ( $option eq 'google_fallback_uri' ) {

            $self->{google_fallback_uri} = $value;
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
        elsif ( $option eq 'retries' ) {

            $self->{retries} = $value;
        }
        else {

            croak "Unknown configuration option $option";
        }
    }
}

# extract configuration options from the POD
use Pod::Constants
  'NAME' => sub { ($VERSION) = (m/(\d+\.\d+)/); },
  'CONFIGURATION FUNCTIONS' => sub {
    Pod::Constants::add_hook(
        '*item' => sub {
            my ($varname) = m/(\w+)/;

            my ($default) = m/The default value is\s+"(.*?)"/s;
            config( $varname => $default );
        }
    );
    Pod::Constants::add_hook(
        '*back' => sub {

            # an ugly hack?
            $config{agent} .= $VERSION;

            Pod::Constants::delete_hook('*item');
            Pod::Constants::delete_hook('*back');
        }
    );
  };

1;

# CAUTION: Some constants have their default values extracted from the
# POD. See the use Pod::Constants section.

__END__

=head1 NAME

Lingua::Translate::Google 0.01 - Translation back-end for Google's beta translation service.

=head1 SYNOPSIS

 use Lingua::Translate;

 Lingua::Translate::config
     (
       backend => 'Google',
       api_key => 'YoUrApIkEy',
       referer => 'http://your.domain.tld/yourdir/',
       ua      => LWP::UserAgent->new(),
     );

 my $xl8r = Lingua::Translate->new(src => 'de', dest => 'en');

 # prints 'My hovercraft is full of eels'
 print $xl8r->translate('Mein Luftkissenfahrzeug ist voller Aale');

=head1 DESCRIPTION

Lingua::Translate::Google is a translation back-end for Lingua::Translate that contacts Google (http://ajax.googleapis.com/ajax/services/language/translate/) to do the real work.

It is normally invoked by Lingua::Translate; there should be no need to call it directly.  If you do call it directly, you will lose the ability to easily switch your programs over to alternate back-ends that are later produced.

If you omit the API key config option, then this module uses the fallback service at translate.google.com/ which works fine without it.

To use the Google APIs, Google asks that you obtain an API key, and that you always include a valid and accurate referer URL. If you supply an API key, then this module uses the AJAX API which Google provides specifically for third party application development.

One way or another, by using Google services (either directly or via this module) you are agreeing by their terms of service.

=over

=item Please read: 

http://www.google.com/accounts/TOS

=item To obtain your own API key: 

http://code.google.com/apis/ajaxfeeds/signup.html

=back

=head1 CONSTRUCTOR

=head2 new(src => $lang, dest => lang)

=over

Creates a new translation handle. 
Determines whether the requested language pair is available and will croak if not.

=back

=head3 paramters

=over

=over

=head2 src

Source language, in RFC-3066 form.  See L<I18N::LangTags> for a discussion of RFC-3066 language tags.

=back

=over

=head2 dest

Destination Language

=back

Other options that may be passed to the config() function (see below) may also be passed as arguments to this constructor.

=back

=head1 METHODS

The following methods may be called on Lingua::Translate::Google objects.

=head2 available() : @list

=over

Returns a list of available language pairs, in the form of 'XX_YY', where XX is the source language and YY is the destination. 
If you want the english name of a language tag, call I18N::LangTags::List::name() on it.  See L<I18N::LangTags::List>.

This method contacts Google (http://translate.google.com/translate_a/t?) to calculate available language pairs. 
The data about available language pairs is cached in memory.

=back

=head2 translate($text) : $translated

=over

Translates the given text, or die's on any kind of error. 

It is assumed that the $text coming in is UTF-8 encoded, and that Google will be returning UTF-8 encoded text. In the case that Google returns some other encoding, then an attempt to convert the result to UTF-8 is made with Unicode::MapUTF8::to_utf8. Observation has indicated that the fallback service (at /translate_a/t) is inclined to return windows-1255 encoded text, despite the value of the 'Accept-Charset' header sent in the request. However, a non-windows user agent string seems to remedy this. 

Also, the primary service (at googleapis.com) returns JSON which assumes the client is JavaScript running with an HTML document. This being the case strings are double encoded. First special characters are converted to HTML entities, and then the ampersands are converted to unicode escape sequences. For example, the string "Harold's" is encoded as "Harold\u0027#39;s". The translate function attempts to return plain old UTF-8 encoded strings without any entities or escape sequences.

=back

=head2 agent() : LWP::UserAgent

=over

Returns the LWP::UserAgent object used to contact Google.

=back

=head1 CONFIGURATION FUNCTIONS

=head2 config( option => $value, )

This function sets defaults for use when constructing objects. Options include:

=item google_uri

The uri to use when contacting Google.

The default value is

"http://ajax.googleapis.com/ajax/services/language/translate?"
     v=1.0
    &q=hello%20world
    &langpair=en%7Cit
    &key=yourapikey

For details see:
http://code.google.com/apis/ajaxlanguage/documentation/#fonje

Another possibility is:

"http://www.google.com/uds/Gtranslate?"
     v=1.0
    &q=hello%20world
    &langpair=en%7Czh-TW
    &callback=google.language.callbacks.id101
    &context=22
    &key=notsupplied
    &key=yourapikey

=item google_fallback_uri

The URI used when contacting Google, and no api_key is provided.

The default value is

"http://translate.google.com/translate_a/t?"
     client=t
    &text=hello%20world
    &sl=en
    &tl=zh-Tw

Note, Google states clearly that they want you to obtain and use an API key, and also include a valid and accurate referer URL.

=item agent

The User-Agent string to use when contacting Google.

The default value is "Lingua::Translate::Google/", plus the version number of the package.

=item chunk_size

The size to break chunks into before handing them off to Google. The default value is "1000" (bytes).

=item retries

The number of times to retry contacting Google if the first attempt fails. The default value is "2".

=head1 BUGS/TODO

The chunk_size attribute is a hold-over from the Babelfish algorithm. It is TBD as to what chunk size ought to be set for Google.

=head1 SEE ALSO

L<Lingua::Translate>, L<Lingua::Translate::Babelfish>, L<LWP::UserAgent>, L<Unicode::MapUTF8>

=head1 ACKNOWLEDGEMENTS

This is a rewritten copy of Lingua::Translate::Babelfish by Sam Vilain <enki@snowcra.sh>.

=head1 AUTHOR

Dylan Doxey, <dylan.doxey@gmail.com>

=cut
