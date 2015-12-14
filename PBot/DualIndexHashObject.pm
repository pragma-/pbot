# File: DualIndexHashObject.pm
# Author: pragma_
#
# Purpose: Provides a hash-table object with an abstracted API that includes 
# setting and deleting values, saving to and loading from files, etc.

package PBot::DualIndexHashObject;

use warnings;
use strict;

use Text::Levenshtein qw(fastdistance);
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to DualIndexHashObject should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{name}     = delete $conf{name} // 'Dual Index hash object';
  $self->{filename} = delete $conf{filename} // Carp::carp("Missing filename to DualIndexHashObject, will not be able to save to or load from file.");
  $self->{ignore_duplicates} = delete $conf{ignore_duplicates} // 0;
  $self->{hash} = {};
}


sub load_hash_add {
  my ($self, $primary_index_key, $secondary_index_key, $hash, $i, $filename) = @_;

  if(defined $hash) {
    if(not $self->{ignore_duplicates} and exists $self->hash->{$primary_index_key}->{$secondary_index_key}) {
      if($i) {
        Carp::croak "Duplicate secondary_index_key '$secondary_index_key' found in $filename around line $i\n";
      } else {
        return undef;
      }
    }

    foreach my $key (keys %$hash) {
      $self->hash->{$primary_index_key}->{$secondary_index_key}->{$key} = $hash->{$key};
    }
    return 1;
  }
  return undef;
}

sub load {
  my ($self, $filename) = @_;

  $filename = $self->filename if not defined $filename;

  if(not defined $filename) {
    Carp::carp "No $self->{name} filename specified -- skipping loading from file";
    return;
  }

  if(not open(FILE, "< $filename")) {
    Carp::carp "Skipping loading from file: Couldn't open $filename: $!\n";
    return;
  }

  my ($primary_index_key, $secondary_index_key, $i, $hash);
  $hash = {};

  foreach my $line (<FILE>) {
    $i++;

    $line =~ s/^\s+//;
    $line =~ s/\s+$//;

    if($line =~ /^\[(.*)\]$/) {
      $primary_index_key = $1;
      next;
    }

    if($line =~ /^<(.*)>$/) {
      $secondary_index_key = $1;

      if(not $self->{ignore_duplicates} and exists $self->hash->{$primary_index_key}->{$secondary_index_key}) {
        Carp::croak "Duplicate secondary_index_key '$secondary_index_key' at line $i of $filename\n";
      }

      next;
    }

    if($line eq '') {
      # store the old hash
      $self->load_hash_add($primary_index_key, $secondary_index_key, $hash, $i, $filename);

      # start a new hash
      $hash = {};
      next;
    }

    my ($key, $value) = split /:/, $line, 2;

    $key =~ s/^\s+//;
    $key =~ s/\s+$//;
    $value =~ s/^\s+//;
    $value =~ s/\s+$//;

    if(not length $key or not length $value) {
      Carp::croak "Missing key or value at line $i of $filename\n";
    }

    $hash->{$key} = $value;
  }

  close(FILE);
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

  foreach my $primary_index_key (sort keys %{ $self->hash }) {
    print FILE "[$primary_index_key]\n";

    foreach my $secondary_index_key (sort keys %{ $self->hash->{$primary_index_key} }) {
      print FILE "<$secondary_index_key>\n";

      foreach my $key (sort keys %{ $self->hash->{$primary_index_key}->{$secondary_index_key} }) {
        print FILE "$key: " . $self->hash->{$primary_index_key}->{$secondary_index_key}{$key} . "\n";
      }
      print FILE "\n";
    }
  }

  close FILE;
}

sub find_index {
  my $self = shift;
  my ($primary_index_key, $secondary_index_key) = map {lc} @_;

  return undef if not defined $primary_index_key;

  return undef if not exists $self->hash->{$primary_index_key};

  return $primary_index_key if not defined $secondary_index_key;

  foreach my $index (keys %{ $self->hash->{$primary_index_key} }) {
    return $index if $secondary_index_key eq lc $index;
  }

  return undef;
}

