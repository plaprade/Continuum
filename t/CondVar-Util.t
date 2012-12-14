use strict;
use warnings;

use Test::More; 
use Data::Dumper;

BEGIN { use_ok( 'CondVar::Util', qw( :all ) ) };

ok_cv(
    cv(2),
    [ 2 ],
    'cv creates a condvar when passed a scalar'
);

ok_cv(
    cv( 1, 2, 3 ),
    [ 1, 2, 3 ],
    'cv creates a condvar that returns a list of all its arguments'
);

ok_cv(
    cv( cv(2) ),
    [ 2 ],
    'cv returns its argument if its a condvar'
);

ok_cv(
    cv_eval( sub{ sub{ ( 1, 2, 3 ) } } ),
    [ 1, 2, 3 ],
    'cv_eval recursively evalutes functions passed as argument'
);

ok_cv(
    cv_timer( 0.1 => sub{2} ),
    [ 2 ],
    'cv_timer evalutes its callback and returns it'
);

ok_cv(
    cv_and(
        cv(1),
        cv_timer( 0.2 => sub{2} ),
        cv(3),
        cv_timer( 0.1 => sub{4} ),
        cv(5),
    ),
    [ 1, 2, 3, 4, 5 ],
    'cv_and returns an ordered list of all the condvar values'
);

ok_cv(
    cv_or(
        cv_timer( 0.4 => sub{1} ),
        cv_timer( 0.3 => sub{2} ),
        cv_timer( 0.2 => sub{3} ),
        cv_timer( 0.1 => sub{4} ),
    ),
    [ 4 ],
    'cv_or returns the value of the first condvar to complete'
);

ok_cv(
    (cv_chain {
        cv_timer( 0.1 => sub{ 1 } );
    } with {
        cv( @_, 2 );
    } with {
        my @args = @_;
        cv_timer( 0.1 => sub{ ( @args, 3 ) } );
    }),
    [ 1, 2, 3 ],
    'cv_chain chains the result of a condvar with the next function'
);


ok_cv(
    (cv_chain {
        cv_timer( 0.1 => sub{ 3 } );
    } with {
        return ( shift, 2, 1 );
    } with {
        cv_timer( 0.1 => sub{ ( 1, 2, 3 ) } );
    }),
    [ 3, 2, 1 ],
    'cv_chain returns from the chain if no condvar is seen'
);

ok_cv(
    ( cv_wrap { ( @_, 3 ) } cv( 1, 2 ) ),
    [ 1, 2, 3 ],
    'cv_wrap maps the result of a condvar into another one'
);

ok_cv(
    ( cv_map {
        my $elem = $_;
        cv_timer( $elem => sub{ $elem } );
    } ( 0.3, 0.2, 0.1 ) ),
    [ 0.3, 0.2, 0.1 ],
    'cv_map maps elements to condvars and cv_and them together'
);

ok_cv(
    ( cv_grep {
        my $elem = $_;
        cv_timer( $elem => sub{ int( $elem*10 ) % 2 } ); 
    } ( 0.4, 0.3, 0.2, 0.1 ) ),
    [ 0.3, 0.1 ],
    'cv_grep maps elements to condvars the return filters'
);

ok_cv(
    ( cv_grep {
        my $elem = $_;
        cv_timer( 0.1 => sub{ not defined $elem } ); 
    } ( 1, undef, 2, undef ) ),
    [ undef, undef ],
    'cv_grep must work with undef filters'
);

done_testing();

sub ok_cv {
    my ( $cv, $res, $name ) = @_;
    is_deeply( [ $cv->recv ], $res, $name );
}
