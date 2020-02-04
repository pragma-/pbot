# File: HashObject.pm
# Author: pragma_
#
# Purpose: Provides a hash-table object with an abstracted API that includes
# setting and deleting values, saving to and loading from files, etc.  Provides
# case-insensitive access to the index key while preserving original case when
# displaying index key.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::HashObject;

use warnings;
use strict;

use feature 'unicode_strings';

use Text::Levenshtein qw(fastdistance);
use Carp ();
use JSON;

sub new {
  Carp::croak("Options to HashObject should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  $self->{name} = $conf{name} // 'hash object';
  $self->{filename} = $conf{filename} // Carp::carp("Missing filename to HashObject, will not be able to save to or load from file.");
  $self->{pbot} = $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{hash} = {};
}

sub load {
  my $self = shift;
  my $filename;
  if (@_) { $filename = shift; } else { $filename = $self->{filename}; }

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

  $self->{hash} = decode_json $contents;
  close FILE;

  # update existing entries to use _name to preserve case
  # and lowercase any non-lowercased entries
  foreach my $index (keys %{ $self->{hash} }) {
    if (not exists $self->{hash}->{$index}->{_name}) {
      if (lc $index eq $index) {
        $self->{hash}->{$index}->{_name} = $index;
      } else {
        if (exists $self->{hash}->{lc $index}) {
          Carp::croak "Cannot update $self->{name} object $index; duplicate object found";
        }

        my $data = delete $self->{hash}->{$index};
        $data->{_name} = $index;
        $self->{hash}->{lc $index} = $data;
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
  close(FILE);
}

sub clear {
  my $self = shift;
  $self->{hash} = {};
}

sub levenshtein_matches {
  my ($self, $keyword) = @_;
  my $comma = '';
  my $result = "";

  foreach my $index (sort keys %{ $self->{hash} }) {
    my $distance = fastdistance($keyword, $index);
    my $length = (length $keyword > length $index) ? length $keyword : length $index;

    if ($length != 0 && $distance / $length < 0.50) {
      $result .= $comma . $index;
      $comma = ", ";
    }
  }

  $result =~ s/(.*), /$1 or /;
  $result = "none"  if $comma eq '';
  return $result;
}

sub set {
  my ($self, $index, $key, $value, $dont_save) = @_;
  my $lc_index = lc $index;

  if (not exists $self->{hash}->{$lc_index}) {
    my $result = "$self->{name}: $index not found; similiar matches: ";
    $result .= $self->levenshtein_matches($index);
    return $result;
  }

  if (not defined $key) {
    my $result = "[$self->{name}] $self->{hash}->{$lc_index}->{_name} keys: ";
    my $comma = '';
    foreach my $k (sort keys %{ $self->{hash}->{$lc_index} }) {
      next if $k eq '_name';
      $result .= $comma . "$k => " . $self->{hash}->{$lc_index}->{$k};
      $comma = "; ";
    }
    $result .= "none" if ($comma eq '');
    return $result;
  }

  if (not defined $value) {
    $value = $self->{hash}->{$lc_index}->{$key};
  } else {
    $self->{hash}->{$lc_index}->{$key} = $value;
    $self->save unless $dont_save;
  }

  return "[$self->{name}] $self->{hash}->{$lc_index}->{_name}: $key " . (defined $value ? "set to $value" : "is not set.");
}

sub unset {
  my ($self, $index, $key) = @_;
  my $lc_index = lc $index;

  if (not exists $self->{hash}->{$lc_index}) {
    my $result = "$self->{name}: $index not found; similiar matches: ";
    $result .= $self->levenshtein_matches($index);
    return $result;
  }

  delete $self->{hash}->{$lc_index}->{$key};
  $self->save;

  return "[$self->{name}] $self->{hash}->{$lc_index}->{_name}: $key unset.";
}

sub exists {
  my ($self, $index) = @_;
  return exists $self->{hash}->{lc $index};
}

sub get_data {
  my ($self, $index) = @_;
  return $self->{hash}->{lc $index};
}

sub add {
  my ($self, $index, $data, $dont_save) = @_;
  my $lc_index = lc $index;

  if (exists $self->{hash}->{$lc_index}) {
    return "Error: $self->{hash}->{$lc_index}->{_name} already exists in $self->{name}.";
  }

  $data->{_name} = $index; # preserve case of index
  $self->{hash}->{$lc_index} = $data;
  $self->save unless $dont_save;
  return "$index added to $self->{name}.";
}

sub remove {
  my ($self, $index) = @_;
  my $lc_index = lc $index;

  if (not exists $self->{hash}->{$lc_index}) {
    my $result = "$self->{name}: $index not found; similiar matches: ";
    $result .= $self->levenshtein_matches($lc_index);
    return $result;
  }

  my $data = delete $self->{hash}->{$lc_index};
  $self->save;

  return "$data->{_name} removed from $self->{name}.";
}

1;
