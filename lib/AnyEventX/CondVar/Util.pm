package AnyEventX::CondVar::Util;

use strict;
use warnings;

use Scalar::Util qw( blessed );

require Exporter;

our @ISA = qw( Exporter );
our %EXPORT_TAGS = ( all => [ qw(
    cv_build
    cv_result
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
                and $cv->send( $x->value )
                and return;

            $cv->send( $x, @xs )
                unless defined $next;
        };
    }
    $fp->() if defined $fp;
    $cv;
}

sub cv_result {
    AnyEventX::Util::Result->new( @_ );
}

sub is_result {
    my $val = shift;
    blessed( $val ) && $val->isa( 'AnyEventX::CondVar::Result' );
}

sub is_cv {
    my $val = shift;
    blessed( $val ) && $val->isa( 'AnyEventX::CondVar' );
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
