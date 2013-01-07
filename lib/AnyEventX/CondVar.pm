package AnyEventX::CondVar;

use strict;
use warnings;

use AnyEvent;
use AnyEventX::CondVar::Util qw( :all );
use List::Util;
use Carp;

use version; our $VERSION = version->declare("v0.0.2"); 

our @ISA = qw( AnyEvent::CondVar );

#my %ops = (
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
#);

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

### BASIC OPERATORS ###

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
        return ($a + 1) if $op eq '++';
        return ($a - 1) if $op eq '--';
        my $stm = "$op $a";
        my $res = eval( $stm ); 
        carp "Error evaluating '$stm' : $@" if $@;
        $res;
    });
}

### LIST OPERATORS ###

sub push : method {
    my ( $self, @elems ) = @_;
    $self->append( @elems );
}

sub pop : method {
    shift->then( sub { pop; @_ } );
}

sub unshift : method {
    my ( $self, $x, @xs ) = @_;
    $self->then( sub { 
        ( is_cv($x) ? $x : (cv_build{$x}))
            ->append( @xs, @_ );
    }); 
}

sub shift : method {
    shift->then( sub { shift; @_ } ); 
}

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

sub map : method {
    my ( $self, $fn ) = @_;
    $self->then( sub {
        map { $fn->() } @_;
    });
}

sub grep : method {
    my ( $self, $fn ) = @_;
    $self->then( sub {
        grep { $fn->() } @_;
    });
}

sub sort : method {
    my ( $self, $fn ) = @_;
    $self->then( sub {
        defined $fn ?
            sort { $fn->( $a, $b ) } @_ :
            sort @_;
    });
}

sub reduce : method {
    my ( $self, $fn, @acc ) = @_;
    $self->then( sub {
        List::Util::reduce { $fn->( $a, $b ) } ( @acc, @_ );
    });
}

sub sum {
    my $self = shift;
    $self->reduce( sub { $_[0] + $_[1] } );
}

sub mul {
    my $self = shift;
    $self->reduce( sub { $_[0] * $_[1] } );
}

sub unique {
    my ( $self, $fn ) = @_;
    $self->then( sub {
        values %{{ map { $fn->() => $_ } @_ }};
    });
}

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

### BOOLEAN OPERATORS ###

sub and : method {
    my ( $self, $cb ) = @_;
    $self->first->then( sub {
        $_[0] ? $cb->( @_ ) : @_;
    });
}

sub or : method {
    my ( $self, $cb ) = @_;
    $self->first->then( sub {
        my ( $x, @xs ) = @_;
        $_[0] ? @_ : $cb->( @_ );
    });
}

### MISC OPERATORS ###

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

# TODO: NAMING ??!?!?
sub result {
    my ( $self, @args ) = @_;
    $self->then( sub { @args } );
}

sub any {
    my ( $self, $other ) = @_;

    my $cv = AnyEventX::CondVar->new();
    my $done = ! is_cv( $other );

    $self->then( sub {
        $cv->send( @_ ) and $done = 1
            unless $done;
    });

    is_cv( $other ) ?
        $other->then( sub {
            $cv->send( @_ ) and $done = 1
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

sub then {
    my ( $self, $cb ) = @_;
    my $cv = AnyEventX::CondVar->new();
    $self->cb( sub {
        my ( $x, @xs ) = $cb->( shift->recv );

        (( is_cv($x) ? $x : (cv_build{$x}) )
            ->append( @xs ))
                ->cb( sub {
                    $cv->send( shift->recv );
                });

    });
    $cv;
}

sub append {
    my ( $self, $x, @xs ) = @_;
    return $self unless defined $x || @xs;
    $self->cons( $x )->append( @xs );
}

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


1;
