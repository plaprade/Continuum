package AnyEventX::CondVar;

use strict;
use warnings;

use AnyEvent;
use AnyEventX::CondVar::Util qw( :all );
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
            "$b $op $a" :
            "$a $op $b";
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

sub cons {
    my ( $self, $other ) = @_;
    $self->then( sub {
        my @list = @_;
        is_cv( $other ) ? 
            $other->then( sub { ( @list, @_ ) } ) :
            ( @list, $other );
    });
}

sub push : method {
    shift->cons( shift );
}

sub pop : method {
    shift->then( sub { pop; @_ } );
}

sub shift : method {
    shift->then( sub { shift; @_ } ); 
}

sub unshift : method {
    my ( $self, $elem ) = @_;
    $self->then( sub { 
        unshift @_, $elem; 
        @_; 
    }); 
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
            sort { $fn->() } @_ :
            sort @_;
    });
}

sub sum {
    my $self = shift;
    my $cv = AnyEventX::CondVar->new();
    $self->cb( sub {
        my $sum = 0;
        $sum += $_ for ( shift->recv );
        $cv->send( $sum );
    });
    $cv;
}

sub mul {
    my $self = shift;
    my $cv = AnyEventX::CondVar->new();
    $self->cb( sub {
        my $mul = 1;
        $mul *= $_ for ( shift->recv );
        $cv->send( $mul );
    });
    $cv;
}

sub unique {
    my ( $self, $fn ) = @_;
    $self->then( sub {
        values %{{ map { $fn->() => $_ } @_ }};
    });
}

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
        my @res = $cb->( shift->recv );
        is_cv( @res ) ?
            $res[0]->cb( sub {
                $cv->send( shift->recv ); 
            }) : 
            $cv->send( @res );
    });
    $cv;
}

1;
