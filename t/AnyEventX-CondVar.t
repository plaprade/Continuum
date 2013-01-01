use strict;
use warnings;

use AnyEvent;
use Test::More; 
use Data::Dumper;

BEGIN { use_ok( 'AnyEventX::CondVar' ) };
BEGIN { use_ok( 'AnyEventX::CondVar::Util', qw( :all ) ) };

run_all( 0, 0 );
run_all( 0, 1 );
run_all( 1, 0 );
run_all( 1, 1 );
run_all( 2, 2 );
run_all( 0, -1 );
run_all( -1, 0 );
run_all( 1, -2 );
run_all( -2, 1 );

sub run_all {
    my ( $a, $b ) = @_;

    subtest "with_assign with $a and $b" => sub {

        plan tests => $b == 0 ? 26 : 28;

        foreach my $op ( 
            qw( + - * / % ** << >> x . ), 
            qw( < <= > >= == != ),
            qw( <=> cmp ),
            qw( lt le gt ge eq ne ),
            qw( & | ^ ),
            qw( ~~ ),
        ){
            next if $op ~~ [qw( / % )] && $b == 0;
            is( 
                eval( "cv($a) $op cv($b)" )->recv, 
                eval( "$a $op $b" ),
                "Evaluating operator $op"
            ); 
        }
    };

    subtest "unary with $a" => sub {

        plan tests => $a <= 0 ? 9 : 11;

        foreach my $op ( 
            qw( atan2 cos sin exp abs log sqrt int ),
            qw( ! not ~ ),
        ){
            next if $op ~~ [qw( log sqrt )] && $a <= 0;
            is( 
                eval( "($op cv($a))->recv" ), 
                eval( "$op $a" ), 
                "Evaluating operator $op"
            ); 
        }

    };

}

### LIST OPERATORS ###

is_deeply(
    [ cv(2)->cons( cv(3) )->cons( cv(4) )->recv ],
    [ 2, 3, 4 ],
    'Cons',
);

is_deeply(
    [ cv( 1, 2, 3 )->push( cv(4) )->recv ],
    [ 1, 2, 3, 4 ],
    'Push',
);

is_deeply(
    [ cv( 1, 2, 3, 4 )->pop->recv ],
    [ 1, 2, 3 ],
    'Pop',
);

is_deeply(
    [ cv( 2, 3, 4 )->unshift(1)->recv ],
    [ 1, 2, 3, 4 ],
    'Unshift',
);

is_deeply(
    [ cv( 1, 2, 3, 4 )->shift->recv ],
    [ 2, 3, 4 ],
    'Shift',
);

is_deeply(
    [ cv( a => 1, b => 2, c => 3 )->hget( 'c' )->recv ],
    [ 3 ],
    'Hash Get'
);

is_deeply(
    [ cv( a => 1, b => 2, c => 3 )->hget( 'c', 'a' )->recv ],
    [ 3, 1 ],
    'Hash Get Many'
);

is_deeply(
    [ cv( a => 1, b => 2, c => 3 )
        ->hset( b => 4 )
        ->hget( 'b' )->recv ],
    [ 4 ],
    'Hash Set'
);

is_deeply(
    [ cv( 1, 2, 3, 4 )->aget( 2 )->recv ],
    [ 3 ],
    'Array Get'
);

is_deeply(
    [ cv( 1, 2, 3, 4 )->aget( 2, 1 )->recv ],
    [ 3, 2 ],
    'Array Get Many'
);

is_deeply(
    [ cv( 1, 2, 3, 4 ) ->aset( 2 => 5 )->recv ],
    [ 1, 2, 5, 4 ],
    'Array Set'
);

is_deeply(
    [ cv( 4, 2, 3 )->first->recv ],
    [ 4 ],
    'First'
);

is_deeply(
    [ cv( 4, 2, 3 )->last->recv ],
    [ 3 ],
    'Last'
);

is_deeply(
    [ cv( 1, 4, 2, 1, 3, 2, 1 )->unique( sub{ $_ } )->sort->recv ],
    [ 1, 2, 3, 4 ],
    'Unique & Sort',
);

is_deeply(
    [ cv( 1, 2, 3, 4 )->map( sub { $_ * 2 } )->recv ],
    [ 2, 4, 6, 8 ],
    'Map'
);

is_deeply(
    [ cv( 1, 2, 3, 4 )->grep( sub { $_ % 2 } )->recv ],
    [ 1, 3 ],
    'Grep'
);