sub levenshtein_matches {
  my ($self, $primary_index_key, $secondary_index_key, $distance) = @_;
  my $comma = '';
  my $result = "";

  $distance = 0.60 if not defined $distance;

  $primary_index_key = '.*' if not defined $primary_index_key;
  
  if(not $secondary_index_key) {
    foreach my $index (sort keys %{ $self->hash }) {
      my $distance_result = fastdistance($primary_index_key, $index);
      my $length = (length($primary_index_key) > length($index)) ? length $primary_index_key : length $index;

      if($distance_result / $length < $distance) {
        $result .= $comma . $index;
        $comma = ", ";
      }
    }
  } else {
    my $primary = $self->find_index($primary_index_key);

    if(not $primary) {
      return 'none';
    }

    my $last_header = "";
    my $header = "";

    foreach my $index1 (sort keys %{ $self->hash }) {
      $header = "[$index1] ";
      $header = "[global channel] " if $header eq "[.*] ";

      foreach my $index2 (sort keys %{ $self->hash->{$index1} }) {
        my $distance_result = fastdistance($secondary_index_key, $index2);
        my $length = (length($secondary_index_key) > length($index2)) ? length $secondary_index_key : length $index2;

        if($distance_result / $length < $distance) {
          $header = "" if $last_header eq $header;
          $last_header = $header;
          $result .= $comma . $header . $index2;
          $comma = ", ";
        }
      }
    }
  }

  $result =~ s/(.*), /$1 or /;
  $result = 'none'  if $comma eq '';
  return $result;
}

sub set {
  my ($self, $primary_index_key, $secondary_index_key, $key, $value, $dont_save) = @_;

  my $primary = $self->find_index($primary_index_key);

  if(not $primary) {
    my $result = "No such $self->{name} object [$primary_index_key]; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index_key);
    return $result;
  }

  my $secondary = $self->find_index($primary, $secondary_index_key);

  if(not $secondary) {
    my $result = "No such $self->{name} object [$primary_index_key] $secondary_index_key; similiar matches: ";
    $result .= $self->levenshtein_matches($primary, $secondary_index_key);
    return $result;
  }

  if(not defined $key) {
    my $result = "[" . ($primary eq '.*' ? 'global' : $primary) . "] $secondary keys:\n";
    my $comma = '';
    foreach my $key (sort keys %{ $self->hash->{$primary}->{$secondary} }) {
      $result .= $comma . "$key => " . $self->hash->{$primary}->{$secondary}->{$key};
      $comma = ";\n";
    }
    $result .= "none" if($comma eq '');
    return $result;
  }

  if(not defined $value) {
    $value = $self->hash->{$primary}->{$secondary}->{$key};
  } else {
    $self->hash->{$primary}->{$secondary}->{$key} = $value;
    $self->save unless $dont_save;
  }

  $primary = 'global' if $primary eq '.*';
  return "[$primary] $secondary: '$key' " . (defined $value ? "set to '$value'" : "is not set.");
}

sub unset {
  my ($self, $primary_index_key, $secondary_index_key, $key) = @_;

  my $primary = $self->find_index($primary_index_key);

  if(not $primary) {
    my $result = "No such $self->{name} object group '$primary_index_key'; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index_key);
    return $result;
  }

  my $secondary = $self->find_index($primary, $secondary_index_key);

  if(not $secondary) {
    my $result = "No such $self->{name} object '$secondary_index_key'; similiar matches: ";
    $result .= $self->levenshtein_matches($primary, $secondary_index_key);
    return $result;
  }

  delete $self->hash->{$primary}->{$secondary}->{$key};
  $self->save();

  $primary = 'global' if $primary eq '.*';
  return "[$self->{name}] ($primary) $secondary: '$key' unset.";
}

sub add {
  my ($self, $primary_index_key, $secondary_index_key, $hash) = @_;

  if($self->load_hash_add($primary_index_key, $secondary_index_key, $hash, 0)) {
    $self->save();
  } else {
    return "Error occurred adding new $self->{name} object.";
  }

  return "'$secondary_index_key' added to $primary_index_key [$self->{name}].";
}

sub remove {
  my ($self, $primary_index_key, $secondary_index_key) = @_;

  my $primary = $self->find_index($primary_index_key);

  if(not $primary) {
    my $result = "No such $self->{name} object group '$primary_index_key'; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index_key);
    return $result;
  }

  if(not $secondary_index_key) {
    delete $self->hash->{$primary};
    $self->save;
    return "'$primary' group removed from $self->{name}.";
  }

  my $secondary = $self->find_index($primary, $secondary_index_key);

  if(not $secondary) {
    my $result = "No such $self->{name} object '$secondary_index_key'; similiar matches: ";
    $result .= $self->levenshtein_matches($primary, $secondary_index_key);
    return $result;
  }

  delete $self->hash->{$primary}->{$secondary};

  # remove primary group if no more secondaries
  if(scalar keys $self->hash->{$primary} == 0) {
      delete $self->hash->{$primary};
  }

  $self->save();
  return "'$secondary' removed from $primary group [$self->{name}].";
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
