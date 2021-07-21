package PBot::Core::IRC::EventQueue::Entry;    # pragma_ 2011/21/01

use strict;

use feature 'unicode_strings';
use utf8;

my $id = 0;

sub new {
    my $class   = shift;
    my $time    = shift;
    my $content = shift;

    my $self = {
        'time'    => $time,
        'content' => $content,
        'id'      => "$time:" . $id++,
    };

    bless $self, $class;
    return $self;
}

sub id {
    my $self = shift;
    return $self->{'id'};
}

sub time {
    my $self = shift;
    $self->{'time'} = $_[0] if @_;
    return $self->{'time'};
}

sub content {
    my $self = shift;
    $self->{'content'} = $_[0] if @_;
    return $self->{'content'};
}

1;

