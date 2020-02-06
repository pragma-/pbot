# File: DualIndexHashObject.pm
# Author: pragma_
#
# Purpose: Provides a hash-table object with an abstracted API that includes
# setting and deleting values, saving to and loading from files, etc. This
# extends the HashObject with an additional index key. Provides case-insensitive
# access to both index keys, while preserving original case when displaying the
# keys.

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
  Carp::croak("Options to DualIndexHashObject should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{name}     = $conf{name} // 'Dual Index hash object';
  $self->{filename} = $conf{filename} // Carp::carp("Missing filename to DualIndexHashObject, will not be able to save to or load from file.");
  $self->{pbot}     = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{hash}     = {};
}

sub load {
  my ($self, $filename) = @_;
  $filename = $self->{filename} if not defined $filename;

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

  # update existing entries to use _name to preserve case
  # and lowercase any non-lowercased entries
  foreach my $primary_index (keys %{ $self->{hash} }) {
    if (not exists $self->{hash}->{$primary_index}->{_name}) {
      if (lc $primary_index eq $primary_index) {
        $self->{hash}->{$primary_index}->{_name} = $primary_index;
      } else {
        if (exists $self->{hash}->{lc $primary_index}) {
          Carp::croak "Cannot update $self->{name} primary index $primary_index; duplicate object found";
        }

        my $data = delete $self->{hash}->{$primary_index};
        $data->{_name} = $primary_index;
        $primary_index = lc $primary_index;
        $self->{hash}->{$primary_index} = $data;
      }
    }

    foreach my $secondary_index (keys %{ $self->{hash}->{$primary_index} }) {
      next if $secondary_index eq '_name';
      if (not exists $self->{hash}->{$primary_index}->{$secondary_index}->{_name}) {
        if (lc $secondary_index eq $secondary_index) {
          $self->{hash}->{$primary_index}->{$secondary_index}->{_name} = $secondary_index;
        } else {
          if (exists $self->{hash}->{$primary_index}->{lc $secondary_index}) {
            Carp::croak "Cannot update $self->{name} $primary_index sub-object $secondary_index; duplicate object found";
          }

          my $data = delete $self->{hash}->{$primary_index}->{$secondary_index};
          $data->{_name} = $secondary_index;
          $secondary_index = lc $secondary_index;
          $self->{hash}->{$primary_index}->{$secondary_index} = $data;
        }
      }
    }
  }
}

