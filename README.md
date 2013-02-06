## Continuum - A continuation framework for Mojo & AnyEvent

Continuum is a continuation framework that attempts to bring a bit of
sanity and fun into your asynchronous programming. We try to both
improve the readability of your code and decrease the level of
callback embedding that usually comes with asynchronous code. 

Continuum is built on top of the [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) framework, more
specifically the [AnyEvent::CondVar](http://search.cpan.org/perldoc?AnyEvent) condition variables. If
you're not yet familiar with AnyEvent, it's a good time to get
acquainted! Understanding condition variables is essential to using
this module efficiently. However, we provide a different analogy to
the dryer condition variable semantics: we'll use portals! Yes, just
like the Stargate portals.

There are two schools of asynchronous programming styles in Perl.
Either you require the user to provide a callback that will be called
once the results are available, or you can give the user a promise of
delivering a result sometime in the future. In the [AnyEvent](http://search.cpan.org/perldoc?AnyEvent)
framework, this promise is a condition variable. In Continuum, we call
them Portals. Essentially, if someone wants to do an asynchronous
database call, we hand them a portal and we promise that the database
results will come out of that portal once they are ready. 

Aside from the different naming conventions, the power of Continuum
comes from it's portal manipulation API. We make it easy to connect
portals, apply various functions to portals and handle the portal
results once they are available. Because portals are very similar to
condition variables, Continuum also makes it easier to work with them.
Let's work our way through an example to understand the differences
and benefits of AnyEvent and Continuum. Let's assume we have access to
an asynchronous `$fleet` API that returns AnyEvent condition
variables.

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
give this condition variable to the caller who will wait for the fleet
to assemble in a blocking or non-blocking way.

According to us, there are a few problems with this approach:
essentially code readability and execution flow. It is not immediately
clear how this code works and when different blocks of code execute.
The order of execution is confusing. This might be fine for small
projects but becomes rapidly unmaintainable for non-trivial projects.
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

We use `append` in the example above, which is one of multiple
functions available in the portal API. `append` essentially acts as a
merge-point for portals or condition variables. It builds a new portal
that will trigger only once all the input portal values are available.
In our case, `append` creates a new portal out of which the
Millennium Falcon, the USS Enterprise and the Destiny will fly out at
the same time once they have been found. 

Now, let's assume our `$fleet` API is portal-enabled and returns
portals for all of its calls. We could selectively find individual
ships:

```perl
    $fleet->find( 'Millennium Falcon' ) =
        ->cons( $fleet->find( 'USS Enterprise' ) )
        ->then( sub {
            my @ships = @_;
        });
```

`cons` essentially creates a new portal that concatenates the values
of two portals. It will trigger once both input portal values are
available. This is similar to `append`. In fact, `append` is
implemented using `cons`. It is important to notice that all the
calls to `append` and `cons` happen in parallel.

`then` allows you to set a function to process the results of the
previous portal once they are available. When both the Millennium
Falcon and the USS Enterprise are found, they can be processed in
`then`. It will also return a new portal containing the
transformations applied to the ships.

When you are working with Continuum, you are chaining portals
together. Once something comes out of the first portal, it will go
through your portal chain and come out transformed from the last
portal in your chain. Another analogy for Continuum is that you are
applying transformation to future values. Applying a transformation to
a portal is essentially equivalent to applying the same transformation
to the value that will come out of the portal sometime in the future.
The portal only stores the transformation until it can be applied to
the value coming out of the portal.

## Extended examples

Let's build on top of the previous example and create a function that
can repair a ship. It needs to find the ship, repair it and put it
back into the fleet. These 3 actions are provided by the `$fleet` API
which is portal-enabled.

```perl
    # Returns a portal
    sub find_and_repair {
        my $ship = shift;
        $fleet->find( $ship )
            ->then( sub { $fleet->repair( shift ) } )
            ->then( sub { $fleet->put( shift ) } );
    }
```

We have a data dependency between the 3 asynchronous operations find,
repair and put. They can not be processed in parallel. We use the
`then` keyword to chain transformations to our data when there are
data dependencies (i.e. we can only repair a ship once we found it). 

There is however no data dependency between repairing two distinct
ships. We can essentially repair them in parallel:

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

You use `cons` to concatenate one value or portal. You use `append`
if you need to append a list of values or portals. 

We could also have implemented the find and repair algorithm
differently, using the `map` function of the portal API:

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

We start by creating a new portal containing all the ships. Then we
map them through 3 portals that finds the ships, repairs them and puts
them back into the fleet. The difference here is that the find, repair
and put steps happen in batch: first we find all the ships in
parallel, then we repair them all in parallel, then we put them back
into the fleet in parallel. In our first example, the find => repair
=> put pipeline was independent for every ship.

## From callbacks to portals

We didn't explain the `portal` keyword yet. It allows us to create a
new portal from scratch. We used it up until now to create an empty
portal when we didn't have a prior portal, to access the portal API.
`portal` is actually much more powerful, as it allows us to create
portals from a chain of arbitrary callbacks. This is very useful when
you need to map a callback-oriented API to a portal API. Let's
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

Portal takes a list of functions as argument. We have a very neat
syntax for you to create portals with function lists using the
`continuum` keyword. In every function, you are either expected to
call `$jump` to go to the next function in the chain, or return a
portal ( or AnyEvent condition variable ) which will trigger the next
function when the results are available. 

The `portal` call will immediately return a portal. The value that
will come out of the portal is the return value of your last function
in the chain. The above example is a trivial one-to-one mapping from a
callback API to a portal call. It is usually more interesting to write
application specific portals from a callback API. We might want to
create a portal that finds all the repair-class ships in our fleet and
command them to repair all the damaged ships. We assume the `$fleet`
API is an asynchronous callback-oriented framework.

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

Now, with this portal function, we have access to the whole portal
API. If we have multiple fleets to repair in parallel, it's simple:

```perl
    repair_fleet( $alpha_fleet )
        ->cons( repair_fleet( $beta_fleet ) )
        ->cons( repair_fleet( $gamma_fleet ) )
        ->then( sub {
            my @ships = @_;
        });
```

## Learn more about Portals

You can write most of your portal code using the techniques described
in this tutorial. There are however a lot more functions available in
the portal API. Feel free to head to the wiki for additional
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
