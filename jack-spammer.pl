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
use Mojolicious::Lite;

use strict;
use JSON;
use Data::Dumper;
use threads;
use Thread::Queue;
use jacks;
use strict;
use warnings;
use Cwd 'abs_path';


my $n = 2048;
my $sizet = 4;
#my $buffer = 

my $queue = Thread::Queue->new();

sub addToBuffer {    
    warn "aTB: ".length($_[0]). " ".$queue->pending;
    $queue->enqueue($_[0]);
}

sub readFromBuffer {
    my ($index) = @_;
    my $i = $index % $queue->pending();
    warn "rFB: $index $i";
    return $queue->peek($queue->pending()-1);
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
                warn $nframes;
                my $dbuffer = "XXYY"x($nframes);
                $inbuffer->dumpBuffer($dbuffer);
                addToBuffer($dbuffer);
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
    $self->on(message => 
              sub {
                  my ($self, $message) = @_;
                  my $x = int($message);
                  warn "WS: [$x]";
                  $self->send( { binary => readFromBuffer($x) } );
              }
    );
};

app->start;