#!/usr/bin/perl

use v5.14;
use warnings;

use FindBin;
use lib $FindBin::Bin."/lib";

use IO::Async::Loop;

use Net::Async::HTTP::Router;
use Net::Async::HTTP::Server;

use HTTP::Response;

use Future::AsyncAwait;
use Data::Dumper;


my $loop = IO::Async::Loop->new();


my $api_router = Net::Async::HTTP::Router->new();

$api_router->get( "/delete/:id", sub { my ( $req, $next ) = @_; return "Path: ".$req->{path}.": ".Dumper($req->{params}); } );

$api_router->get( qr/(?<TestVerb>test)/i, sub { my ( $req, $next ) = @_; return "Path: ".$req->{path}.": ".Dumper($req->{params}); } );


my $router = Net::Async::HTTP::Router->new();

$router->use( sub { my ( $req, $next ) = @_; print STDERR "New request $req->{path}\n"; &$next(); } );

$router->use( "/api", $api_router->handle() );

$router->get( "/test1", sub { return "Hallo, Welt\n"; } );

$router->get( "/test2", sub { die "Error\n" } );
$router->get( "/test3", sub { my ( $req, $next ) = @_; &$next("next Error\n"); } );
$router->get( "/test4", sub {    
    my $req = shift;
    my $response = HTTP::Response->new( 200 );
    $response->add_content( "Direct sending of HTTP::Response instance\n".$req->{path}."\n" );
    $response->content_type( "text/plain" );
    $response->content_length( length $response->content );
    $req->respond( $response );
} );
$router->get( "/test5", async sub { return "async => Hallo, Welt\n"; } );

$router->get( "/test6", async sub {
    my $req = shift;
    await $req->stream->loop->delay_future( after => 3 );    
    return "async, wait 3s => Hallo, Welt\n";
} );

$router->get( "/test7", async sub {
    my $req = shift;
    await $req->stream->loop->timeout_future( after => 3 );    
    return "This will never get returned\n";
} );

my $httpserver = Net::Async::HTTP::Server->new( on_request => $router->handle() );

$loop->add( $httpserver );

$httpserver->listen(
   addr => {
      family   => "inet6",
      socktype => "stream",
      port     => 8080,
   },
   on_listen_error => sub { die "Cannot listen - $_[-1]\n" },
);

my $sockhost = $httpserver->read_handle->sockhost;
$sockhost = "[$sockhost]" if $sockhost =~ m/:/; # IPv6 numerical

printf "Listening on %s://%s:%d\n", ( "http" ), $sockhost, $httpserver->read_handle->sockport;

$loop->run;

