package Mojo::Promise::Role::Repeat;

# ABSTRACT: Promise looping construct with break

use Mojo::Base -role;

sub repeat {
    my ($self, $body) = (shift, pop);
    unless (ref $self) {
	$self = $self->resolve(@_);
    }
    elsif (@_) {
	my @values = @_;
	$self = $self->then( sub { (@values, @_) });
    }
    my $done_p = $self->clone;
    my $break = sub {
	$done_p->resolve(@_);
	die $self->clone;
	# kills whatever handler we are in,
	# but because the reason is a promise,
	# does not actually reject anything,
	# any promises dependent on that handler remain unsettled,
	# and, because the passed promise is not referenced by anyone else,
	# it will NEVER be settled; that whole line of execution just stops;
        # which is not a problem here because we're skipping ahead and
	# resolving the promise at the "end" of the chain
    };
    my $again_w;
    $again_w = sub {
	 my $again = $again_w;
	 $self = $self->then(
	     sub {
		 my @r;
		 @r = $body->(@_) for ($break);
		 $again->();
		 return @r;
	     }
	 )->catch(
	     sub {
		 $done_p->reject(@_);
	     }
	 );
     };
    $again_w->();
    Scalar::Util::weaken($again_w);
    return $done_p;
};

sub repeat_catch {
    my ($self, $body) = (shift, pop);
    unless (ref $self) {
	$self = $self->reject(@_);
    }
    elsif (@_) {
	my @values = @_;
	$self = $self->catch( sub { (@values, @_) });
    }
    my $done_p = $self->clone;
    my $break = sub {
	$done_p->reject(@_);
	die $self->clone;
	# kill/abandon whatever handler we are in.
	# Same as for repeat()
    };
    my $again_w;
    $again_w = sub {
	my $again = $again_w;
	$self = $self->catch(
	    sub {
		$again->();
		my @r;
		@r = $body->(@_) for ($break);
		return @r;
	    }
	)->then(
	    sub {
		$done_p->resolve(@_);
		die $self->clone;
	    }
	);
    };
    $again_w->();
    Scalar::Util::weaken($again_w);
    return $done_p;
};

1;
__END__

=encoding utf8

=head1 NAME

Mojo::Promise::Role::Repeat - Promise looping construct with break

=head1 SYNOPSIS

  # stupidly complicated while loop
  Mojo::Promise->with_roles('+Repeat')->repeat( 5, sub {
      my $n = shift;
      $_->('yay') unless $n > 0;
      print "($n)";
      return $n-1;
  })->then( sub { print @_; } )->wait
  #
  # (5)(4)(3)(2)(1)yay

  # web treasure hunt pattern
  my @clues;
  $ua->get_p('http://example.com/start_here.html')->with_roles('+Repeat')
  ->repeat( sub {
     my $res = shift->result;
     die $res->message if $res->is_error;
     push @clues, $res->dom->at('#found_clue')->all_text;
     $_->()
       unless my $next_url = $res->dom->at('a#go_here_next')->{href};
     $ua->get_p($next_url)
  })->then( sub {
     # do stuff with @clues
     ...
   },sub {
     # error handling
     ...
  })

=head1 DESCRIPTION

L<Mojo::Promise::Role::Repeat>, a role intended for L<Mojo::Promise> objects, provides a looping construct for control flows involving promises and a "break" function that can escape through arbitrarily many levels of nested loops.

=head1 METHODS

In all of the following

  $class   = Mojo::Promise->with_roles('+Repeat');
  $promise = $class->new;  # or some other promise object of this class

L<Mojo::Promise::Role::Repeat> supplies the following methods to the host object/class:

=head2 repeat

  $done = $class  ->repeat(@initial, sub {...});
  $done = $promise->repeat(@initial, sub {...});

The first form is equivalent to

  $done = $class->resolve(@initial)
          ->then(sub {...})
          ->then(sub {...})
          # ... forever

The second form is equivalent to

  $done = $promise->then( sub { (@initial, @_) } )
          ->then(sub {...})
          ->then(sub {...})
          # ... forever

In both cases, the value returned is effectily the promise generated by the "last" C<then> call, the effect being to invoke the handler (C<sub {...}>) repeatedly, each time passing the values returned from the previous iteration, and with C<$_> bound to a "break" function that, when called, does not return but instead exits the handler, abandons the loop, and resolves that final promise (C<$done>) with the arguments provided.

If the "break" function is invoked with a promise passed as its first argument, the handler and loop are likewise abandoned, and the final promise awaits resolution/rejection of the passed promise.

If any iteration of the handler dies or returns a returns a promise that is rejected, the final promise is likewise rejected.

Note that the "break" function can be used to break out of nested handlers, but since C<$_> is dynamically bound and may change by the time a nested handler runs, it is highly recommended that, for nested handlers, you use a lexical variable to reference this function, e.g.,

    $promise->repeat( sub {
        my $break = $_;
        ...
        $ua->get_p(...)->then( sub {
            ...
            $break->(@result) if (condition...);
            ...
        })->then( sub {
            ...
        })
    })

Note that this method is B<EXPERIMENTAL> and might change without warning.

=head2 repeat_catch

  $done = $class  ->repeat_catch(@initial, sub {...});
  $done = $promise->repeat_catch(@initial, sub {...});

The first form is equivalent to

  $done = $class->reject(@initial)
          ->catch(sub {...})
          ->catch(sub {...})
          # ... forever

The second form is equivalent to

  $done = $promise->catch( sub { (@initial, @_) } )
          ->catch(sub {...})
          ->catch(sub {...})
          # ... forever

In both cases, the value returned is effectily the promise generated by the "last" C<catch> call, the effect being to invoke the handler (C<sub {...}>) repeatedly for as often as it keeps failing, each time passing the (error) values thrown from the previous iteration, and with C<$_> bound to a "break" function that, when called, does not return but instead exits the handler, abandons the loop, and rejects that final promise (C<$done>) with the arguments provided.

If the "break" function is invoked with a promise passed as its first argument, the handler and loop are likewise abandoned, and the final promise awaits resolution/rejection of the passed promise.

If any iteration of the handler returns normally or returns a returns a promise that is resolved, the final promise is likewise resolved with the same values.

Note that this method is B<EXPERIMENTAL> and might change without warning.

=head1 SEE ALSO

L<Mojo::Promise>, L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=head1 AUTHOR

Roger Crew <wrog@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2019 by Roger Crew.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