is_deeply(
    [ cv( 1, 2, 3 )->sum->recv ],
    [ 6 ],
    'Sum'
);

is_deeply(
    [ cv( 2, 3, 4 )->mul->recv ],
    [ 24 ],
    'Mul'
);

is_deeply(
    [ cv( [ 1, 2, 3 ], 4, { 5 => 6 } )->deref->recv ],
    [ 1, 2, 3, 4, 5, 6 ],
    'Deref',
);

### BOOLEAN OPERATORS ###

is_deeply(
    [ ( cv(2) == 2 )->and( sub { 3 } )->recv ],
    [ 3 ],
    'And true',
);

is_deeply(
    [ ( cv(2) < 2 )->and( sub { 3 } )->recv ],
    [ '' ],
    'And false',
);

is_deeply(
    [ ( cv(2) == 2 )->or( sub { 3 } )->recv ],
    [ 1 ],
    'Or true',
);

is_deeply(
    [ ( cv(2) < 2 )->or( sub { 3 } )->recv ],
    [ 3 ],
    'Or false',
);

### MISC OPERATORS ###

is_deeply(
    [ cv(1)->wait(0.1)->any( cv(2) )->recv ],
    [ 2 ],
    'Any 1'
);

is_deeply(
    [ cv(1)->any( cv(2)->wait(0.1) )->recv ],
    [ 1 ],
    'Any 2'
);

is_deeply(
    [ cv(2)->cons( cv(3) )->wait( 0.1 )->cons( cv(4) )->recv ],
    [ 2, 3, 4 ],
    'Wait',
);

### UTIL OPERATIONS ###

is_deeply(
    [ cv_build->recv ],
    [],
    'cv_build empty'
);

is_deeply(
    [ ( cv_build { 2 } )->recv ],
    [ 2 ],
    'cv_build single scalar'
);

is_deeply(
    [ ( cv_build { cv_result(2) } )->recv ],
    [ 2 ],
    'cv_build single result'
);

is_deeply(
    [( 
        cv_build { 
            $_->(1); 
        } cv_then {
            $_->( @_, 2 );
        } cv_then {
            ( @_, 3 );
        }
    )->recv],
    [ 1, 2, 3 ],
    'cv_build chain'
);

is_deeply(
    [( 
        cv_build { 
            $_->(1); 
        } cv_then {
            cv_result( @_, 4 );
        } cv_then {
            ( @_, 3 );
        }
    )->recv],
    [ 1, 4 ],
    'cv_build early return'
);

is_deeply(
    [( cv_build { anyevent_cv() } )->recv],
    [],
    'cv_build empty anyevent'
);

is_deeply(
    [( cv_build { anyevent_cv( 2 ) } )->recv],
    [ 2 ],
    'cv_build simple anyevent'
);

is_deeply(
    [( cv_build { anyevent_cv( 1, 2, 3 ) } )->recv],
    [ 1, 2, 3 ],
    'cv_build list anyevent'
);

is_deeply(
    [( 
        cv_build { 
            anyevent_cv( 1, 2, 3 ) 
        } cv_then {
            anyevent_cv( @_, 4, 5, 6 ) 
        } cv_then {
            ( @_, 7 );
        }
    )->recv],
    [ 1, 2, 3, 4, 5, 6, 7 ],
    'cv_build chain anyevent'
);

is_deeply(
    [( 
        cv_build { 
            anyevent_cv( 1, 2, 3 ) 
        } cv_then {
            cv_result( @_, 4, 5 );
        } cv_then {
            ( @_, 7 );
        }
    )->recv],
    [ 1, 2, 3, 4, 5 ],
    'cv_build chain anyevent early return'
);

is_deeply(
    [( 
        cv_build { 
            anyevent_cv( 1, 2, 3 ) 
        } cv_then {
            $_->( @_, 4, 5 );
        } cv_then {
            cv_result( @_, 6 );
        } cv_then {
            ( @_, 7 );
        }
    )->recv],
    [ 1, 2, 3, 4, 5, 6 ],
    'cv_build chain mix'
);

done_testing();

sub cv {
    my $cv = AnyEventX::CondVar->new();
    $cv->send( @_ );
    $cv;
}

sub anyevent_cv {
    my $cv = AnyEvent->condvar;
    $cv->send( @_ );
    $cv;
}
