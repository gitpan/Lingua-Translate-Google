use ExtUtils::MakeMaker;

WriteMakefile
    (
ABSTRACT => 'Lingua::Translate::Google - a Google backend for Lingua::Translate',
AUTHOR => 'Dylan Doxey, <dylan@cpan.org>',
NAME => "Lingua::Translate::Google",
PREREQ_PM =>
  { HTML::TokeParser => 2.19,
    I18N::LangTags   => 0.27,
    LWP::UserAgent   => 1.73,
    Pod::Constants   => 0.15,
    Unicode::MapUTF8 => 1.09, },
VERSION_FROM => "lib/Lingua/Translate/Google.pm",
    )

