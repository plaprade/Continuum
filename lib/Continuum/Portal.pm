package Continuum::Portal;

use strict;
use warnings;

use AnyEvent;
use List::Util;
use Carp;
use Continuum::Util;

our @ISA = qw( AnyEvent::CondVar );

#    All Perl operators ( for reference ):
#
#    with_assign => [ qw( + - * / % ** << >> x . ) ],
#    assign => [ qw( += -= *= /= %= **= <<= >>= x= .= ) ],
#    num_comparison => [ qw( < <= > >= == != ) ],
#    '3way_comparison' => [ qw( <=> cmp ) ],
#    str_comparison => [ qw( lt le gt ge eq ne ) ],
#    binary => [ qw( & &= | |= ^ ^= ) ],
#    unary => [ qw( neg ! ~ ) ],
#    mutators => [ qw( ++ -- ) ],
#    func => [ qw( atan2 cos sin exp abs log sqrt int ) ],
#    conversion => [ qw( bool "" 0+ qr ) ],
#    iterators => [ qw( <> ) ],
#    filetest => [ qw( -X ) ],
#    dereferencing => [ qw( ${} @{} %{} &{} *{} ) ],
#    matching => [ qw( ~~ ) ],
#    special => [ qw( nomethod fallback = ) ],
#

use overload (
    ( map { my $op = $_; $op => sub { _op2( $op, @_ ) }  }
        ( 
            qw( + - * / % ** << >> x . ),
            qw( < <= > >= == != ),
            qw( <=> cmp ),
            qw( lt le gt ge eq ne ),
            qw( & | ^ ),
            qw( ~~ ),
        )),
    ( map { my $op = $_; $op => sub { _op1( $op, @_ ) }  }
        ( 
            qw( neg ! ~ ),
            qw( atan2 cos sin exp abs log sqrt int ),
        ) ),
    (
        '""' => sub {
            croak "Can't stringify Continuum::Portal. You probably "
                . "want to call ->recv or ->cb to read the value."
        },
        '0+' => sub {
            croak "Can't numify Continuum::Portal. You probably "
                . "want to call ->recv or ->cb to read the value."
        },
        'bool' => sub {
            croak "Can't boolify Continuum::Portal. You probably "
                . "want to call ->recv or ->cb to read the value."
        },
    ),
);

=pod

=head1 NAME

Continuum::Portal - Asynchronous continuation framework for Perl

=cut

### Basic Perl operator overload ###

sub _op2 {
    my ( $op, $self, $other, $swap ) = @_;

    $self->cons( $other )->then( sub {
        my ( $a, $b ) = @_;
        my $stm = $swap ?
            '$b ' . $op . ' $a' :
            '$a ' . $op . ' $b';
        my $res = eval( $stm );
        carp "Error evaluating '$stm' : $@" if $@;
        $res;
    });
}

sub _op1 {
    my ( $op, $self ) = @_;

    $self->then( sub {
        my $a = shift;
        my $stm = $op . '$a';
        my $res = eval( $stm ); 
        carp "Error evaluating '$stm' : $@" if $@;
        $res;
    });
}

### Concatenation - Append ###

sub cons {
    my ( $self, $other ) = @_;
    my $portal = Continuum::Portal->new;
    $self->cb( sub {
        my @left = shift->recv;
        is_portal( $other ) ?
            $other->cb( sub {
                $portal->send( @left, shift->recv );
            }) :
            $portal->send( @left, $other );
    });
    $portal;
}

sub append {
    my ( $self, $x, @xs ) = @_;
    return $self unless defined $x || @xs;
    $self->cons( $x )->append( @xs );
}

### Continuation - Data dependencies ###

sub then {
    my ( $self, $cb ) = @_;
    my $portal = Continuum::Portal->new;
    $self->cb( sub {
        my $inner = Continuum::Portal->new; 
        $inner->send();
        $inner->append( $cb->( shift->recv ) )->cb( sub {
            $portal->send( shift->recv );
        });
    });
    $portal;
}

### List operations ###

sub push : method {
    shift->append( @_ );
}

sub pop : method {
    shift->then( sub { pop; @_ } );
}

sub unshift : method {
    my ( $self, @list ) = @_;
    $self->then( sub { @list, @_ } ); 
}

