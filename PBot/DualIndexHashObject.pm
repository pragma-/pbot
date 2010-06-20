# File: DualIndexHashObject.pm
# Author: pragma_
#
# Purpose: Provides a hash-table object with an abstracted API that includes 
# setting and deleting values, saving to and loading from files, etc.

package PBot::DualIndexHashObject;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = "1.0";

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

  my $name = delete $conf{name};
  if(not defined $name) {
    $name = "dual index hash object";
  }

  my $filename = delete $conf{filename};
  if(not defined $filename) {
    Carp::carp("Missing filename to DualIndexHashObject, will not be able to save to or load from file.");
  }

  $self->{name} = $name;
  $self->{filename} = $filename;
  $self->{hash} = {};
}


sub load_hash_add {
  my ($self, $primary_index_key, $secondary_index_key, $hash, $i, $filename) = @_;

  if(defined $hash) {
    if(exists $self->hash->{$primary_index_key}->{$secondary_index_key}) {
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
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->filename; }

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

      if(exists $self->hash->{$primary_index_key} and $primary_index_key ne '.*') {
        Carp::croak "Duplicate primary_index_key '$primary_index_key' at line $i of $filename\n";
      }

      $self->hash->{$primary_index_key} = {};
      next;
    }

    if($line =~ /^<(.*)>$/) {
      $secondary_index_key = $1;

      if(exists $self->hash->{$primary_index_key}->{$secondary_index_key}) {
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
  my ($self, $primary_index_key, $secondary_index_key) = @_;
  my $result;

  if(not $secondary_index_key) {
    $result = eval {
      foreach my $index (keys %{ $self->hash }) {
        if($primary_index_key =~ m/^\Q$index\E$/i) {
          return $index;
        }
      }

      return undef;
    };

    if($@) {
      Carp::carp ("find_index: bad regex: $@\n");
      return undef;
    }
  } else {
    $result = eval {
      foreach my $index (keys %{ $self->hash->{$primary_index_key} }) {
        if($secondary_index_key =~ m/^\Q$index\E$/i) {
          return $index;
        }
      }

      return undef;
    };

    if($@) {
      Carp::carp ("find_index: bad regex: $@\n");
      return undef;
    }
  }

  return $result;
}

sub levenshtein_matches {
  my ($self, $primary_index_key, $secondary_index_key) = @_;
  my $comma = '';
  my $result = "";

  $primary_index_key = '.*' if not defined $primary_index_key;
  
  if(not $secondary_index_key) {
    foreach my $index (sort keys %{ $self->hash }) {
      my $distance = fastdistance($primary_index_key, $index);
      my $length = (length($primary_index_key) > length($index)) ? length $primary_index_key : length $index;

      if($distance / $length < 0.50) {
        $result .= $comma . $index;
        $comma = ", ";
      }
    }
  } else {
    my $primary = $self->find_index($primary_index_key);

    if(not $primary) {
      return 'none';
    }

    foreach my $index (sort keys %{ $self->hash->{$primary} }) {
      my $distance = fastdistance($secondary_index_key, $index);
      my $length = (length($secondary_index_key) > length($index)) ? length $secondary_index_key : length $index;

      if($distance / $length < 0.50) {
        $result .= $comma . $index;
        $comma = ", ";
      }
    }
  }

  $result =~ s/(.*), /$1 or /;
  $result = 'none'  if $comma eq '';
  return $result;
}

sub set {
  my ($self, $primary_index_key, $secondary_index_key, $key, $value) = @_;

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

  if(not defined $key) {
    my $result = "[$self->{name}] ($primary) $secondary keys: ";
    my $comma = '';
    foreach my $key (sort keys %{ $self->hash->{$primary}->{$secondary} }) {
      $result .= $comma . "$key => " . $self->hash->{$primary}->{$secondary}->{$key};
      $comma = ", ";
    }
    $result .= "none" if($comma eq '');
    return $result;
  }

  if(not defined $value) {
    $value = $self->hash->{$primary}->{$secondary}->{$key};
  } else {
    $self->hash->{$primary}->{$secondary}->{$key} = $value;
    $self->save();
  }

  return "[$self->{name}] ($primary) $secondary: '$key' " . (defined $value ? "set to '$value'" : "is not set.");
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
