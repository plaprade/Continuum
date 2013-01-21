package AnyEventX::CondVar;

use strict;
use warnings;

use AnyEvent;
use AnyEventX::CondVar::Util qw( :all );
use List::Util;
use Carp;
require Exporter;

use version; our $VERSION = version->declare("v0.0.2"); 

our @ISA = qw( AnyEvent::CondVar );

#    All Perl operators:
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
            croak "Can't stringify AnyEventX::CondVar. You probably "
                . "want to call ->recv or ->cb to read the value."
        },
        '0+' => sub {
            croak "Can't numify AnyEventX::CondVar. You probably "
                . "want to call ->recv or ->cb to read the value."
        },
        'bool' => sub {
            croak "Can't boolify AnyEventX::CondVar. You probably "
                . "want to call ->recv or ->cb to read the value."
        },
    ),
);

=pod

=head1 NAME

AnyEventX::CondVar - Asynchronous continuation framework for Perl

=cut

### Basic Perl operator overload ###

sub _op2 {
    my ( $op, $self, $other, $swap ) = @_;

    $self->first->cons(
        is_cv( $other ) ? $other->first : $other 
    )->then( sub {
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

    $self->first->then( sub {
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
    my $cv = AnyEventX::CondVar->new();
    $self->cb( sub {
        my @left = shift->recv;
        is_cv( $other ) ?
            $other->cb( sub {
                $cv->send( @left, shift->recv );
            }) :
            $cv->send( @left, $other );
    });
    $cv;
}

sub append {
    my ( $self, $x, @xs ) = @_;
    return $self unless defined $x || @xs;
    $self->cons( $x )->append( @xs );
}

### Continuation - Data dependencies ###

sub then {
    my ( $self, $cb ) = @_;
    my $cv = AnyEventX::CondVar->new();
    $self->cb( sub {
        my @res = $cb->( shift->recv );
        cv->append( @res )->cb( sub {
            $cv->send( shift->recv );
        });
    });
    $cv;
}

### List operations ###

sub push : method {
    my ( $self, @list ) = @_;
    $self->append( @list );
}

sub pop : method {
    shift->then( sub { pop; @_ } );
}

sub unshift : method {
    my ( $self, @list ) = @_;
    $self->then( sub { 
        @list, @_;
    }); 
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
        my $bool = $fn->();
        is_cv( $bool ) ?
            $bool->then( sub { [ $_, shift ] } ) : 
            [ $_, $bool ];
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
                $caller ne 'AnyEventX::CondVar'
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
            $caller ne 'AnyEventX::CondVar'
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

# TODO : NAMING ?? USEFULL ??
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

# TODO: NAMING ??!?!?
sub result {
    my ( $self, @args ) = @_;
    $self->then( sub { @args } );
}

sub any {
    my ( $self, $other ) = @_;

    my $cv = AnyEventX::CondVar->new();
    my $done = ! is_cv( $other );

    $self->cb( sub {
        $cv->send( shift->recv ) and $done = 1
            unless $done;
    });

    is_cv( $other ) ?
        $other->cb( sub {
            $cv->send( shift->recv ) and $done = 1
                unless $done;
        }) :
        $cv->send( $other );

    $cv;
}

sub wait {
    my ( $self, $time ) = @_;
    my $cv = AnyEventX::CondVar->new();
    $self->cb( sub {
        my @args = shift->recv;
        my $t; $t = AnyEvent->timer( after => $time, cb => sub {
            undef $t;
            $cv->send( @args );
        });
    });
    $cv;
}

1;
