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

use Mojo::Reactor::Poll;
use Mojo::IOLoop;
use Mojolicious::Lite;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use strict;
use JSON;
use Data::Dumper;
use threads;
use Thread::Queue;
use jacks;
use strict;
use warnings;
use Cwd 'abs_path';

#@ARGV = qw(daemon --listen http://*:5000);

my $n = 4096;
my $sizet = 4;
#my $buffer = 

my $queue = Thread::Queue->new();
my %transactions = ();

#my $reactor = Mojo::Reactor::Poll->new;

sub addToBuffer {    
    my $d = $_[0];
    #warn "aTB: ".length($_[0]). " ".$queue->pending;
    $queue->enqueue($d);
  
}

sub readFromBuffer {
    my ($index) = @_;
    my $pending = $queue->pending();
    my $i = $index % $pending;
    # warn "rFB: $index $i ".$pending;
    #return $queue->peek($queue->pending()-1);
    return $queue->peek($i);
}

sub bufferSize {
    return $queue->pending();
}


#foreach my $file (@ARGV) {
#    open(FILE,$file);
#    my $in;
#    while(0!=read(FILE,$in,$sizet*$n)) {
#        push @buffers, $in;
#    }
#    warn scalar(@buffers);
#    close(FILE);
#}
my $thr = threads->create(
    sub {
        my $jc = jacks::JsClient->new("simpler", undef, $jacks::JackNullOption, 0);
        my $in = $jc->registerPort("input", $jacks::JackPortIsInput);
        $jc->activate();
        my $done = undef;

        until($done) {
            
            my $jsevent = $jc->getEvent(-1);

            if ($jsevent->getType() == $jacks::PROCESS) {
                my $inbuffer = $in->getBuffer();
                my $nframes = $inbuffer->length();
                #warn $nframes;
                #my $dbuffer = "XXYY"x($nframes);
                my $dbuffer = "X"x($nframes);
                $inbuffer->dumpBuffer($dbuffer);
                #my $digest = md5_hex($dbuffer);
                my $digest = "";

                addToBuffer($dbuffer);
                #addToBuffer(substr($dbuffer,0,$nframes));
                #warn "$digest -- $nframes ".bufferSize();
            } elsif ($jsevent->getType() == $jacks::SAMPLE_RATE_CHANGE) {
                my $sr = $jc->getSampleRate();
                print("sample rate change event: sample rate is now $sr\n");
            } elsif ($jsevent->getType() == $jacks::SHUTDOWN) {
                print("jack shutdown event\n");
                $done = "done!";
            } elsif ($jsevent->getType() == $jacks::SESSION) {
                my $dir       = $jsevent->getSessionDir();
                my $uuid      = $jsevent->getUuid();
                my $se_type   = $jsevent->getSessionEventType();
                my $setypeTxt = $se_type == $jacks::JackSessionSave ? "save" : "quit";
                warn("session notification: path $dir, uuid $uuid, type: $setypeTxt\n");
                if ($se_type == $jacks::JackSessionSaveAndQuit) {
                    $done = "done!";
                }
                my $script_path = abs_path($0);
                my $cmd = "perl $script_path $uuid"; 
                $jsevent->setCommandLine($cmd); #tell jackd how to restart us
            } else {
                die("unknown event type\n");
            }
            $jsevent->complete();
        }
})->detach();

sub responder {
    my $self = shift;
    my $params = $self->req->params;
    my $x = $params->param('n');
    $self->respond_to(any => {data=>readFromBuffer($x)}, status => 200);
}

get "/stream/" => sub {
    responder(@_);
};

websocket '/ws/' => sub {
    my ($self) = @_;
    # make a queue here and just add to it.
    # when we get something send it.
    $self->on(message => 
              sub {
                  my ($self, $message) = @_;
                  # warn keys %transactions;
                  my $tx = $self->tx;
                  #my $buffSize = bufferSize();
                  #my $last = $transactions{$self->tx} || ($buffSize - 2);
                  #my $x = $last + 1;
                  #if ($buffSize - $x > 25) {
                  #    $x = $buffSize - 1;
                  #}
		  warn $tx;
                  $transactions{$tx} = $self;
                  #my $x = int($message);
                  #warn "WS: [$x] $buffSize";
                  #$self->send( { binary => readFromBuffer($x) } );
              }
    );
    $self->on(finish => sub {
        my ($ws, $code, $reason) = @_;
        my $tx = $ws->tx;
        delete $transactions{$tx};
    });
    my $id = Mojo::IOLoop->recurring( ($n/(2.0*44100.0)) => sub {
        my $pending = $queue->pending();
        while( $pending > 0 ) {
            my $d = $queue->dequeue_nb();
            for my $tx (keys %transactions) {
                warn "send $tx";
		my $t = $transactions{$tx};
                $t->send( { binary => $d } );
            }
            $pending = $queue->pending();
        }
    });

};

app->start();
