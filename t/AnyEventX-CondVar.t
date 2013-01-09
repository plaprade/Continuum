use strict;
use warnings;

use AnyEvent;
use Test::More; 
use Data::Dumper;

BEGIN { use_ok( 'AnyEventX::CondVar' ) };
BEGIN { use_ok( 'AnyEventX::CondVar::Util', qw( :all ) ) };

test_num( 0, 0 );
test_num( 0, 1 );
test_num( 1, 0 );
test_num( 1, 1 );
test_num( 2, 2 );
test_num( 0, -1 );
test_num( -1, 0 );
test_num( 1, -2 );
test_num( -2, 1 );

test_str( '', '' );
test_str( '', 'a' );
test_str( 'a', '' );
test_str( 'a', 'a' );
test_str( 'aa', 'aa' );
test_str( 'a', 'b' );
test_str( 'ab', 'aa' );

sub test_num {
    my ( $a, $b ) = @_;

    subtest "with_assign with $a and $b" => sub {

        plan tests => $b == 0 ? 19 : 21;

        foreach my $op ( 
            qw( + - * / % ** << >> x . ), 
            qw( < <= > >= == != ),
            qw( <=> ),
            qw( & | ^ ),
            qw( ~~ ),
        ){
            next if $op ~~ [qw( / % )] && $b == 0;
            is( 
                eval( '(cv($a) ' . $op . ' cv($b))->recv' ), 
                eval( '$a ' . $op . ' $b' ),
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
                eval( '(' . $op . ' cv($a))->recv' ), 
                eval( $op . ' $a' ), 
                "Evaluating operator $op"
            ); 
        }

    };

}

sub test_str {
    my ( $a, $b ) = @_;

    subtest "String test with $a and $b" => sub {

        plan tests => 8;

        foreach my $op ( 
            qw( cmp ),
            qw( lt le gt ge eq ne ),
            qw( ~~ ),
        ){
            is( 
                eval( '(cv($a) ' . $op . ' cv($b))->recv' ), 
                eval( '$a ' . $op . ' $b' ),
                "Evaluating operator $op"
            ); 
        }
    };

}

### Concatenation - Append ###

is_deeply(
    [ cv(2)->cons( cv(3) )->cons( 4 )->recv ],
    [ 2, 3, 4 ],
    'Cons',
);

is_deeply(
    [ cv(2)->cons( cv(3) )->cons( undef )->recv ],
    [ 2, 3, undef ],
    'Cons undef',
);

is_deeply(
    [ cv(2)->append( cv(3), 4, cv(5) )->recv ],
    [ 2, 3, 4, 5 ],
    'Append',
);

is_deeply(
    [ cv(2)->append( cv(3), 4, cv(5), undef )->recv ],
    [ 2, 3, 4, 5 ],
    'Append undef',
);

is_deeply(
    [ cv( undef )->append( undef )->recv ],
    [ undef ],
    'Append double undef',
);

is_deeply(
    [ cv(2)->append( cv(3), undef, 4, cv(5), undef )->recv ],
    [ 2, 3, undef, 4, 5 ],
    'Append undef middle',
);

### Continuation - Data dependencies ### 

is_deeply(
    [ cv(2,3)->then( sub { ( @_, cv(4), 5, cv(6) ) } )->recv ],
    [ 2, 3, 4, 5, 6 ],
    'Then',
);

### List operations ### 

is_deeply(
    [ cv( 1, 2, 3 )->push( cv(4) )->recv ],
    [ 1, 2, 3, 4 ],
    'Push',
);

is_deeply(
    [ cv( 1, 2, 3 )->push( cv(4), 5, cv(6) )->recv ],
    [ 1, 2, 3, 4, 5, 6 ],
    'Push list',
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
    [ cv( 4, 5, 6 )->unshift( cv(1), cv(2), 3 )->recv ],
    [ 1, 2, 3, 4, 5, 6 ],
    'Unshift list',
);

is_deeply(
    [ cv( 1, 2, 3, 4 )->shift->recv ],
    [ 2, 3, 4 ],
    'Shift',
);

### Get/Set List elements ###

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

### Get/Set Hash elements ###

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

### Advanced List operations ###

