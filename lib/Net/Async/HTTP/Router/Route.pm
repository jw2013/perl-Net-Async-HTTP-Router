package Net::Async::HTTP::Router::Route;

use v5.14;
use strict;
use warnings;

use Carp;

use Regexp::PathToRegexp qw(match);


sub new
{
    my $class = shift;
    my ( $pattern, $options ) = @_;

    my $check = undef;

    if ( !defined $pattern ) {
    }
    elsif ( ref($pattern) eq "Regexp" ) {
        $check = $pattern;
    }
    else {
        $check = match($pattern, $options)
            or croak "Pattern invalid: $pattern";
    }

    return bless {
        check => $check,
        stack => [],
        methods => {}
    }, $class;
}

sub check {
    my $self = shift;
    my $fn = $self->{check};
    return { path => '', params => {} } if !defined $self->{check};

    if ( ref($self->{check}) eq "Regexp" ) {
        return undef unless $_[0] =~ $self->{check};
        my $params = {};
        for ( my $i = 0; $i < @{^CAPTURE}; $i++ ) {
            $params->{$i} = ${^CAPTURE}[$i];
        }
        foreach my $key ( keys %+ ) {
            $params->{$key} = $+{$key};
        }
        return { path => '', params => $params };
    }

    return &$fn(@_);
}


sub add_handlers {
    my $self = shift;
    my $method = shift;
    my @handlers = shift;
    @handlers = _flatten(@handlers);
    foreach my $handler ( @handlers ) {
        push @{$self->{stack}}, [$method, $handler];
    }
    return $self;
}

sub all    { return __handlers_by_method("all",    @_); }
sub get    { return __handlers_by_method("get",    @_); }
sub head   { return __handlers_by_method("head",   @_); }
sub post   { return __handlers_by_method("post",   @_); }
sub put    { return __handlers_by_method("put",    @_); }
sub delete { return __handlers_by_method("delete", @_); }
# connect
# options
# trace
# patch

sub _flatten {
    return map { ref eq 'ARRAY' ? _flatten(@$_) : $_ } @_;
}

sub __handlers_by_method {
    my $method = shift;
    my $self = shift;
    return $self->add_handlers($method, @_);
}

0x55AA;
