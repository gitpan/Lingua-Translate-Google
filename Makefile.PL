use ExtUtils::MakeMaker;

WriteMakefile
    (
ABSTRACT => 'Lingua::Translate::Google - a Google backend for Lingua::Translate',
AUTHOR => 'Dylan Doxey, <dylan.doxey@gmail.com>',
NAME => "Lingua::Translate::Google",
PREREQ_PM =>
  { 'Carp'                  => 0,
    'HTTP::Request::Common' => 0,
    'I18N::LangTags'        => 0.27,
    'Lingua::Translate'     => 0,
    'LWP::UserAgent'        => 1.73,
    'Readonly'              => 0,
    'Test::More'            => 0,
    'Unicode::MapUTF8'      => 1.09, },
VERSION_FROM => "lib/Lingua/Translate/Google.pm",
    )

