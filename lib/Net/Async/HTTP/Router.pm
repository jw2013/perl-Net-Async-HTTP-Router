package Net::Async::HTTP::Router;

use v5.14;
use strict;
use warnings;

use Carp;

use Net::Async::HTTP::Router::Route;
use Net::Async::HTTP::Server::Request;
use HTTP::Request;
use HTTP::Response;
use Net::Async::HTTP::Server::Protocol;


=encoding utf8

=head1 NAME

C<Net::Async::HTTP::Router> - Router for C<Net::Async::HTTP::Server::Request>, exposing an API similar to C<express.js>.

=cut


sub new
{
   my $class = shift;
   my ( ) = @_;

   return bless {
      routes => [],
   }, $class;
}


sub handle {
    my $self = shift;

    if ( !@_ ) {
        my $callback = sub {
            # Remove first parameters from call, if not instance of Request
            while ( @_ && (ref $_[0]) && !($_[0]->isa("Net::Async::HTTP::Server::Request")) ) {
                shift @_;
            }
            $self->handle(@_) if @_;
        };
        return $callback;
    }

    my $req = shift;
    my $parent_next = shift;

    $req->{path} = $req->path() if !exists $req->{path};

    my $path = $req->{path};
    my $new_path = undef;

    my $method = lc $req->method();
    my $route_index = 0;
    my $stack_index = -1;

    my $next;
    my $finish;

    $finish = sub {
        my @r = @_;

        if ( @r == 2 ) {
            my ( $content_type, $content ) = @r;
            $req->respond( _text_response(200, $content, $content_type) ) unless $req->{is_done};
            return;
        }
        my ( $response ) = @r;

        return unless defined $response;
        return unless length $response;

        if ( !ref $response ) {
            $req->respond( _text_response(200, $response) ) unless $req->{is_done};
            return;
        }

        if ( $response->isa("HTTP::Response") ) {
            $req->respond( $response ) unless $req->{is_done};
            return;
        }

        if ( $response->isa("Future") ) {
            $req->stream()->adopt_future($response->on_done($finish)->on_fail($next)->else_done());
            return;
        }
    };

    $next = sub {
        my $err = shift;

        if ( (defined $err) && ($err eq "route") ) {
            $route_index++;
            $stack_index = -1;
        }
        if ( (defined $err) && ($err eq "router") ) {
            $route_index = scalar(@{$self->{routes}});
            $stack_index = -1;
        }
        elsif ( defined $err ) {
            $req->respond( _text_response(500, $err) ) unless $req->{is_done};
        }

        $stack_index++;

        my $callback = undef;
        my $use_new_path = undef;

        while ( exists $self->{routes}[$route_index] ) {
            my $route = $self->{routes}[$route_index];
            if ( !$stack_index ) {
                my $m = $route->check($path);
                unless ( $m ) {
                    $route_index++;
                    next;
                }
                $req->{params} = $m->{params};
                $new_path = substr($path, length($m->{path}));
            }

            while ( exists $route->{stack}[$stack_index] ) {
                my $handler = $route->{stack}[$stack_index];
                if ( $handler->[0] eq 'use' ) {
                    $use_new_path = 1;
                }
                elsif ( ($handler->[0] ne 'all') && ($handler->[0] ne $method) ) {
                    $stack_index++;
                    next;
                }
                $callback = $handler->[1];
                last;
            }
            if ( !exists $route->{stack}[$stack_index] ) {
                $route_index++;
                $stack_index = 0;
            }
            else {
                $stack_index++;
                last;
            }
        }

        if ( !defined $callback ) {
            if ( $parent_next ) {
                &$parent_next();
            }
            else {
                $req->respond( _text_response(404, "No matching route found!\n") ) unless $req->{is_done};
            }
            return;
        }

        my @r = eval {
            $req->{path} = $new_path if $use_new_path && defined $new_path;
            return &$callback($req, $next);
        };
        $req->{path} = $path if $use_new_path && defined $new_path;
        if ( $@ ) {
            $req->respond( _text_response(500, $@) ) unless $req->{is_done};
            return;
        }
        &$finish(@r);
        return;
    };

    &$next();
}


sub use    { return __route_by_method( "use", { end => 0, trailing => 0 }, @_ ); }
sub all    { return __route_by_method( "all",    @_ ); }
sub get    { return __route_by_method( "get",    @_ ); }
sub head   { return __route_by_method( "head",   @_ ); }
sub post   { return __route_by_method( "post",   @_ ); }
sub put    { return __route_by_method( "put",    @_ ); }
sub delete { return __route_by_method( "delete", @_ ); }
# connect
# options
# trace
# patch


sub route {
    my $self = shift;
    my $path = shift;
    my $options = shift;
    my $route = Net::Async::HTTP::Router::Route->new($path, $options);
    push @{$self->{routes}}, $route;
    return $route;
}


sub __route_by_method {
    my $method = shift;
    my $options = {};
    while ( @_ && (ref $_[0] eq "HASH") ) {
        $options = {%$options, %{shift @_}};
    }
    my $self = shift;
    my $path = !ref $_[0] ? shift @_ : ref $_[0] eq "Regexp" ? shift @_ : undef;
    return $self->route($path, $options)->add_handlers($method, @_);
}


sub _text_response {
    my $code = shift;
    my $content = shift;
    my $content_type = shift || "text/plain";
    my $response = HTTP::Response->new( $code );
    $response->add_content( $content );
    $response->content_type( $content_type );
    $response->content_length( length $response->content );
    return $response;
}


0x55AA;
