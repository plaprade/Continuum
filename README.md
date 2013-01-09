## AnyEventX-CondVar

__! This module is work in progress. The code is likely to change. And
the documentation as well !__

AnyEventX-CondVar is a wrapper module around [AnyEvent](http://search.cpan.org/perldoc?AnyEvent) condition
variables. It's purpose is to provide a clean and readable API for
manipulating condition variables. This is achieved by extending the
[AnyEvent::CondVar](http://search.cpan.org/perldoc?AnyEvent) library with chainable transformations.
It produces code with the following style:

```perl
    ping( 'host1' )->cons( ping( 'host2' ) )
        ->map( sub{ list_files( $_ ) } )
        ->map( sub{ fetch_file( $_ ) } )
        ->grep( sub{ $_->size > 0 } )
        ->then( sub {
            my @files = @_;
            # Work with @files ...
        });
```

Condition variables are promises of delivering results. They are used
in asynchronous frameworks as an alternative to callbacks and for
synchronizing parallel execution flows. I recommend reading the
[AnyEvent](http://search.cpan.org/perldoc?AnyEvent) documentation on condition variables if you are not
already familiar with them.

Returning condition variables from asynchronous API's is generally
more flexible than requiring callbacks as users can decide to block
or not on API calls. The downside of building complex operations with
condition variables is code readability. It's easy to end up with
embedded callback code and spaghetti flows of execution. This library
is an attempt at solving these issues and make asynchronous
programming in Perl fun. I hope you find it useful!

Let's start with an example. Given a list of `@keys`, we want to
retrieve the database values for each key in parallel and return the
result as a `%hash` ( in a condition variable ).  Let's assume we
have access to a database API `$db` that produces AnyEvent (old) and
AnyEventX (new) condition variables. Here is how you would solve this
problem traditionally:

```perl
    use AnyEvent;

    sub get_keys {
        my @keys = @_;

        my %results
        my $cv = AnyEvent->condvar;

        $cv->begin( sub {
            shift->send( %results );
        });

        foreach my $key ( @keys ) { 
            $cv->begin;
            $db->get( $key )->cb( sub {
                results{ $key } = shift->recv;
                cv->end;
            });
        }

        $cv->end;
        $cv;
    }
```

And using the `AnyEventX::CondVar` approach:

```perl
    use AnyEventX::CondVar;

    sub get_keys {
        cv( @_ )->map( sub { 
            $_ => $db->get( $_ )
        });
    }
```

Power comes from conciseness, all other things being equal. The
behavior of the first example is not immediately obvious. It requires
some mental parsing to understand the non-linear execution flow of the
code. The second example has the merit of describing functionality in
a short and effective way. It is also much easier to maintain.

## Design philosophy

We believe that returning condition variables from asynchronous API's
is more powerful than requesting callbacks from users for the
following reasons:

- Your API can be used in a blocking or non-blocking fashion
- You return meaningful values from your asynchronous functions
- You save yourself an argument in your function calls

Building asynchronous APIs then boils down to:

- Performing asynchronous operations ( HTTP, database, file IO, ...  )
- Applying data transformations and
- Returning them through a condition variable.

Our goal is to make the data transformations as clear and effective as
possible. We claim that in most cases, it is not necessary to leave
the realm of condition variables to describe data transformations.  It
is somewhat wasteful to "peek" into condition variables and build
new ones for simple transformations:

```perl
    use AnyEvent;

    sub penguins {
        my $cv = AnyEvent->condvar;

        $db->get( 'zoo_animals' )->cb( sub {
            my @animals = shift->recv;
            $cv->send( grep { $_->type eq 'penguin' } @animals );
        });

        $cv;
    }
```

The above example could be more concisely describe as follows:

```perl
    use AnyEventX::CondVar;

    sub penguins {
        $db->get( 'zoo_animals' )
            ->grep( sub { $_->type eq 'penguin' } );
    }
```

Using the second form saves you from writing a lot of boilerplate code
that can be automatically handled for you. Both examples above are
functionally identical. This example holds for many list
transformations such as `map`, `sort` and `reduce`.

Something else you might be doing a lot when writing asynchronous code
is performing parallel operations with merge-point callbacks:

```perl
    use AnyEvent;

    my $cv = AnyEvent->condvar;

    my ( $roy, $silo );

    $cv->begin;
    $db->get( 'roy' )->cb( sub { 
        $roy = shift->recv; 
        $cv->end; 
    });

    $cv->begin;
    $db->get( 'silo' )->cb( sub { 
        $silo = shift->recv; 
        $cv->end; 
    });

    $cv->cb( sub {
        # Do stuff with roy and silo. Be gentle !
    });
```

We provide two powerful constructs for dealing with this problem:
`cons` and `then` for concatenating condition variables and handling
data dependencies:

```perl
    use AnyEventX::CondVar;

    $db->get( 'roy' )
        ->cons( $db->get( 'silo' ) )
        ->then( sub {
            my ( $roy, $silo ) = @_;
            # Do stuff with roy and silo. Be nice !
        });
```

From the example above, you notice that calls such as `cons` and
`then` can be chained. This holds true for every method in this
library. Every call produces a new condition variable holding the
result of the previous transformation. 

## Continuation style

Continuations are the basic building blocks of asynchronous programs.
In this library, they are provided by the `then` operation. From a
`then` callback, you can return any value which will automatically
become available to the next chained operation: 

```perl
    $db->get( 'a' )
        ->then( sub { a => shift } )
        ->then( sub { my ( $key, $value ) = @_ } );
```

You can also return a condition variable from a `then` callback. The
internal value of the condition variable will be automatically
available to the next chained operation:

```perl
    $db->get( 'a' )
        ->then( sub { $db->get( 'b' ) } )
        ->then( sub { my $b = shift; } );
```

You can return multiple condition variables from a `then` callback.
You can even mix them with regular values. `then` does the right
thing by making the regular values directly available to the next
chained operation, together with the internal values of the condition
variables:

```perl
    $db->get( 'a' )
        ->then( sub { shift, $db->get( 'b' ) } )
        ->then( sub { my ( $a, $b ) = @_ } );
```

This holds for most of the functions in the API. You can use `map` to
transform values into a mix of regular variables and condition
variables and chain it with `then` to fetch all the results:

```perl
    cv( @keys )
        ->map( sub { $_ => $db->get( $_ ) } )
        ->then( sub { my %results = @_ } );
```

`cv` is only a helper function to access the API if you don't have an
initial condition variable. Note that in all of the examples above, we
do not perform any blocking calls. We only describe how the data
should be transformed once it becomes available. 

## More please !

For a complete and exhaustive documentation of the library, head over
to the wiki ! ( TODO ... )

## Bugs

Please report any bugs in the projects bug tracker:

[http://github.com/ciphermonk/AnyEventX-CondVar/issues](http://github.com/ciphermonk/AnyEventX-CondVar/issues)

You can also provide a fix by contributing to the project:

## Contributing

We're glad you want to contribute! It's simple:

- Fork the project
- Create a branch `git checkout -b my_branch`
- Commit your changes `git commit -am 'comments'`
- Push the branch `git push origin my_branch`
- Open a pull request

## Supporting

Like what you see? You can support the project by donating in
[Bitcoins](http://www.weusecoins.com/) to:

__17YWBJUHaiLjZWaCyPwcV8CJDpfoFzc8Gi__

## Copyright and license

Copyright (C) 2012 ciphermonk

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see [http://www.gnu.org/licenses/](http://www.gnu.org/licenses/)
