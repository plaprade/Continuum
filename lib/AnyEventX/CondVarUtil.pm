package AnyEventX::CondVarUtil;

use strict;
use warnings;

use AnyEvent;
use Scalar::Util qw( blessed );
require Exporter;

use version; our $VERSION = version->declare("v0.0.1"); 

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
    cv_build
    cv_result
) ] );
our @EXPORT_OK = @{ $EXPORT_TAGS{ all } }; 

=pod

=head1 NAME

AnyEventX::CondVarUtil - Continuation framework for AnyEvent condition variables

=cut

sub cv {
    return shift if is_condvar( @_ );
    my $cv = AnyEvent::condvar;
    $cv->send( @_ );
    $cv;
}

sub cv_and {
    my @cvs = @_;

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

sub cv_or {
    my @cvs = @_;

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
            is_result( $x ) ?
                $cv->send(( $x->value )) :
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

sub cv_wrap(&@) {
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
    cv_and( map { $fn->() } @list );
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

sub cv_build(&@) {
    my $cv = AnyEvent->condvar;
    my $fp = undef;
    foreach my $f ( reverse @_ ) {
        my $next = $fp; $fp = sub {
            if( defined $next ){
                my $res = $f->( $next, @_ );
                $cv->send(( $res->value ))
                    if is_result( $res );
            } else {
                my @res = $f->( @_ );
                $cv->send( is_result( @res ) ? 
                    @res[0]->value : @res );
            }
        };
    }
    $fp->();
    $cv;
}

sub cv_result {
    AnyEventX::CondVarUtil::Return->new( @_ );
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

sub is_condvar {
    my $val = shift;
    defined $val && ref( $val ) eq 'AnyEvent::CondVar';
}

sub is_result {
    my $val = shift;
    blessed( $val ) && $val->isa( 'AnyEventX::CondVarUtil::Return' );
}

package AnyEventX::CondVarUtil::Return;

sub new {
    my $class = shift;
    my $self = {
        _value => [ @_ ],
    };
    bless $self, $class;
}

sub value {
    my $self = shift;
    wantarray ? 
        @{ $self->{ _value } } : 
        $self->{ _value }->[0];
}

1;
