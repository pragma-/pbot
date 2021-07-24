# File: HashObject.pm
#
# Purpose: Provides a hash-table object with an abstracted API that includes
# setting and deleting values, saving to and loading from files, etc.  Provides
# case-insensitive access to the index key while preserving original case when
# displaying index key.
#
# Data is stored in working memory for lightning fast performance. If a filename
# is provided, data is written to the file after any modifications.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::Storage::HashObject;

use PBot::Imports;

use Text::Levenshtein qw(fastdistance);
use JSON;

sub new {
    my ($class, %args) = @_;
    my $self  = bless {}, $class;
    Carp::croak("Missing pbot reference to " . __FILE__) unless exists $args{pbot};
    $self->{pbot} = delete $args{pbot};
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    $self->{name}     = $conf{name} // 'unnammed';
    $self->{hash}     = {};
    $self->{filename} = $conf{filename};

    if (not defined $self->{filename}) {
        Carp::carp("Missing filename for $self->{name} HashObject, will not be able to save to or load from file.");
    }
}

sub load {
    my ($self, $filename) = @_;

    # allow overriding $self->{filename} with $filename parameter
    $filename //= $self->{filename};

    # no filename? nothing to load
    if (not defined $filename) {
        Carp::carp "No $self->{name} filename specified -- skipping loading from file";
        return;
    }

    $self->{pbot}->{logger}->log("Loading $self->{name} from $filename\n");

    if (not open(FILE, "< $filename")) {
        $self->{pbot}->{logger}->log("Skipping loading from file: Couldn't open $filename: $!\n");
        return;
    }

    # slurp file into $contents
    my $contents = do {
        local $/;
        <FILE>;
    };

    close FILE;

    eval {
        # first try to deocde json, throws exception on misparse/errors
        my $newhash = decode_json $contents;

        # clear current hash only if decode succeeded
        $self->clear;

        # update internal hash
        $self->{hash} = $newhash;

        # update existing entries to use _name to preserve typographical casing
        # e.g., when someone edits a config file by hand, they might add an
        # entry with uppercase characters in its name.
        foreach my $index (keys %{$self->{hash}}) {
            if (not exists $self->{hash}->{$index}->{_name}) {
                if ($index ne lc $index) {
                    if (exists $self->{hash}->{lc $index}) {
                        Carp::croak "Cannot update $self->{name} object $index; duplicate object found";
                    }

                    my $data = delete $self->{hash}->{$index};
                    $data->{_name} = $index;             # _name is original typographical case
                    $self->{hash}->{lc $index} = $data;  # index key is lowercased
                }
            }
        }
    };

    if ($@) {
        # json parse error or such
        $self->{pbot}->{logger}->log("Warning: failed to load $filename: $@\n");
    }
}

sub save {
    my ($self, $filename) = @_;

    # allow parameter overriding internal field
    $filename //= $self->{filename};

    # no filename? nothing to save
    if (not defined $filename) {
        Carp::carp "No $self->{name} filename specified -- skipping saving to file.\n";
        return;
    }

    $self->{pbot}->{logger}->log("Saving $self->{name} to $filename\n");

    # add update_version to metadata
    if (not $self->get_data('$metadata$', 'update_version')) {
        $self->add('$metadata$', { update_version => PBot::VERSION::BUILD_REVISION });
    }

    # ensure `name` metadata is current
    $self->set('$metadata$', 'name', $self->{name}, 1);

    # encode hash as JSON
    my $json      = JSON->new;
    my $json_text = $json->pretty->canonical->utf8->encode($self->{hash});

    # print JSON to file
    open(FILE, "> $filename") or die "Couldn't open $filename: $!\n";
    print FILE "$json_text\n";
    close(FILE);
}

sub clear {
    my ($self) = @_;
    $self->{hash} = {};
}

sub levenshtein_matches {
    my ($self, $keyword) = @_;

    my @matches;

    foreach my $index (sort keys %{$self->{hash}}) {
        my $distance = fastdistance($keyword, $index);

        my $length_a = length $keyword;
        my $length_b = length $index;
        my $length   = $length_a > $length_b ? $length_a : $length_b;

        if ($length != 0 && $distance / $length < 0.50) {
            push @matches, $index;
        }
    }

    return 'none' if not @matches;

    my $result = join ', ', @matches;

    # "a, b, c, d" -> "a, b, c or d"
    $result =~ s/(.*), /$1 or /;

    return $result;
}

