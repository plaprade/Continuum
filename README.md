## Continuum - A continuation framework for Mojo & AnyEvent

Continuum is a continuation framework that attempts to bring a bit of
sanity and fun into asynchronous programming. We try to both
improve the readability of your code and decrease the level of
callback embedding that usually comes with asynchronous code. 

Continuum is built on top of the [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) framework, more
specifically the [AnyEvent::CondVar](http://search.cpan.org/perldoc?AnyEvent) condition variables. If
you're not yet familiar with AnyEvent, it's a good time to get
acquainted! Understanding condition variables is essential to using
this module efficiently. However, we provide a different analogy to
the _boring_ condition variable semantics: we'll talk about Portals!
Yes, just like the Stargate Portals.

There are two schools of asynchronous programming styles in Perl.
Either you require the user to provide a callback that will be
triggered once the results are available, or you can give the user a
promise of delivering the results some time in the future. In the
[AnyEvent](http://search.cpan.org/perldoc?AnyEvent) framework, this promise is a condition variable. In
Continuum, we call them Portals. Essentially, if someone wants to do
an asynchronous database call, we hand them a Portal and we promise
that the database results will come out of that Portal once they are
ready. 

Aside from the different naming conventions, the power of Continuum
comes from it's Portal manipulation API. We make it easy to connect
Portals, apply various functions to Portals and handle the Portal
results once they are available. Because Portals are essentially
glorified condition variables, Continuum also makes it easier to work
with them. Let's see our way through an example to understand the
differences and advantages of Continuum. Let's assume we have access
to an asynchronous `$fleet` API that returns [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) condition
variables:

```perl
    use AnyEvent;

    sub assemble_squad {
        my %squad;
        my $cv = AnyEvent->condvar;

        $cv->begin( sub {
            shift->send( %squad );
        });

        foreach my $ship ( @_ ){
            $cv->begin;
            $fleet->find( $ship )->cb( sub {
                $squad{ $ship } = shift->recv;
                $cv->end;
            });
        }

        $cv->end;
        return $cv;
    }

    # Usage (non-blocking)
    assemble_squad(
        'Millennium Falcon',
        'USS Enterprise',
        'Destiny',   
    )->cb( sub {
        my %squad = shift->recv;
    });
```

This is the traditional way of building condition variables. You set
your callback in the first `being` call. This will be triggered when
all the fleet ships are assembled and will call `send` on your
condition variable. Then you loop over all of your ships, setting
non-blocking callbacks with the proper `begin` and `end` calls to
increment and decrement the condition variables internal counter. You
give this condition variable to the caller who can wait for the fleet
to assemble in a blocking or non-blocking way.

Our humbly believe there are a few problems with this approach:
essentially code readability and execution flow. It is not immediately
obvious how this code works and when different blocks of code execute.
The order of execution is confusing. This might be fine for small
projects but becomes rapidly unmaintainable for non-trivial code bases.
Continuum allows you to rewrite the above example in a functionally
equivalent manner as:

```perl
    use Continuum;

    sub assemble_squad {
        portal->append( map{ $fleet->find( $_ ) } @_ );
    }

    # Usage
    assemble_squad(
        'Millennium Falcon',
        'USS Enterprise',
        'Destiny',   
    )->then( sub {
        my %squad = @_;
    });
```

Much shorter and (hopefully) easier to understand.

We use `append` in this example, which is one of multiple functions
available in the Portal API. Append essentially acts as a merge-point
for Portals and condition variables. It builds a new Portal that will
trigger only once all the input Portal values are available.  In this
case, append creates a new Portal that will deliver the Millennium
Falcon, the USS Enterprise and the Destiny once all of them are
available.

Now, let's assume our `$fleet` API is Portal-enabled and returns
Portals for all of its calls. We could selectively find individual
ships:

```perl
    $fleet->find( 'Millennium Falcon' ) 
        ->cons( $fleet->find( 'USS Enterprise' ) )
        ->then( sub {
            my @ships = @_;
        });
```

`cons` essentially creates a new Portal that will deliver the result
of it's two input Portals when both of them are ready. It concatenates
both results into a list. This is similar to `append`. In fact,
append is implemented using cons. It is also interesting to note that
all Portals passed to cons or append execute in parallel.

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
will be linked to the outer Portal created by `then`.

When you are playing with Continuum, you are chaining Portals together
using transformations. Every call to the Portal API creates a new
Portal returning a transformation of the previous Portals results.
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

## Extended examples

Let's build on top of the previous example and create a function that
can repair a ship. It needs to find the ship, repair it and put it
back into the fleet. These 3 actions are provided by the `$fleet` API
which is Portal-enabled.

```perl
    # Returns a Portal
    sub find_and_repair {
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

Nothing prevents us, however, from finding and repairing two ships in
parallel:

```perl
    find_and_repair( 'Millennium Falcon' )
        ->cons( find_and_repair( 'USS Enterprise' ) )
        ->cons( find_and_repair( 'Destiny' ) )
        ->then( sub {
            my @repaired_ships = @_;
        });
```

We can even repair a whole fleet of ships in parallel:

```perl
    portal
        ->append( map { find_and_repair( $_ ) } @ships )
        ->then( sub {
            my @repaired_ships = @_;
        });
```

`cons` and `append` are similar in function. You use cons when you
want to process two Portals in parallel. You use append when you have
a list of Portals to process in parallel. 

We could also have implemented the find and repair algorithm
differently, using the `map` function from the Portal API:

```perl
    sub find_and_repair {
        my @ships = @_;
        portal
            ->append( @ships )
            ->map( sub { $fleet->find( $_ ) } )
            ->map( sub { $fleet->repair( $_ ) } )
            ->map( sub { $fleet->put( $_ ) } );
    }
```

We start by creating a new Portal containing all the ships. Then we
map them through 3 Portals that respectively finds the ships, repairs
them and puts them back into the fleet. The difference here is that
the find, repair and put are batch operations. First we find all
the ships in parallel, then we repair them all in parallel, then we
put them back into the fleet in parallel. In our first example, the
find => repair => put pipeline was independent for every ship.

## From callbacks to Portals

We didn't explain the `portal` keyword yet. It allows us to create a
new Portal from scratch. We used it up until now to create an empty
Portal when we didn't have a prior Portal to access the Portal API.
`portal` is actually much more powerful, as it allows us to create
Portals from a chain of arbitrary callbacks. This is very useful when
you need to map a callback-oriented API to a Portal API. Let's
demonstrate.

Assume we have an asynchronous callback-oriented `$db` API.

```perl
    use Continuum;

    sub get {
        my $key = shift;
        portal {
            $db->get( $key => $jump );
        } continuum {
            my $value = shift;
        }
    }; 
```

`portal` takes a list of functions as argument. We have a very neat
syntax to create Portals with the `continuum` keyword. Every
`continuum` simply declares a new function. In every function, you
are either expected to call `$jump` to go to the next function in the
chain, or return a Portal ( or [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) condition variable ) which
will trigger the next function when the results are available. 

The `Portal` call will immediately return a Portal to the user. The
value that will come out of the Portal is the return value of your
last function in the chain. The above example is a trivial one-to-one
mapping from a callback API to a Portal. It is usually more
interesting to write application specific Portals from a callback API.
We might want to create a Portal that finds all the repair-class ships
in our fleet and command them to repair all the damaged ships. Let's
assume the `$fleet` API is an asynchronous callback-oriented
framework.

```perl
    use Continuum;

    sub repair_fleet {
        my $fleet = shift;
        portal {
            $fleet->findclass( repair => $jump )
        } continuum {
            my @repair_ships = @_;
            $fleet->finddamaged( sub { 
                my @damaged_ships = @_;
                $jump->( \@repair_ships, \@damaged_ships ); 
            });
        } continuum {
            my ( $repair_ships, $damaged_ships ) = @_;
            $fleet->repair( $repair_ships => $damaged_ships => $jump );
        } continuum {
        # Let's assume that $fleet->repair will return the repaired ships
            my @ships = @_;
        }
    }
```

Now, with this Portal at our disposial, we can repair multiple fleets
in parallel!

```perl
    repair_fleet( $alpha_fleet )
        ->cons( repair_fleet( $beta_fleet ) )
        ->cons( repair_fleet( $gamma_fleet ) )
        ->then( sub {
            my @ships = @_;
        });
```

## Learn more about Portals

You can write most of your Portal code using the techniques described
in this tutorial. There are however a lot more functions available in
the Portal API. Feel free to head to the wiki for additional
documentation.

( TODO ... )

## Bugs

Please report any bugs in the projects bug tracker:

[http://github.com/ciphermonk/Continuum/issues](http://github.com/ciphermonk/Continuum/issues)

You can also provide a fix by contributing to the project:

## Contributing

We're glad you want to contribute! It's simple:

- Fork the Continuum (and perhaps claim a nobel prize in physics)
- Create a branch `git checkout -b my_branch`
- Commit your changes `git commit -am 'comments'`
- Push the branch `git push origin my_branch`
- Open a pull request

## Supporting

Like what you see? You can support the project by donating in
[Bitcoins](http://www.weusecoins.com/) to:

__17YWBJUHaiLjZWaCyPwcV8CJDpfoFzc8Gi__
