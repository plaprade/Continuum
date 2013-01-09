= pod 

=head2 AnyEventX-CondVar

B<! This module is work in progress. The code is likely to change. And
the documentation as well !>

AnyEventX-CondVar is a wrapper module around L<AnyEvent> condition
variables. It's purpose is to provide a clean and readable API for
manipulating condition variables. This is achieved by extending the
L<AnyEvent::CondVar|AnyEvent> library with chain-able transformations.

Condition variables are promises of delivering results. They are used
in asynchronous frameworks as an alternative to callbacks and for
synchronizing parallel execution flows. I recommend reading the
L<AnyEvent> documentation on condition variables if you are not
already familiar with them.

Returning condition variables from asynchronous API's is generally
more flexible than requiring callbacks as users can decide to block
or not on API calls. The downside of building complex operations with
condition variables is code readability. It's easy to end up with
embedded callback code and spaghetti flows of execution. This library
is an attempt at solving these issues and make asynchronous
programming in Perl fun. I hope you find it useful!

Let's start with an example. Given a list of C<@keys>, we want to
retrieve the database values for each key in parallel and return the
result as a C<%hash> ( in a condition variable ).  Let's assume we
have access to a database API C<$db> that produces AnyEvent (old) and
AnyEventX (new) condition variables. Here is how you would solve this
problem traditionally:

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

And using the C<AnyEventX::CondVar> approach:

    use AnyEventX::CondVar;

    sub get_keys {
        cv( @_ )->map( sub { 
            $_ => $db->get( $_ )
        });
    }

Power comes from conciseness, all other things being equal. The
behavior of the first example is not immediately obvious. It requires
some mental parsing to understand the non-linear execution flow of the
code. The second example has the merit of describing functionality in
a short and effective way. It is also much easier to maintain.

=head2 Design philosophy

We believe that returning condition variables from asynchronous API's
is more powerful than requesting callbacks from users for the
following reasons:

=over

=item *

Your API can be used in a blocking or non-blocking fashion

=item *

You return meaningful values from your asynchronous functions

=item *

You save yourself an argument in your function calls

=back

Building asynchronous APIs then boils down to:

=over

=item *

Performing asynchronous operations ( HTTP, database, file IO, ...  )

=item *

Applying data transformations and

=item *

Returning them through a condition variable.

=back

Our goal is to make the data transformations as clear and effective as
possible. We claim that in most cases, it is not necessary to leave
the realm of condition variables to describe data transformations.  It
is somewhat wasteful to "peek" into condition variables and build
new ones for simple transformations:

    use AnyEvent;

    sub penguins {
        my $cv = AnyEvent->condvar;

        $db->get( 'zoo_animals' )->cb( sub {
            my @animals = shift->recv;
            $cv->send( grep { $_->type eq 'penguin' } @animals );
        });

        $cv;
    }

The above example could be more concisely describe as follows:

    use AnyEventX::CondVar;

    sub penguins {
        $db->get( 'zoo_animals' )
            ->grep( sub { $_->type eq 'penguin' } );
    }

Using the second form saves you from writing a lot of boilerplate code
that can be automatically handled for you. Both examples above are
functionally identical. This example holds for many list
transformations such as C<map>, C<sort> and C<reduce>.

Something else you might be doing a lot when writing asynchronous code
is performing parallel operations with merge-point callbacks:

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

We provide two powerful constructs for dealing with this problem:
C<cons> and C<then> for concatenating condition variables and handling
data dependencies:

    use AnyEventX::CondVar;

    $db->get( 'roy' )
        ->cons( $db->get( 'silo' ) )
        ->then( sub {
            my ( $roy, $silo ) = @_;
            # Do stuff with roy and silo. Be nice !
        });

From the example above, you notice that calls such as C<cons> and
C<then> can be chained. This holds true for every method in this
library. Every call produces a new condition variable holding the
result of the previous transformation. 

=head2 Continuation style

Continuations are the basic building blocks of asynchronous programs.
In this library, they are provided by the C<then> operation. From a
C<then> callback, you can return any value which will automatically
become available to the next chained operation: 

    $db->get( 'a' )
        ->then( sub { a => shift } )
        ->then( sub { my ( $key, $value ) = @_ } );

You can also return a condition variable from a C<then> callback. The
internal value of the condition variable will be automatically
available to the next chained operation:

    $db->get( 'a' )
        ->then( sub { $db->get( 'b' ) } )
        ->then( sub { my $b = shift; } );

You can return multiple condition variables from a C<then> callback.
You can even mix them with regular values. C<then> does the right
thing by making the regular values directly available to the next
chained operation, together with the internal values of the condition
variables:

    $db->get( 'a' )
        ->then( sub { shift, $db->get( 'b' ) } )
        ->then( sub { my ( $a, $b ) = @_ } );

This holds for most of the functions in the API. You can use C<map> to
transform values into a mix of regular variables and condition
variables and chain it with C<then> to fetch all the results:

    cv( @keys )
        ->map( sub { $_ => $db->get( $_ ) } )
        ->then( sub { my %results = @_ } );

C<cv> is only a helper function to access the API if you don't have an
initial condition variable. Note that in all of the examples above, we
do not perform any blocking calls. We only describe how the data
should be transformed once it becomes available. 

=head2 More please !

For a complete and exhaustive documentation of the library, head over
to the wiki ! ( TODO ... )

=head2 Bugs

Please report any bugs in the projects bug tracker:

L<http://github.com/ciphermonk/AnyEventX-CondVar/issues>

You can also provide a fix by contributing to the project:

=head2 Contributing

We're glad you want to contribute! It's simple:

=over

=item * 
Fork the project

=item *
Create a branch C<git checkout -b my_branch>

=item *
Commit your changes C<git commit -am 'comments'>

=item *
Push the branch C<git push origin my_branch>

=item *
Open a pull request

=back

=head2 Supporting

Like what you see? You can support the project by donating in
L<Bitcoins|http://www.weusecoins.com/> to:

B<17YWBJUHaiLjZWaCyPwcV8CJDpfoFzc8Gi>

=head2 Copyright and license

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
along with this program.  If not, see L<http://www.gnu.org/licenses/>

=cut


