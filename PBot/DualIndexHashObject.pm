# File: DualIndexHashObject.pm
# Author: pragma_
#
# Purpose: Provides a hash-table object with an abstracted API that includes
# setting and deleting values, saving to and loading from files, etc.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::DualIndexHashObject;

use warnings;
use strict;

use feature 'unicode_strings';

use Text::Levenshtein qw(fastdistance);
use JSON;
use Carp ();

sub new {
  if (ref($_[1]) eq 'HASH') {
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
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{hash} = {};
}


sub hash_add {
  my ($self, $primary_index_key, $secondary_index_key, $hash) = @_;

  if (defined $hash) {
    if (exists $self->hash->{$primary_index_key}->{$secondary_index_key}) {
      return undef;
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

  if (not defined $filename) {
    Carp::carp "No $self->{name} filename specified -- skipping loading from file";
    return;
  }

  $self->{pbot}->{logger}->log("Loading $self->{name} from $filename ...\n");

  if (not open(FILE, "< $filename")) {
    Carp::carp "Skipping loading from file: Couldn't open $filename: $!\n";
    return;
  }

  my $contents = do {
    local $/;
    <FILE>;
  };

  $self->{hash} = decode_json $contents if length $contents;
  close FILE;
}

sub save {
  my $self = shift;
  my $filename;

  if (@_) { $filename = shift; } else { $filename = $self->filename; }

  if (not defined $filename) {
    Carp::carp "No $self->{name} filename specified -- skipping saving to file.\n";
    return;
  }

  $self->{pbot}->{logger}->log("Saving $self->{name} to $filename\n");

  my $json = JSON->new;
  my $json_text = $json->pretty->canonical->utf8->encode($self->{hash});

  open(FILE, "> $filename") or die "Couldn't open $filename: $!\n";
  print FILE "$json_text\n";
  close FILE;
}

sub clear {
  my $self = shift;
  $self->{hash} = {};
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
  my ($self, $primary_index_key, $secondary_index_key, $distance, $strictnamespace) = @_;
  my $comma = '';
  my $result = "";

  $distance = 0.60 if not defined $distance;

  $primary_index_key = '.*' if not defined $primary_index_key;

  if (not $secondary_index_key) {
    foreach my $index (sort keys %{ $self->hash }) {
      my $distance_result = fastdistance($primary_index_key, $index);
      my $length = (length($primary_index_key) > length($index)) ? length $primary_index_key : length $index;

      if ($distance_result / $length < $distance) {
        if ($index =~ / /) {
          $result .= $comma . "\"$index\"";
        } else {
          $result .= $comma . $index;
        }
        $comma = ", ";
      }
    }
  } else {
    my $primary = $self->find_index($primary_index_key);

    if (not $primary) {
      return 'none';
    }

    my $last_header = "";
    my $header = "";

    foreach my $index1 (sort keys %{ $self->hash }) {
      $header = "[$index1] ";
      $header = "[global channel] " if $header eq "[.*] ";

      if ($strictnamespace) {
        next unless $index1 eq '.*' or $index1 eq $primary;
        $header = "" unless $header eq '[global channel] ';
      }

      foreach my $index2 (sort keys %{ $self->hash->{$index1} }) {
        my $distance_result = fastdistance($secondary_index_key, $index2);
        my $length = (length($secondary_index_key) > length($index2)) ? length $secondary_index_key : length $index2;

        if ($distance_result / $length < $distance) {
          $header = "" if $last_header eq $header;
          $last_header = $header;
          $comma = '; ' if $comma ne '' and $header ne '';
          if ($index2 =~ / /) {
            $result .= $comma . $header . "\"$index2\"";
          } else {
            $result .= $comma . $header . $index2;
          }
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

  if (not $primary) {
    my $result = "No such $self->{name} object [$primary_index_key]; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index_key);
    return $result;
  }

  my $secondary = $self->find_index($primary, $secondary_index_key);

  if (not $secondary) {
    my $secondary_text = $secondary_index_key =~ / / ? "\"$secondary_index_key\"" : $secondary_index_key;
    my $result = "No such $self->{name} object [$primary_index_key] $secondary_text; similiar matches: ";
    $result .= $self->levenshtein_matches($primary, $secondary_index_key);
    return $result;
  }

  if (not defined $key) {
    my $secondary_text = $secondary =~ / / ? "\"$secondary\"" : $secondary;
    my $result = "[" . ($primary eq '.*' ? 'global' : $primary) . "] $secondary_text keys:\n";
    my $comma = '';
    foreach my $key (sort keys %{ $self->hash->{$primary}->{$secondary} }) {
      $result .= $comma . "$key => " . $self->hash->{$primary}->{$secondary}->{$key};
      $comma = ";\n";
    }
    $result .= "none" if ($comma eq '');
    return $result;
  }

  if (not defined $value) {
    $value = $self->hash->{$primary}->{$secondary}->{$key};
  } else {
    $self->hash->{$primary}->{$secondary}->{$key} = $value;
    $self->save unless $dont_save;
  }

  $primary = 'global' if $primary eq '.*';
  $secondary = "\"$secondary\"" if $secondary =~ / /;
  return "[$primary] $secondary: '$key' " . (defined $value ? "set to '$value'" : "is not set.");
}

sub unset {
  my ($self, $primary_index_key, $secondary_index_key, $key) = @_;

  my $primary = $self->find_index($primary_index_key);

  if (not $primary) {
    my $result = "No such $self->{name} object group '$primary_index_key'; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index_key);
    return $result;
  }

  my $secondary = $self->find_index($primary, $secondary_index_key);

  if (not $secondary) {
    my $result = "No such $self->{name} object '$secondary_index_key'; similiar matches: ";
    $result .= $self->levenshtein_matches($primary, $secondary_index_key);
    return $result;
  }

  delete $self->hash->{$primary}->{$secondary}->{$key};
  $self->save();

  $primary = 'global' if $primary eq '.*';
  $secondary = "\"$secondary\"" if $secondary =~ / /;
  return "[$self->{name}] ($primary) $secondary: '$key' unset.";
}

sub add {
  my ($self, $primary_index_key, $secondary_index_key, $hash) = @_;

  if ($self->hash_add($primary_index_key, $secondary_index_key, $hash)) {
    $self->save();
  } else {
    return "Error occurred adding new $self->{name} object.";
  }

  return "'$secondary_index_key' added to $primary_index_key [$self->{name}].";
}

sub remove {
  my ($self, $primary_index_key, $secondary_index_key) = @_;

  my $primary = $self->find_index($primary_index_key);

  if (not $primary) {
    my $result = "No such $self->{name} object group '$primary_index_key'; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index_key);
    return $result;
  }

  if (not $secondary_index_key) {
    delete $self->hash->{$primary};
    $self->save;
    return "'$primary' group removed from $self->{name}.";
  }

  my $secondary = $self->find_index($primary, $secondary_index_key);

  if (not $secondary) {
    my $result = "No such $self->{name} object '$secondary_index_key'; similiar matches: ";
    $result .= $self->levenshtein_matches($primary, $secondary_index_key);
    return $result;
  }

  delete $self->hash->{$primary}->{$secondary};

  # remove primary group if no more secondaries
  if (scalar keys %{ $self->hash->{$primary} } == 0) {
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

  if (@_) { $self->{filename} = shift; }
  return $self->{filename};
}

1;
