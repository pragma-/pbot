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
use JSON;

sub new {
  if (ref($_[1]) eq 'HASH') {
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
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{hash} = {};
}

sub hash_add {
  my ($self, $index_key, $hash) = @_;

  if (defined $hash) {
    if (exists $self->hash->{$index_key}) {
      return undef;
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

  if (@_) { $filename = shift; } else { $filename = $self->filename; }

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
  close(FILE);
}

sub clear {
  my $self = shift;
  $self->{hash} = {};
}

sub find_hash {
  my ($self, $keyword) = @_;

  my $result = eval {
    foreach my $index (keys %{ $self->hash }) {
      if ($keyword =~ m/^\Q$index\E$/i) {
        return $index;
      }
    }

    return undef;
  };

  if ($@) {
    $self->{pbot}->{logger}->log("find_hash: bad regex: $@\n");
    return undef;
  }

  return $result;
}

sub levenshtein_matches {
  my ($self, $keyword) = @_;
  my $comma = '';
  my $result = "";

  foreach my $index (sort keys %{ $self->hash }) {
    my $distance = fastdistance($keyword, $index);

    # print "Distance $distance for $keyword (" , (length $keyword) , ") vs $index (" , length $index , ")\n";

    my $length = (length($keyword) > length($index)) ? length $keyword : length $index;

    # print "Percentage: ", $distance / $length, "\n";

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

  my $hash_index = $self->find_hash($index);

  if (not $hash_index) {
    my $result = "No such $self->{name} object '$index'; similiar matches: ";
    $result .= $self->levenshtein_matches($index);
    return $result;
  }

  if (not defined $key) {
    my $result = "[$self->{name}] $hash_index keys: ";
    my $comma = '';
    foreach my $k (sort keys %{ $self->hash->{$hash_index} }) {
      $result .= $comma . "$k => " . $self->hash->{$hash_index}{$k};
      $comma = "; ";
    }
    $result .= "none" if ($comma eq '');
    return $result;
  }

  if (not defined $value) {
    $value = $self->hash->{$hash_index}{$key};
  } else {
    $self->hash->{$hash_index}{$key} = $value;
    $self->save() unless $dont_save;
  }

  return "[$self->{name}] $hash_index: '$key' " . (defined $value ? "set to '$value'" : "is not set.");
}

sub unset {
  my ($self, $index, $key) = @_;

  my $hash_index = $self->find_hash($index);

  if (not $hash_index) {
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

  if ($self->hash_add($index_key, $hash)) {
    $self->save();
  } else {
    return "Error occurred adding new $self->{name} object.";
  }

  return "'$index_key' added to $self->{name}.";
}

sub remove {
  my ($self, $index) = @_;

  my $hash_index = $self->find_hash($index);

  if (not $hash_index) {
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

  if (@_) { $self->{filename} = shift; }
  return $self->{filename};
}

1;
