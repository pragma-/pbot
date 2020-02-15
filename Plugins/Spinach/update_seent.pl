#!/usr/bin/perl

use warnings;
use strict;

use JSON;
use Time::Piece;

my $self = {};

sub load_questions {
    my ($filename) = @_;

    if (not defined $filename) { $filename = $ENV{HOME} . "/pbot/data/spinach/trivia.json"; }

    $self->{loaded_filename} = $filename;

    my $contents = do {
        open my $fh, '<', $filename or do {
            print "Spinach: Failed to open $filename: $!\n";
            return "Failed to load $filename";
        };
        local $/;
        <$fh>;
    };

    $self->{questions}  = decode_json $contents;
    $self->{categories} = ();

    my $questions;
    foreach my $key (keys %{$self->{questions}}) {
        foreach my $question (@{$self->{questions}->{$key}}) {
            $question->{category} = uc $question->{category};
            $self->{categories}{$question->{category}}{$question->{id}} = $question;

            if (not exists $question->{seen_timestamp}) { $question->{seen_timestamp} = 0; }

            $questions++;
        }
    }

    my $categories;
    foreach my $category (sort { keys %{$self->{categories}{$b}} <=> keys %{$self->{categories}{$a}} } keys %{$self->{categories}}) {
        my $count = keys %{$self->{categories}{$category}};
        print "Category [$category]: $count\n";
        $categories++;
    }

    print "Spinach: Loaded $questions questions in $categories categories.\n";
    return "Loaded $questions questions in $categories categories.";
}

sub save_questions {
    my $json     = encode_json $self->{questions};
    my $filename = exists $self->{loaded_filename} ? $self->{loaded_filename} : $self->{questions_filename};
    open my $fh, '>', $filename or do {
        print "Failed to open Spinach file $filename: $!\n";
        return;
    };
    print $fh "$json\n";
    close $fh;
}

load_questions;

open my $fh, '<', 'seent' or do {
    print "Failed to open seent file: $!\n";
    die;
};

my $nr = 0;

foreach my $line (<$fh>) {
    ++$nr;
    my ($date, $id) = $line =~ m/^(.*?) :: .*? question:.*?\s(\d+,?\d*)\)/;

    if (not defined $date or not defined $id) {
        print "Parse error at line $nr\n";
        die;
    }

    $id =~ s/,//g;

    print "matched [$date] and [$id]\n";

    my $time = Time::Piece->strptime($date, "%a %b %e %H:%M:%S %Y");
    print "epoch: ", $time->epoch, "\n";

    foreach my $q (@{$self->{questions}->{questions}}) {
        if ($q->{id} == $id) {
            print "question: $q->{question}\n";
            $q->{seen_timestamp} = $time->epoch;
            last;
        }
    }
}

close $fh;

save_questions;
