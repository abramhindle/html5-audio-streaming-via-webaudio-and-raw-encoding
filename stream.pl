#!/usr/bin/env perl
# Copyright (C) 2013 Abram Hindle
#
# This program is free software, you can redistribute it and/or modify it
# under the terms of the Artistic License version 2.0.
#
# Stupidly stream raw audio over XHTTPRequest
#
# To start this webservice just run:
#   hypnotoad -f stream.pl rawfile.raw
# or
#   perl stream.pl daemon rawfile.raw
# 


use Mojolicious::Lite;
use strict;
use JSON;
use Data::Dumper;
#my $n = 4096;
my $n = 2048;
my $sizet = 4;
my @buffers = ();
foreach my $file (@ARGV) {
    open(FILE,$file);
    my $in;
    while(0!=read(FILE,$in,$sizet*$n)) {
        push @buffers, $in;
    }
    warn scalar(@buffers);
    close(FILE);
}


sub responder {
    my $self = shift;
    my $params = $self->req->params;
    my $x = $params->param('n');
    warn $x;
    $x = $x % scalar(@buffers);
    $self->respond_to(any => {data=>$buffers[$x]}, status => 200);
}

get "/stream/" => sub {
    responder(@_);
};

websocket '/ws/' => sub {
    my ($self) = @_;
    $self->on(message => 
              sub {
                  my ($self, $message) = @_;
                  my $x = int($message);
                  #$x =~ s/\s+//g;
                  $x = $x % scalar(@buffers);
                  warn "WS: [$x]";
                  #$self->send( { data => $buffers[$x] } );
                  eval {
                      #$self->respond_to( { binary => $buffers[$x] } );
                      $self->send( { binary => $buffers[$x] } );
                      #warn "SENT";
                  };
                  if ($@) { warn $@ };
              }
    );
};

app->start;