sub save {
  my $self = shift;
  my $filename;
  if (@_) { $filename = shift; } else { $filename = $self->{filename}; }

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

sub levenshtein_matches {
  my ($self, $primary_index, $secondary_index, $distance, $strictnamespace) = @_;
  my $comma = '';
  my $result = "";

  $distance = 0.60 if not defined $distance;

  $primary_index = '.*' if not defined $primary_index;

  if (not $secondary_index) {
    foreach my $index (sort keys %{ $self->{hash} }) {
      my $distance_result = fastdistance($primary_index, $index);
      my $length = (length $primary_index > length $index) ? length $primary_index : length $index;

      if ($distance_result / $length < $distance) {
        my $name = $self->{hash}->{$index}->{_name};
        if ($name =~ / /) {
          $result .= $comma . "\"$name\"";
        } else {
          $result .= $comma . $name;
        }
        $comma = ", ";
      }
    }
  } else {
    my $lc_primary_index = lc $primary_index;
    if (not exists $self->{hash}->{$lc_primary_index}) {
      return 'none';
    }

    my $last_header = "";
    my $header = "";

    foreach my $index1 (sort keys %{ $self->{hash} }) {
      $header = "[$self->{hash}->{$index1}->{_name}] ";
      $header = '[global] ' if $header eq '[.*] ';

      if ($strictnamespace) {
        next unless $index1 eq '.*' or $index1 eq $lc_primary_index;
        $header = "" unless $header eq '[global] ';
      }

      foreach my $index2 (sort keys %{ $self->{hash}->{$index1} }) {
        my $distance_result = fastdistance($secondary_index, $index2);
        my $length = (length $secondary_index > length $index2) ? length $secondary_index : length $index2;

        if ($distance_result / $length < $distance) {
          my $name = $self->{hash}->{$index1}->{$index2}->{_name};
          $header = "" if $last_header eq $header;
          $last_header = $header;
          $comma = '; ' if $comma ne '' and $header ne '';
          if ($name =~ / /) {
            $result .= $comma . $header . "\"$name\"";
          } else {
            $result .= $comma . $header . $name;
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
  my ($self, $primary_index, $secondary_index, $key, $value, $dont_save) = @_;
  my $lc_primary_index = lc $primary_index;
  my $lc_secondary_index = lc $secondary_index;

  if (not exists $self->{hash}->{$lc_primary_index}) {
    my $result = "$self->{name}: $primary_index not found; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index);
    return $result;
  }

  if (not exists $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}) {
    my $secondary_text = $secondary_index =~ / / ? "\"$secondary_index\"" : $secondary_index;
    my $result = "$self->{name}: [$self->{hash}->{$lc_primary_index}->{_name}] $secondary_text not found; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index, $secondary_index);
    return $result;
  }

  my $name1 = $self->{hash}->{$lc_primary_index}->{_name};
  my $name2 = $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{_name};

  $name1 = 'global' if $name1 eq '.*';
  $name2 = "\"$name2\"" if $name2 =~ / /;

  if (not defined $key) {
    my $result = "[$name1] $name2 keys:\n";
    my $comma = '';
    foreach my $key (sort keys %{ $self->{hash}->{$lc_primary_index}->{$lc_secondary_index} }) {
      next if $key eq '_name';
      $result .= $comma . "$key => " . $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{$key};
      $comma = ";\n";
    }
    $result .= "none" if ($comma eq '');
    return $result;
  }

  if (not defined $value) {
    $value = $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{$key};
  } else {
    $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{$key} = $value;
    $self->save unless $dont_save;
  }

  return "[$name1] $name2: $key " . (defined $value ? "set to $value" : "is not set.");
}

sub unset {
  my ($self, $primary_index, $secondary_index, $key) = @_;
  my $lc_primary_index = lc $primary_index;
  my $lc_secondary_index = lc $secondary_index;

  if (not exists $self->{hash}->{$lc_primary_index}) {
    my $result = "$self->{name}: $primary_index not found; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index);
    return $result;
  }

  my $name1 = $self->{hash}->{$lc_primary_index}->{_name};
  $name1 = 'global' if $name1 eq '.*';

  if (not exists $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}) {
    my $result = "$self->{name}: [$name1] $secondary_index not found; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index, $secondary_index);
    return $result;
  }

  delete $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{$key};
  $self->save();

  my $name2 = $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{_name};
  $name2 = "\"$name2\"" if $name2 =~ / /;

  return "$self->{name}: [$name1] $name2: $key unset.";
}

sub add {
  my ($self, $primary_index, $secondary_index, $data, $dont_save) = @_;
  my $lc_primary_index = lc $primary_index;
  my $lc_secondary_index = lc $secondary_index;

  if (exists $self->{hash}->{$lc_primary_index} and exists $self->{$lc_primary_index}->{$lc_secondary_index}) {
    $self->{pbot}->{logger}->log("Entry $lc_primary_index/$lc_secondary_index already exists.\n");
    return "Error: entry already exists";
  }

  if (not exists $self->{hash}->{$lc_primary_index}) {
    $self->{hash}->{$lc_primary_index}->{_name} = $primary_index; # preserve case
  }

  $data->{_name} = $secondary_index; # preserve case
  $self->{hash}->{$lc_primary_index}->{$lc_secondary_index} = $data;
  $self->save() unless $dont_save;

  my $name1 = $self->{hash}->{$lc_primary_index}->{_name};
  my $name2 = $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{_name};
  $name1 = 'global' if $name1 eq '.*';
  $name2 = "\"$name2\"" if $name2 =~ / /;
  $self->{pbot}->{logger}->log("$self->{name}: [$name1]: $name2 added.\n");
  return "$self->{name}: [$name1]: $name2 added.";
}

sub remove {
  my ($self, $primary_index, $secondary_index) = @_;
  my $lc_primary_index = lc $primary_index;
  my $lc_secondary_index = lc $secondary_index;

  if (not exists $self->{hash}->{$lc_primary_index}) {
    my $result = "$self->{name}: $primary_index not found; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index);
    return $result;
  }

  if (not $secondary_index) {
    my $data = delete $self->{hash}->{$lc_primary_index};
    my $name = $data->{_name};
    $name = 'global' if $name eq '.*';
    $self->save;
    return "$self->{name}: $name removed.";
  }

  my $name1 = $self->{hash}->{$lc_primary_index}->{_name};
  $name1 = 'global' if $name1 eq '.*';

  if (not exists $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}) {
    my $result = "$self->{name}: [$name1] $secondary_index not found; similiar matches: ";
    $result .= $self->levenshtein_matches($primary_index, $secondary_index);
    return $result;
  }

  my $data = delete $self->{hash}->{$lc_primary_index}->{$lc_secondary_index};
  my $name2 = $data->{_name};
  $name2 = "\"$name2\"" if $name2 =~ / /;

  # remove primary group if no more secondaries (only key left should be the _name key)
  if (keys %{ $self->{hash}->{$lc_primary_index} } == 1) {
    delete $self->{hash}->{$lc_primary_index};
  }

  $self->save();
  return "$self->{name}: [$name1] $name2 removed.";
}

sub exists {
  my ($self, $primary_index, $secondary_index) = @_;
  $primary_index = lc $primary_index;
  $secondary_index = lc $secondary_index;
  return (exists $self->{hash}->{$primary_index} and exists $self->{hash}->{$primary_index}->{$secondary_index});
}

1;