sub set {
    my ($self, $index, $key, $value, $dont_save) = @_;
    my $lc_index = lc $index;

    # find similarly named keys
    if (not exists $self->{hash}->{$lc_index}) {
        my $result = "$self->{name}: $index not found; similar matches: ";
        $result .= $self->levenshtein_matches($index);
        return $result;
    }

    if (not defined $key) {
        # if no key provided, then list all keys and values
        my $result = "[$self->{name}] " . $self->get_key_name($lc_index) .  " keys: ";

        my @entries;

        foreach my $key (sort grep { $_ ne '_name' } keys %{$self->{hash}->{$lc_index}}) {
            push @entries, "$key: $self->{hash}->{$lc_index}->{$key}";
        }

        if (@entries) {
            $result .= join ";\n", @entries;
        } else {
            $result .= 'none';
        }

        return $result;
    }

    if (not defined $value) {
        # if no value provided, then show this key's value
        $value = $self->{hash}->{$lc_index}->{$key};
    } else {
        # otherwise update the value belonging to key
        $self->{hash}->{$lc_index}->{$key} = $value;
        $self->save unless $dont_save;
    }

    return "[$self->{name}] " . $self->get_key_name($lc_index) . ": $key " . (defined $value ? "set to $value" : "is not set.");
}

sub unset {
    my ($self, $index, $key) = @_;
    my $lc_index = lc $index;

    if (not exists $self->{hash}->{$lc_index}) {
        my $result = "$self->{name}: $index not found; similar matches: ";
        $result .= $self->levenshtein_matches($index);
        return $result;
    }

    if (defined delete $self->{hash}->{$lc_index}->{$key}) {
        $self->save;
        return "[$self->{name}] " . $self->get_key_name($lc_index) . ": $key unset.";
    } else {
        return "[$self->{name}] " . $self->get_key_name($lc_index) . ": $key does not exist.";
    }
}

sub exists {
    my ($self, $index, $data_index) = @_;
    return exists $self->{hash}->{lc $index} if not defined $data_index;
    return exists $self->{hash}->{lc $index}->{$data_index};
}

sub get_key_name {
    my ($self, $index) = @_;
    my $lc_index = lc $index;
    return $lc_index if not exists $self->{hash}->{$lc_index};
    return exists $self->{hash}->{$lc_index}->{_name} ? $self->{hash}->{$lc_index}->{_name} : $lc_index;
}

sub get_keys {
    my ($self, $index) = @_;
    return grep { $_ ne '$metadata$' } keys %{$self->{hash}} if not defined $index;
    return grep { $_ ne '_name' } keys %{$self->{hash}->{lc $index}};
}

sub get_data {
    my ($self, $index, $data_index) = @_;
    my $lc_index = lc $index;
    return undef                      if not exists $self->{hash}->{$lc_index};
    return $self->{hash}->{$lc_index} if not defined $data_index;
    return $self->{hash}->{$lc_index}->{$data_index};
}

sub add {
    my ($self, $index, $data, $dont_save) = @_;
    my $lc_index = lc $index;

    # preserve case of index
    if ($index ne $lc_index) {
        $data->{_name} = $index;
    }

    $self->{hash}->{$lc_index} = $data;
    $self->save unless $dont_save;
    return "$index added to $self->{name}.";
}

sub remove {
    my ($self, $index, $data_index, $dont_save) = @_;
    my $lc_index = lc $index;

    if (not exists $self->{hash}->{$lc_index}) {
        my $result = "$self->{name}: $index not found; similar matches: ";
        $result .= $self->levenshtein_matches($lc_index);
        return $result;
    }

    if (defined $data_index) {
        if (defined delete $self->{hash}->{$lc_index}->{$data_index}) {
            delete $self->{hash}->{$lc_index} if keys(%{$self->{hash}->{$lc_index}}) == 1;
            $self->save unless $dont_save;
            return $self->get_key_name($lc_index) . ".$data_index removed from $self->{name}";
        } else {
            return "$self->{name}: " . $self->get_key_name($lc_index) . ".$data_index does not exist.";
        }
    }

    my $data = delete $self->{hash}->{$lc_index};
    if (defined $data) {
        $self->save unless $dont_save;
        my $name = exists $data->{_name} ? $data->{_name} : $lc_index;
        return "$name removed from $self->{name}.";
    } else {
        return "$self->{name}: $data_index does not exist.";
    }
}

1;