sub shift : method {
    shift->then( sub { shift; @_ } ); 
}

### Get/Set List elements ###

sub aget {
    my ( $self, @pos ) = @_;
    $self->then( sub {
        my @list = @_;
        map { $list[ $_ ] } @pos;
    });
}

sub aset {
    my ( $self, $pos, $value ) = @_;
    $self->then( sub {
        my @list = @_;
        $list[ $pos ] = $value;
        @list;
    });
}

sub first {
    shift->aget( 0 );
}

sub last {
    shift->aget( -1 );
}

### Get/Set Hash elements ###

sub hget {
    my ( $self, @keys ) = @_;
    $self->then( sub {
        my %h = @_;
        map { $h{ $_ } } @keys;
    });
}

sub hset {
    my ( $self, $key, $value ) = @_;
    $self->then( sub {
        my %h = @_;
        $h{ $key } = $value;
        %h;
    });
}

### Advanced List operations ###

sub map : method {
    my ( $self, $fn ) = @_;
    $self->then( sub {
        map { $fn->() } @_;
    });
}

sub grep : method {
    my ( $self, $fn ) = @_;
    $self->map( sub {
        my $portal = Continuum::Portal->new;
        $portal->send();
        $portal->cons( $fn->() )->then( sub {
            [ $_, shift ]
        });
    })->then( sub {
        map { $_->[0] }
            grep { $_->[1] } @_;
    });
}

sub sort : method {
    my ( $self, $fn ) = @_;

    my $caller = caller;

    $self->then( sub {
        no strict 'refs';
        defined $fn ? sort { 
                $caller ne 'Continuum::Portal'
                    and local( *{ $caller . '::a' } ) = \$a
                    and local( *{ $caller . '::b' } ) = \$b;
                $fn->(); 
            } @_ : sort @_;
    });
}

sub reduce : method {
    my ( $self, $fn, @acc ) = @_;

    my $caller = caller;

    $self->then( sub {
        no strict 'refs';
        List::Util::reduce { 
            $caller ne 'Continuum::Portal'
                and local( *{ $caller . '::a' } ) = \$a
                and local( *{ $caller . '::b' } ) = \$b;
            $fn->();
        } ( @acc, @_ );
    });
}

sub unique {
    my ( $self, $fn ) = @_;
    $self->then( sub {
        values %{{ map { $fn->() => $_ } @_ }};
    });
}

sub sum {
    my $self = shift;
    $self->reduce( sub { $a + $b } );
}

sub mul {
    my $self = shift;
    $self->reduce( sub { $a * $b } );
}

### Boolean operations ###

sub and : method {
    my ( $self, $cb ) = @_;
    $self->then( sub {
        $_[0] ? $cb->( @_ ) : @_;
    });
}

sub or : method {
    my ( $self, $cb ) = @_;
    $self->then( sub {
        $_[0] ? @_ : $cb->( @_ );
    });
}

### Stash operations ###

my @stash;

sub push_stash {
    my $self = shift;
    $self->then( sub {
        push @stash, \@_;
        @_;
    });
}

sub pop_stash {
    my $self = shift;
    $self->then( sub {
        @{ pop @stash };
    });
}

### MISC Operators ###

sub deref {
    my $self = shift;
    $self->then( sub {
        map {
            ref $_ eq 'HASH' ?
                %{ $_ } :
                ref $_ eq 'ARRAY' ?
                @{ $_ } : $_
        } @_;
    });
}

sub shadow {
    my ( $self, @args ) = @_;
    $self->then( sub { @args } );
}

sub any {
    my ( $self, $other ) = @_;

    my $portal = Continuum::Portal->new;
    my $pending = is_portal( $other );

    $self->cb( sub {
        if( $pending ) {
            $portal->send( shift->recv );
            $pending = 0;
        }
    });

    is_portal( $other ) ?
        $other->cb( sub {
            if( $pending ){
                $portal->send( shift->recv );
                $pending = 0;
            }
        }) : $portal->send( $other );

    $portal;
}

sub wait {
    my ( $self, $time ) = @_;

    my $portal = Continuum::Portal->new;

    $self->cb( sub {
        my @args = shift->recv;
        my $t; $t = AnyEvent->timer( after => $time, cb => sub {
            undef $t;
            $portal->send( @args );
        });
    });

    $portal;
}

1;

