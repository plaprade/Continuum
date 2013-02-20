package Continuum::Util;

use strict;
use warnings;

use Scalar::Util qw( blessed );

use base 'Exporter';

our @EXPORT = (qw(
    is_portal
));

sub is_portal {
    my $val = shift;
    blessed( $val ) && (
        $val->isa( 'Continuum::Portal' ) ||
        $val->isa( 'AnyEvent::CondVar' )
    );
}

1;
