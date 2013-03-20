# NAME

Continuum - A continuation framework for Mojo & AnyEvent

# DESCRIPTION

Continuum is a continuation framework that attempts to bring a bit of
sanity and fun into asynchronous programming. We try to both
improve the readability of your code and decrease the level of
callback embedding that usually comes with asynchronous code. 

Continuum is built on top of the [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) framework, more
specifically the [AnyEvent::CondVar](http://search.cpan.org/perldoc?AnyEvent) condition variables. If
you're not yet familiar with AnyEvent, it's a good time to get
acquainted! Understanding condition variables is essential to using
this module efficiently. However, we provide a different analogy to
the _boring_ condition variable semantics: we'll talk about portals!
Yes, just like the Stargate portals.

There are two schools of asynchronous programming styles in Perl.
Either you require the user to provide a callback that will be
triggered once the results are available, or you can give the user a
promise of delivering the results some time in the future. In the
[AnyEvent](http://search.cpan.org/perldoc?AnyEvent) framework, this promise is a condition variable. In
Continuum, we call them portals. Essentially, if someone wants to do
an asynchronous database call, we hand them a Portal and we promise
that the database results will come out of that Portal once they are
ready. 

Aside from the different naming conventions, the power of Continuum
comes from it's Portal manipulation API. We make it easy to connect
portals, apply various functions to portals and handle the Portal
results once they are available. Because portals are essentially
glorified condition variables, Continuum also makes it easier to work
with them. Let's see our way through an example to understand the
differences and advantages of Continuum. Let's assume we have access
to an asynchronous `$fleet` API that returns [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) condition
variables:

```perl
    use AnyEvent;

    sub assemble\_squad {
        my %squad;
        my $cv = AnyEvent->condvar;

        $cv->begin( sub {
            shift->send( %squad );
        } );

        foreach my $ship ( @\_ ) {
            $cv->begin;
            $fleet->find( $ship )->cb( sub {
                $squad{ $ship } = shift->recv;
                $cv->end;
            } );
        }

        $cv->end;
        return $cv;
    }

    # Usage (non-blocking)
    assemble\_squad(
        'Millennium Falcon',
        'USS Enterprise',
        'Destiny',   
    )->cb( sub {
        my %squad = shift->recv;
    } );
```

This is the traditional way of building condition variables. You set your
callback in the first `being` call. This will be triggered when all the
fleet ships are assembled and will call `send` on your condition variable.
A loop iterates over all of your ships, setting non-blocking callbacks with
the proper `begin` and `end` calls to increment and decrement a condition
variable's internal counter. This condition variable is returned to the
caller who can wait for the fleet to assemble in a blocking or non-blocking
way.

There are a few problems with this approach regarding code readability and
execution flow. It is not immediately obvious how this code works and when
different blocks of code execute.  The order of execution is confusing. This
might be fine for small projects but becomes rapidly unmaintainable for
non-trivial code bases.  Continuum allows you to rewrite the above example in
a functionally equivalent manner as:

```perl
    use Continuum;

    sub assemble\_squad {
        portal( map { $fleet->find( $\_ ) } @\_ );
    }

    # Usage
    assemble\_squad(
        'Millennium Falcon',
        'USS Enterprise',
        'Destiny',   
    )->then( sub { my %squad = @\_ } );
```

Much shorter and (hopefully) easier to understand.

`portal` can build a new Portal from a list of [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) condition
variables. The new portal will trigger once all the conditions become
true in the input condition variables. `portal` can also build a
portal from a list of Portals or from a code reference. We will study
such an example later in this tutorial. In the example above,
`portal` creates a new Portal that will deliver the Millennium
Falcon, the USS Enterprise and the Destiny once all of them are found
(through their underlying condition variable).

Using `portal` is equivalent to using the `merge` call from the
Portal API. We will have a look at it now. Let's assume our `$fleet`
API is Portal-enabled and returns portals for all of its calls. We
could selectively find individual ships in parallel:

```perl
    $fleet->find( 'Millennium Falcon' ) 
        ->merge( $fleet->find( 'USS Enterprise' ) )
        ->then( sub { my @ships = @\_ } );
```

`merge` essentially creates a new Portal that will deliver the
results of it's input portals when all of them are ready. It executes
all the portals in parallel and merges the results into a list.
`merge` is part of the Portal API and as such, is called in _chain_
mode on an existing Portal.

`then` is used when you have data dependencies between different
asynchronous calls. It is probably the most important function of the
Continuum API. You can apply arbitrary transformations to the results
of any Portal by chaining a `then` call. The function provided in
`then` will only be called when the results from the Portal are
available, instead of running in parallel. It is the primary way of
defining continuations in Continuum. 

`then` will create a new Portal, like every other call in the
Continuum API (this allows for chaining calls). The Portal will
eventually return the value returned by the `then` function. If you
return a Portal or a condition variable from within your function, it
will be linked to the outer Portal created by `then`. You can also
return a list of Portals or condition variables. They will be merged
using the `merge` API call before being linked to the outer Portal.

When you are playing with Continuum, you are chaining portals together
using transformations. Every call to the Portal API creates a new
Portal returning a transformation of the previous portals results.
When something actually comes out of the first Portal in your chain,
all the transformations that you have created will be applied and the
final result will come out of the last Portal in your chain. As far as
your users are concerned, if you only give them the last Portal in
your chain, the rest is completely abstracted and equivalent to a
black box.

A different analogy for Continuum is that you are applying
transformation to future values. Applying a transformation to a Portal
is essentially equivalent to applying the same transformation to the
value that will come out of the Portal some time in the future.  The
Portal only stores the transformation until it can be applied to the
value coming out of the Portal.

## More Examples

Let's build on top of the previous example and create a function that
can repair a ship. It needs to find the ship, repair it and put it
back into the fleet. These 3 actions are provided by the `$fleet` API
which is Portal-enabled.

```perl
    # Returns a Portal
    sub find\_and\_repair {
        my $ship = shift;
        $fleet->find( $ship )
            ->then( sub { $fleet->repair( shift ) } )
            ->then( sub { $fleet->put( shift ) } );
    }
```

We have data dependencies between our 3 asynchronous operations and
can not process them in parallel (we actually need to find a ship
before we can start the repair work). Using `then`, we chain the
necessary transformations to our ship.

Nothing prevents us, however, from finding and repairing multiple
ships in parallel:

```perl
    find\_and\_repair( 'Millennium Falcon' )->merge( 
        find\_and\_repair( 'USS Enterprise' ) 
        find\_and\_repair( 'Destiny' ) 
    );
```

We can even repair a whole fleet of ships in parallel:

```perl
    portal( map { find\_and\_repair( $\_ ) } @ships )
```

We could also have implemented the find and repair algorithm
differently, using the `map` function from the Portal API:

```perl
    sub find\_and\_repair {
        my @ships = @\_;
        portal( @ships )
            ->map( sub { $fleet->find( $\_ ) } )
            ->map( sub { $fleet->repair( $\_ ) } )
            ->map( sub { $fleet->put( $\_ ) } );
    }
```

We start by creating a new Portal containing all the ships. Then we
map them through 3 portals that respectively finds the ships, repairs
them and puts them back into the fleet. The difference here is that
the find, repair and put are batch operations. First we find all
the ships in parallel, then we repair them all in parallel, then we
put them back into the fleet in parallel. In our first example, the
find => repair => put pipeline was independent for every ship.

## Bridging the gap

In order to access to Portal API, we need an easy way to create
Portals. The `portal` keyword is there to help us bridge the gap
between traditional asynchronous methods (condition variables and
callbacks) and the Portal world. We already saw how to create a Portal
from a condition variable earlier in this tutorial.

```perl
    portal( @condition\_variables )
```

This creates a Portal that merges the results of all the input
condition variables together and returns them when they are all
available. The condition variables execute in parallel.  If you are
working with a condition variable API, it is easy to use them to
access the Portal API:

```perl
    portal( $db->get( $key1 ), $db->get( $key2 ) )
        ->then( sub { 
            my ( $value1, $value2 ) = @\_;
            ...
        } );
```

We also provide an easy way to create Portals from a callback oriented
API (like [Mojo::Redis](http://search.cpan.org/perldoc?Mojo::Redis)):

```perl
    portal( sub { $redis->get( $key => $jump ) } );
```

It works by passing a function to `portal` in which you can make your
call to your callback-oriented API. Inside the function, you have
access to the `$jump` variable which is equal to the Portal returned
by the `portal` call. This allows you to pass it as a code reference
to your callback API, or call `$jump->send(...)` manually when you
are ready to send data through your Portal. Let's demonstrate that
second case:

```perl
    portal( sub {
        my $jump = $jump; # Create a lexical copy
        $redis->get( $key => sub {
            my ( $redis, $value ) = @\_;
            # Equivalent to $jump->send( $value )
            $jump->( $value ); # Trigger the Portal
        } );
    } );
```

Because `$jump` is a local variable, we need to create a lexical
equivalent to access it from the Redis callback. Using this style, we
can easily access to Portal API:

```perl
    # Prepare the Portal
    sub portal\_get {
        my $key = shift;
        portal( sub { 
            my $jump = $jump;
            $redis->get( $key => sub { $jump->( $\_[1] ) } ) 
        } );
    }

    # Use your new Portal function
    portal\_get( $key1 )->merge( portal\_get( $key2 ) )
        ->then( sub {
            my ( $value1, $value2 ) = @\_;
            ...
        } );
```

We can even process lists of keys in this way

```perl
    portal( map { portal\_get( $\_ ) } @keys )
        ->then( sub {
            my @values = @\_;
            ...
        } );
```

This last example demonstrates the last case of the `portal`
function. It also accepts lists of Portals and will process them in
the same way as it processes condition variables. It merges all the
input portals and returns their values from a new Portal once they are
all available. In the example above, we simply chain a `then` call to
capture the results in a callback.

While I still have your attention, let's work our way through a last
example to build on the concepts we have just learned. Let's assume we
have access to a callback-oriented `$fleet` API and we want to write
a little program that can find all the ships with repair capabilities
in the fleet and all damaged ships. We them have all the damaged ships
repaired by the repairer ships.

```perl
    use Continuum;

    sub fleet\_find {
        my ( $fleet, type ) = @\_;
        # Create a portal returning all the ships
        portal( sub { $fleet->getall( $jump ) } )
            # and filter the portal results by ship type
            ->grep( sub { $\_->type eq $type } )
            # Return a reference through the portal
            ->then( sub { \@\_ } );
    }

    sub repair\_fleet {
        my $fleet = shift;
        fleet\_find( $fleet => 'repair' )
            ->merge( fleet\_find( $fleet => 'damaged' ) )
            ->then( sub {
                my ( $repairer, $damaged ) = @\_; 
                portal( sub {
                    $fleet->repair( $repairer, $damaged, $jump )
                } );
            } );
    }
```

With these functions, we have the possibility of repairing a complete
fleet of ships! If we have multiple fleets under our command, it is
easy to repair them all in parallel:

```perl
    repair\_fleet( $alpha\_fleet )
        ->merge( repair\_fleet( $gamma\_fleet ) );
```

Or if we need to repair an entire empire of fleets:

```perl
    portal( map { repair\_fleet( $\_ ) } @fleets );
```

The sky's the limit!

## Learn more about portals

You can write most of your Portal code using the techniques described
in this tutorial. There are however a lot more functions available in
the Portal API. Feel free to head to the wiki for additional
documentation.

( TODO ... )

## Installing Continuum

Install AnyEvent from CPAN or your distribution repositories by using one of
these lines:

```sh
    apt-get install libanyevent-perl   # Debian/Ubuntu
    yum install perl-AnyEvent          # RedHat/Fedora
    cpan install AnyEvent              # CPAN (any)
```

Download and install Continuum

```sh
    git clone https://github.com/ciphermonk/Continuum.git
    cd Continuum
    perl Makefile.PL && make && sudo make install
```

## Bugs

Please report any bugs in the projects bug tracker:

[http://github.com/ciphermonk/Continuum/issues](http://github.com/ciphermonk/Continuum/issues)

You can also submit a patch.

## Contributing

We're glad you want to contribute! It's simple:

- Fork the Continuum (and perhaps claim a nobel prize in physics)
- Create a branch `git checkout -b my\_branch`
- Commit your changes `git commit -am 'comments'`
- Push the branch `git push origin my\_branch`
- Open a pull request

## Supporting

Like what you see? You can support the project by donating in
[Bitcoins](http://www.weusecoins.com/) to:

__17YWBJUHaiLjZWaCyPwcV8CJDpfoFzc8Gi__