is_deeply(
    [ cv( 1, 2, 3, 4 )->map( sub { $_ * 2 } )->recv ],
    [ 2, 4, 6, 8 ],
    'Map'
);

is_deeply(
    [ cv( 1, 2, 3 )->map( sub{ cv( $_ * 2 ) } )->recv ],
    [ 2, 4, 6 ],
    'Flatmap (with map)'
);

is_deeply(
    [ cv( 1, 2, 3, 4 )->grep( sub { $_ % 2 } )->recv ],
    [ 1, 3 ],
    'Grep'
);

is_deeply(
    [ cv( 1, 2, 3, 4 )->grep( sub{ cv( $_ % 2 ) } )->recv ],
    [ 1, 3 ],
    'Flatgrep (with grep)'
);

is_deeply(
    [ cv( 1, 4, 2, 1, 3, 2, 1 )->unique( sub{ $_ } )->sort->recv ],
    [ 1, 2, 3, 4 ],
    'Unique & Sort',
);

is_deeply(
    [ cv( [1,3], [2,2], [3,1] )->sort( 
        sub { $a->[1] <=> $b->[1] } )->recv ],
    [ [3,1], [2,2], [1,3] ],
    'Sort',
);

is_deeply(
    [ cv( 1, 2, 3, 4 )
        ->reduce( sub { $a + $b }, 2, 3 )->recv ],
    [ 15 ],
    'Reduce'
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

### Boolean operations ###

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

### Stash operations ###

is_deeply(
    [
        cv( 1, 2, 3 )
            ->map( sub { $_ * 2 } )
            ->push_stash
            ->map( sub { $_ / 2 } )
            ->pop_stash
            ->recv
    ],
    [ 2, 4, 6 ],
    'Stash'
);

is_deeply(
    [
        cv( 1, 2, 3 )
            ->map( sub { $_ * 2 } )
            ->push_stash
            ->map( sub { $_ * 2 } )
            ->push_stash
            ->map( sub { $_ / 2 } )
            ->pop_stash
            ->recv
    ],
    [ 4, 8, 12 ],
    'Stash multi level'
);

is_deeply(
    [
        cv( 1, 2, 3 )
            ->map( sub { $_ * 2 } )
            ->push_stash
            ->map( sub { $_ * 2 } )
            ->push_stash
            ->map( sub { $_ / 2 } )
            ->pop_stash
            ->pop_stash
            ->recv
    ],
    [ 2, 4, 6 ],
    'Stash multi level 2'
);

### MISC Operators ###

is_deeply(
    [ cv( [ 1, 2, 3 ], 4, { 5 => 6 } )->deref->recv ],
    [ 1, 2, 3, 4, 5, 6 ],
    'Deref',
);

is_deeply(
    [ cv(1, 2)->result( 3, 4 )->cons( 5 )->recv ],
    [ 3, 4, 5 ],
    'Result scalar'
);

is_deeply(
    [ cv(1, 2)->result( cv( 3, 4 ) )->cons( 5 )->recv ],
    [ 3, 4, 5 ],
    'Result condvar'
);

is_deeply(
    [ cv_wait( 0.1 )->then( sub { cv( 3, 4, ) } )
        ->wait( 0.1 )->result( cv( 1, 2 ) )->recv ],
    [ 1, 2 ],
    'Result wait'
);

is_deeply(
    [ ( cv_build { 
        my $cv = AnyEvent->condvar; 
        my $w; $w = AnyEvent->timer( after => 0.05, cb => sub {
            undef $w;
            $cv->send( 1, 2 );
        });
        $cv;
    } )->result( 
        cv_build {
            my $cv = AnyEvent->condvar; 
            my $w; $w = AnyEvent->timer( after => 0.1, cb => sub {
                undef $w;
                $cv->send( 3, 4 );
            });
            $cv;
        }
    )->recv ],
    [ 3, 4 ],
    'Result build wait'
);

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

### Utility Operators ###

is_deeply(
    [ cv_wait(0.1)->cons( cv( 1, 2 ) )->recv ],
    [ 1, 2 ],
    'cv_wait'
);

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

sub anyevent_cv {
    my $cv = AnyEvent->condvar;
    $cv->send( @_ );
    $cv;
}
