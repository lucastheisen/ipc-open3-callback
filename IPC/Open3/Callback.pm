#!/usr/bin/perl

package IPC::Open3::Callback;

use strict;
use warnings;

use IPC::Open3;

sub new {
    my $prototype = shift;
    my $class = ref( $prototype ) || $prototype;
    my $self = {};
    bless( $self, $class );

    return $self;
}

sub toString() {
    return "Hello world!";
}

1;
