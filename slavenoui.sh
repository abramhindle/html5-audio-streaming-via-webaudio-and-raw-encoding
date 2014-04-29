#!/bin/sh
(sleep 2; jack_connect csoundGrain:output1 net_pcm:playback_1) &
csound grainnoui.csd

