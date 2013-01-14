package AnyEventX::CondVar::Util;

use strict;
use warnings;

use Scalar::Util qw( blessed );

require Exporter;

our @ISA = qw( Exporter );
our %EXPORT_TAGS = ( all => [ qw(
    cv
    cv_build
    cv_then
    cv_result
    cv_wait
    is_cv
)]);
our @EXPORT_OK = @{ $EXPORT_TAGS{ all } }; 

sub cv_build(;&@) {
    my $cv = AnyEventX::CondVar->new();
    my $fp = undef;
    foreach my $f ( reverse @_ ) {
        my $next = $fp; $fp = sub {
            local $_ = $next;
            my ( $x, @xs ) = $f->( @_ );

            is_result( $x ) 
                and do {
                    $cv->send( $x->value );
                    return;
                };

            ( is_anyevent_cv( $x ) || is_cv( $x ) ) && do {
                $x->cb( sub {
                    defined $next ?
                        $next->( shift->recv ) :
                        $cv->send( shift->recv );
                });
                return;
            };

            $cv->send( $x, @xs )
                unless defined $next;
        };
    }
    defined $fp ?
        $fp->() :
        $cv->send();
    $cv;
}

sub cv_then(&@) { @_ }

sub cv {
    return $_[0] if is_cv( $_[0] );
    my $cv = AnyEventX::CondVar->new();
    is_anyevent_cv( $_[0] ) ?
        $_[0]->cb( sub {
            $cv->send( shift->recv );
        }) : 
        $cv->send( @_ );
    $cv;
}

sub cv_result {
    AnyEventX::CondVar::Result->new( @_ );
}

sub cv_wait {
    my $time = shift;
    my $cv = AnyEventX::CondVar->new();
    my $w; $w = AnyEvent->timer( after => $time, cb => sub {
        undef $w;    
        $cv->send();
    });
    $cv;
}

sub is_result {
    my $val = shift;
    blessed( $val ) && $val->isa( 'AnyEventX::CondVar::Result' );
}

sub is_cv {
    my $val = shift;
    blessed( $val ) && $val->isa( 'AnyEventX::CondVar' );
}

sub is_anyevent_cv {
    my $val = shift;
    blessed( $val ) && $val->isa( 'AnyEvent::CondVar' );
}

package AnyEventX::CondVar::Result;

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
