package CondVar::Util;

use strict;
use warnings;

use AnyEvent;

require Exporter;

our @ISA = qw( Exporter );

our %EXPORT_TAGS = ( all => [ qw(
    cv
    cv_timer
    cv_then
    cv_with
    cv_and
    cv_or
    cv_chain
    cv_wrap
    cv_map
    cv_grep
) ] );

our @EXPORT_OK = @{ $EXPORT_TAGS{ all } }; 

our $VERSION = '0.01';

sub is_condvar {
    my $val = shift;
    defined $val && ref( $val ) eq 'AnyEvent::CondVar';
}

sub cv {
    return shift if is_condvar( @_ );
    my $cv = AnyEvent::condvar;
    $cv->send( @_ );
    $cv;
}

sub cv_and(&@) {
    my @cvs = map { $_->() } @_;

    my @result;
    my $cv = AnyEvent::condvar;
    
    $cv->begin( sub {
        $cv->send( map{ @$_ } @result ); 
    });

    for my $i ( 0..$#cvs ){
        $cv->begin;
        $cvs[$i]->cb( sub {
            $result[$i] = [ shift->recv ];
            $cv->end;
        });
    }

    $cv->end;
    $cv;
}

sub cv_or(&@) {
    my @cvs = map { $_->() } @_;

    my $done = 0;
    my $cv = AnyEvent::condvar;
    
    $_->cb( sub {
        return if $done;
        $done = 1;
        $cv->send( shift->recv );
    }) for ( @cvs );

    $cv;
}

sub cv_chain(&@) {
    my @fns = @_;

    my $cv = AnyEvent->condvar;

    my $fp = undef;
    foreach my $fn ( reverse @fns ) {
        my $next = $fp; $fp = sub {
            my ( $x, @xs ) = $fn->( @_ );
            is_condvar( $x ) ?
                $x->cb( sub {
                    defined $next ?
                        $next->( shift->recv ) :
                        $cv->send( shift->recv );
                }) :
                $cv->send( $x, @xs );
        };
    }
    $fp->();

    $cv;
}

sub cv_then(&@) { @_ }
sub cv_with(&@) { @_ }

sub cv_wrap(&$) {
    my ( $fn, $cv ) = @_;

    my $cv_wrap = AnyEvent::condvar;

    $cv->cb( sub {
        $cv_wrap->send( 
            $fn->( shift->recv ) );
    });

    $cv_wrap;
}

sub cv_map(&@) {
    my ( $fn, @list ) = @_;
    cv_and { map { $fn->() } @list };
}

sub cv_grep(&@) {
    my ( $fn, @list ) = @_;
    cv_chain {
        cv_map {
            my $elem = $_;
            cv_wrap { [ shift, $elem ] } $fn->();
        } @list;
    } cv_with {
        map { $_->[1] } grep { $_->[0] } @_;
    };
}

sub cv_timer {
    my ( $after, $cb ) = @_;
    my $cv = AnyEvent::condvar;
    my $w; $w = AnyEvent->timer(
        after => $after,
        cb => sub {
            $cv->send( defined $cb ? $cb->() : '' );
            undef $w;
        },
    );
    $cv;
}

1;
