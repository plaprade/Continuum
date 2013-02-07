use strict;
use warnings;

use AnyEvent;
use Test::More; 
use Data::Dumper;

BEGIN { use_ok( 'Continuum' ) };
use Continuum;

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

### Merge - Parallel execution flows ###

is_deeply(
    [ cv(2)->merge(3)->recv ],
    [ 2, 3 ],
    'Merge scalar',
);

is_deeply(
    [ cv(2)->merge(anyevent_cv(4))->recv ],
    [ 2, 4 ],
    'Merge condition variable',
);

is_deeply(
    [ cv(2)->merge(cv(5))->recv ],
    [ 2, 5 ],
    'Merge portal',
);

is_deeply(
    [ cv(2)->merge( cv(3), 4, cv(5), anyevent_cv(6) )->recv ],
    [ 2, 3, 4, 5, 6 ],
    'Merge mix',
);

is_deeply(
    [ cv(2)->merge( cv(3), 4, anyevent_cv(5), undef )->recv ],
    [ 2, 3, 4, 5, undef ],
    'Merge mix undef',
);

is_deeply(
    [ cv( undef )->merge( undef )->recv ],
    [ undef, undef ],
    'Merge double undef',
);

is_deeply(
    [ cv(2)->merge( cv(3), undef, 4, cv(5), undef )->recv ],
    [ 2, 3, undef, 4, 5, undef ],
    'Merge undef middle',
);


is_deeply(
    [ cv(2)->merge( cv(3), 4, '', anyevent_cv(5) )
        ->merge( anyevent_cv(6) )->merge( 7, 8 )->recv ],
    [ 2, 3, 4, '', 5, 6, 7, 8 ],
    'Merge multiple calls',
);

is_deeply(
    [ cv(1, 2)
        ->merge( cv(3), 4, 5, anyevent_cv(6, 7, 8), 9 )->recv ],
    [ 1, 2, 3, 4, 5, 6, 7, 8, 9 ],
    'Merge list'
);

is_deeply(
    [ cv(2)->merge( undef, cv(3) )->merge( undef )->merge()
        ->merge( undef, undef )->merge( anyevent_cv(4), undef )
        ->merge( 5, undef )->recv ],
    [ 2, undef, 3, undef, undef, undef, 4, undef, 5, undef ],
    'Merge complex undef',
);

is_deeply(
    [ cv(1, 2)
        ->wait( 0.1 )
        ->merge( 3 )
        ->merge( cv(4), cv(undef)->wait(0.02) ) 
        ->merge( cv(5)->wait(0.1), 6, '', undef, anyevent_cv(7) )
        ->wait( 0.1 )
        ->merge( cv(8)->wait(0.05), cv(9)->wait(0.03), 10, cv(undef) )
        ->recv
    ],
    [ 1, 2, 3, 4, undef, 5, 6, '', undef, 7, 8, 9, 10, undef ],
    'Merge with timers'
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
    [ cv(1, 2)->shadow( 3, 4 )->merge( 5 )->recv ],
    [ 3, 4, 5 ],
    'Shadow scalar'
);

is_deeply(
    [ cv(1, 2)->shadow( cv( 3, 4 ) )->merge( 5 )->recv ],
    [ 3, 4, 5 ],
    'Shadow condvar'
);

is_deeply(
    [ portal->wait( 0.1 )->then( sub { cv( 3, 4 ) } )
        ->wait( 0.1 )->shadow( cv( 1, 2 ) )->recv ],
    [ 1, 2 ],
    'Shadow wait'
);

is_deeply(
    [ portal( sub { 
        my $jump = $jump; #Lexical variable
        my $w; $w = AnyEvent->timer( after => 0.05, cb => sub {
            undef $w;
            $jump->( 1, 2 );
        });
    } )->shadow( 
        portal( sub {
            my $jump = $jump; #Lexical variable
            my $w; $w = AnyEvent->timer( after => 0.1, cb => sub {
                undef $w;
                $jump->( 4, 5 );
            });
        })
    )->recv ],
    [ 4, 5 ],
    'Shadow portal wait'
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
    [ cv(2)->merge( cv(3) )->wait( 0.1 )->merge( cv(4) )->recv ],
    [ 2, 3, 4 ],
    'Wait',
);

### Utility Operators ###

is_deeply(
    [ portal->recv ],
    [],
    'portal empty'
);

is_deeply(
    [ portal( 2 )->recv ],
    [ 2 ],
    'portal single scalar'
);

is_deeply(
    [ portal( 1, 2, 3 )->recv ],
    [ 1, 2, 3 ],
    'portal array'
);

is_deeply(
    [ portal( cv() )->recv ],
    [],
    'portal empty portal'
);

is_deeply(
    [ portal( cv( 3 ) )->recv ],
    [ 3 ],
    'portal single portal value'
);

is_deeply(
    [ portal( cv( 1, 2 ) )->recv ],
    [ 1, 2 ],
    'portal list portal values'
);

is_deeply(
    [ portal( cv( 1, 2 ), cv(), cv( 5, 6 ), cv( 7 ) )->recv ],
    [ 1, 2, 5, 6, 7 ],
    'portal list portals'
);

is_deeply(
    [ portal( anyevent_cv() )->recv ],
    [],
    'portal empty anyevent'
);

is_deeply(
    [ portal( anyevent_cv( 2 ) )->recv],
    [ 2 ],
    'portal simple anyevent value'
);

is_deeply(
    [ portal( anyevent_cv( 1, 2, 3 ) )->recv],
    [ 1, 2, 3 ],
    'portal list anyevent values'
);

is_deeply(
    [ portal( 
        anyevent_cv( 1 ), 
        anyevent_cv(), 
        anyevent_cv( 3, 4 ), 
        anyevent_cv( 5, 6 ), 
    )->recv ],
    [ 1, 3, 4, 5, 6 ],
    'portal list anyevent cvs'
);

is_deeply(
    [ portal( undef )->recv ],
    [ undef ],
    'undef portal'
);

is_deeply(
    [ portal( undef, undef, undef )->recv ],
    [ undef, undef, undef ],
    'triple undef portal'
);

is_deeply(
    [ portal( 
        anyevent_cv( 1 ), 
        ( 2, 3 ),
        cv(),
        undef,
        3.5,
        cv( 4, undef, 5 ),
        anyevent_cv( 6, undef ),
        cv( 7 )->wait( 0.1 ),
        undef,
        cv( undef )->wait( 0.1 ),
    )->recv ],
    [ 1, 2, 3, undef, 3.5, 4, undef, 
        5, 6, undef, 7, undef, undef ],
    'portal mix'
);

is_deeply(
    [ portal( sub { $jump->( 1, 2, undef, 3, undef ) } )->recv ],
    [ 1, 2, undef, 3, undef ],
    'portal coderef'
);

is_deeply(
    [ portal( sub { 
        my $jump = $jump; #Lexical variable
        cv()->wait( 0.1 )->then( sub {
            $jump->( undef, 4, 5, undef ) 
        }) 
    } )->recv ],
    [ undef, 4, 5, undef ],
    'portal coderef wait'
);

is_deeply(
    [ portal( sub { 
        cv( 7, 8, undef )->wait( 0.1 )->then( $jump ) 
    } )->recv ],
    [ 7, 8, undef ],
    'portal coderef wait 2'
);

done_testing();

sub anyevent_cv {
    my $cv = AnyEvent->condvar;
    $cv->send( @_ );
    $cv;
}

sub cv {
    my $cv = Continuum::Portal->new;
    $cv->send( @_ );
    $cv;
}
