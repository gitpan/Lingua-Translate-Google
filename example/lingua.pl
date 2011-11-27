#!/usr/bin/perl -w

use strict;
use warnings;
use Lingua::Translate::Google;

my ( $key, $src, $dest, $q );

ARG:
while ( my $arg = shift @ARGV ) {

    if ( $arg eq '--key' ) {

        if ( @ARGV && $ARGV[0] !~ m{\A -- }xms ) {

            $key = shift @ARGV;
        }
        next ARG;
    }
    if ( $arg eq '--src' ) {

        if ( @ARGV && $ARGV[0] !~ m{\A -- }xms ) {

            $src = shift @ARGV;
        }
        next ARG;
    }
    if ( $arg eq '--dest' ) {

        if ( @ARGV && $ARGV[0] !~ m{\A -- }xms ) {

            $dest = shift @ARGV;
        }
        next ARG;
    }
    if ( $arg eq '--q' ) {

        $q = "";

        while ( @ARGV && $ARGV[0] !~ m{\A -- }xms ) {

            $q .= shift @ARGV;
            $q .= ' ';
        }

        chomp $q;

        next ARG;
    }
}

die "q, dest, src and key are all required"
    if !$q || !$src || !$dest || !$key;

my $t = Lingua::Translate::Google->new(
    key  => $key,
    src  => $src,
    dest => $dest,
);

my %r = $t->translate( $q );

print Dumper( \%r );

__END__
