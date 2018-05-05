# File: HashObject.pm
# Author: pragma_
#
# Purpose: Provides a hash-table object with an abstracted API that includes 
# setting and deleting values, saving to and loading from files, etc.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::HashObject;

use warnings;
use strict;

use Text::Levenshtein qw(fastdistance);
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to HashObject should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{name} = delete $conf{name} // 'hash object';
  $self->{filename}  = delete $conf{filename} // Carp::carp("Missing filename to HashObject, will not be able to save to or load from file.");
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to HashObject");
  $self->{hash} = {};
}

sub load_hash_add {
  my ($self, $index_key, $hash, $i, $filename) = @_;

  if(defined $hash) {
    if(exists $self->hash->{$index_key}) {
      if($i) {
        Carp::croak "Duplicate hash '$index_key' found in $filename around line $i\n";
      } else {
        return undef;
      }
    }

    foreach my $key (keys %$hash) {
      $self->hash->{$index_key}{$key} = $hash->{$key};
    }
    return 1;
  }
  return undef;
}

sub load {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->filename; }

  if(not defined $filename) {
    Carp::carp "No $self->{name} filename specified -- skipping loading from file";
    return;
  }

  $self->{pbot}->{logger}->log("Loading $self->{name} objects from $filename ...\n");

  if(not open(FILE, "< $filename")) {
    Carp::carp "Couldn't open $filename: $!\n";
    Carp::carp "Skipping loading from file.\n";
    return;
  }

  my ($hash, $index_key, $i);
  $hash = {};

  foreach my $line (<FILE>) {
    $i++;

    $line =~ s/^\s+//;
    $line =~ s/\s+$//;

    if($line =~ /^\[(.*)\]$/) {
      $index_key = $1;
      next;
    }

    if($line eq '') {
      # store the old hash
      $self->load_hash_add($index_key, $hash, $i, $filename);

      # start a new hash
      $hash = {};
      next;
    }

    my ($key, $value) = split /\:/, $line, 2;

    if(not defined $key or not defined $value) {
      Carp::croak "Error around line $i of $filename\n";
    }

    $key =~ s/^\s+//;
    $key =~ s/\s+$//;
    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    $hash->{$key} = $value;
  }

  close(FILE);

  $self->{pbot}->{logger}->log("Done.\n");
}

sub save {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->filename; }

  if(not defined $filename) {
    Carp::carp "No $self->{name} filename specified -- skipping saving to file.\n";
    return;
  }

  open(FILE, "> $filename") or die "Couldn't open $filename: $!\n";

  foreach my $index (sort keys %{ $self->hash }) {
    print FILE "[$index]\n";

    foreach my $key (sort keys %{ ${ $self->hash }{$index} }) {
      print FILE "$key: ${ $self->hash }{$index}{$key}\n";
    }
    print FILE "\n";
  }
  close(FILE);
}

sub clear {
  my $self = shift;
  $self->{hash} = {};
}

sub find_hash {
  my ($self, $keyword, $arguments) = @_;

  my $string = "$keyword" . (defined $arguments ? " $arguments" : "");

  my $result = eval {
    foreach my $index (keys %{ $self->hash }) {
      if($keyword =~ m/^\Q$index\E$/i) {
        return $index;
      }
    }

    return undef;
  };

  if($@) {
    $self->{pbot}->{logger}->log("find_hash: bad regex: $@\n");
    return undef;
  }

  return $result;
}

sub levenshtein_matches {
  my ($self, $keyword, $distance) = @_;
  my $comma = '';
  my $result = "";

  $distance = 0.60 if not defined $distance;
  
  foreach my $index (sort keys %{ $self->hash }) {
    my $fast_distance = fastdistance($keyword, $index);

    # print "Distance $distance for $keyword (" , (length $keyword) , ") vs $index (" , length $index , ")\n";
    
    my $length = (length($keyword) > length($index)) ? length $keyword : length $index;

    # print "Percentage: ", $distance / $length, "\n";

    if($length != 0 && $fast_distance / $length < $distance) {
      $result .= $comma . $index;
      $comma = ", ";
    }
  }

  $result =~ s/(.*), /$1 or /;
  $result = "none"  if $comma eq '';
  return $result;
}

sub set {
  my ($self, $index, $key, $value) = @_;

  my $hash_index = $self->find_hash($index);

  if(not $hash_index) {
    my $result = "No such $self->{name} object '$index'; similiar matches: ";
    $result .= $self->levenshtein_matches($index);
    return $result;
  }

  if(not defined $key) {
    my $result = "[$self->{name}] $hash_index keys: ";
    my $comma = '';
    foreach my $k (sort keys %{ $self->hash->{$hash_index} }) {
      $result .= $comma . "$k => " . $self->hash->{$hash_index}{$k};
      $comma = "; ";
    }
    $result .= "none" if($comma eq '');
    return $result;
  }

  if(not defined $value) {
    $value = $self->hash->{$hash_index}{$key};
  } else {
    $self->hash->{$hash_index}{$key} = $value;
    $self->save();
  }

  return "[$self->{name}] $hash_index: '$key' " . (defined $value ? "set to '$value'" : "is not set.");
}

sub unset {
  my ($self, $index, $key) = @_;

  my $hash_index = $self->find_hash($index);

  if(not $hash_index) {
    my $result = "No such $self->{name} object '$index'; similiar matches: ";
    $result .= $self->levenshtein_matches($index);
    return $result;
  }

  delete $self->hash->{$hash_index}{$key};
  $self->save();

  return "[$self->{name}] $hash_index: '$key' unset.";
}

sub add {
  my ($self, $index_key, $hash) = @_;

  if($self->load_hash_add($index_key, $hash, 0)) {
    $self->save();
  } else {
    return "Error occurred adding new $self->{name} object.";
  }

  return "'$index_key' added to $self->{name}.";
}

sub remove {
  my ($self, $index) = @_;

  my $hash_index = $self->find_hash($index);

  if(not $hash_index) {
    my $result = "No such $self->{name} object '$index'; similiar matches: ";
    $result .= $self->levenshtein_matches($index);
    return $result;
  }

  delete $self->hash->{$hash_index};
  $self->save();

  return "'$hash_index' removed from $self->{name}.";
}

# Getters and setters

sub hash {
  my $self = shift;
  return $self->{hash};
}

sub filename {
  my $self = shift;

  if(@_) { $self->{filename} = shift; }
  return $self->{filename};
}

1;
