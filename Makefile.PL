use ExtUtils::MakeMaker;

WriteMakefile
    (
ABSTRACT => 'Lingua::Translate::Google - a Google backend for Lingua::Translate',
AUTHOR => 'Dylan Doxey, <dylan.doxey@gmail.com>',
NAME => "Lingua::Translate::Google",
PREREQ_PM =>
  { 'HTTP::Request::Common' => 0,
    'I18N::LangTags'        => 0.27,
    'LWP::UserAgent'        => 1.73,
    'Readonly'              => 0, 
    'Unicode::MapUTF8'      => 1.09, },
VERSION_FROM => "lib/Lingua/Translate/Google.pm",
    )

