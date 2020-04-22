# File: DualIndexHashObject.pm
# Author: pragma_
#
# Purpose: Provides a hash-table object with an abstracted API that includes
# setting and deleting values, saving to and loading from files, etc. This
# extends the HashObject with an additional index key. Provides case-insensitive
# access to both index keys, while preserving original case when displaying the
# keys.
#
# Data is stored in working memory for lightning fast performance. If you have
# a huge amount of data, consider DualIndexSQLiteObject instead.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::DualIndexHashObject;

use warnings; use strict;
use feature 'unicode_strings';

use Text::Levenshtein qw(fastdistance);
use JSON;

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    Carp::croak("Missing pbot reference to " . __FILE__) unless exists $conf{pbot};
    $self->{pbot} = $conf{pbot};
    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;
    $self->{name}     = $conf{name}     // 'Dual Index hash object';
    $self->{filename} = $conf{filename} // Carp::carp("Missing filename to DualIndexHashObject, will not be able to save to or load from file.");
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
        $self->{pbot}->{logger}->log("Skipping loading from file: Couldn't open $filename: $!\n");
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
    foreach my $primary_index (keys %{$self->{hash}}) {
        if (not exists $self->{hash}->{$primary_index}->{_name}) {
            if ($primary_index ne lc $primary_index) {
                if (exists $self->{hash}->{lc $primary_index}) {
                    Carp::croak "Cannot update $self->{name} primary index $primary_index; duplicate object found";
                }

                my $data = delete $self->{hash}->{$primary_index};
                $data->{_name}                  = $primary_index;
                $primary_index                  = lc $primary_index;
                $self->{hash}->{$primary_index} = $data;
            }
        }

        foreach my $secondary_index (grep { $_ ne '_name' } keys %{$self->{hash}->{$primary_index}}) {
            if (not exists $self->{hash}->{$primary_index}->{$secondary_index}->{_name}) {
                if ($secondary_index ne lc $secondary_index) {
                    if (exists $self->{hash}->{$primary_index}->{lc $secondary_index}) {
                        Carp::croak "Cannot update $self->{name} $primary_index sub-object $secondary_index; duplicate object found";
                    }

                    my $data = delete $self->{hash}->{$primary_index}->{$secondary_index};
                    $data->{_name}                                      = $secondary_index;
                    $secondary_index                                    = lc $secondary_index;
                    $self->{hash}->{$primary_index}->{$secondary_index} = $data;
                }
            }
        }
    }
}

sub save {
    my $self = shift;
    my $filename;
    if   (@_) { $filename = shift; }
    else      { $filename = $self->{filename}; }

    if (not defined $filename) {
        Carp::carp "No $self->{name} filename specified -- skipping saving to file.\n";
        return;
    }

    $self->{pbot}->{logger}->log("Saving $self->{name} to $filename\n");

    if (not $self->get_data('$metadata$', '$metadata$', 'update_version')) {
        $self->add('$metadata$', '$metadata$', { update_version => PBot::VERSION::BUILD_REVISION });
    }

    my $json      = JSON->new;
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
    my $comma  = '';
    my $result = "";

    $distance = 0.60 if not defined $distance;

    $primary_index = '.*' if not defined $primary_index;

    if (not $secondary_index) {
        foreach my $index (sort keys %{$self->{hash}}) {
            my $distance_result = fastdistance($primary_index, $index);
            my $length          = (length $primary_index > length $index) ? length $primary_index : length $index;

            if ($distance_result / $length < $distance) {
                my $name = $self->get_key_name($index);
                if   ($name =~ / /) { $result .= $comma . "\"$name\""; }
                else                { $result .= $comma . $name; }
                $comma = ", ";
            }
        }
    } else {
        my $lc_primary_index = lc $primary_index;
        if (not exists $self->{hash}->{$lc_primary_index}) { return 'none'; }

        my $last_header = "";
        my $header      = "";

        foreach my $index1 (sort keys %{$self->{hash}}) {
            $header = "[" . $self->get_key_name($index1) . "] ";
            $header = '[global] ' if $header eq '[.*] ';

            if ($strictnamespace) {
                next unless $index1 eq '.*' or $index1 eq $lc_primary_index;
                $header = "" unless $header eq '[global] ';
            }

            foreach my $index2 (sort keys %{$self->{hash}->{$index1}}) {
                my $distance_result = fastdistance($secondary_index, $index2);
                my $length          = (length $secondary_index > length $index2) ? length $secondary_index : length $index2;

                if ($distance_result / $length < $distance) {
                    my $name = $self->get_key_name($index1, $index2);
                    $header      = "" if $last_header eq $header;
                    $last_header = $header;
                    $comma       = '; ' if $comma ne '' and $header ne '';
                    if   ($name =~ / /) { $result .= $comma . $header . "\"$name\""; }
                    else                { $result .= $comma . $header . $name; }
                    $comma = ", ";
                }
            }
        }
    }

    $result =~ s/(.*), /$1 or /;
    $result = 'none' if $comma eq '';
    return $result;
}

sub set {
    my ($self, $primary_index, $secondary_index, $key, $value, $dont_save) = @_;
    my $lc_primary_index   = lc $primary_index;
    my $lc_secondary_index = lc $secondary_index;

    if (not exists $self->{hash}->{$lc_primary_index}) {
        my $result = "$self->{name}: $primary_index not found; similiar matches: ";
        $result .= $self->levenshtein_matches($primary_index);
        return $result;
    }

    if (not exists $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}) {
        my $secondary_text = $secondary_index =~ / / ? "\"$secondary_index\"" : $secondary_index;
        my $result         = "$self->{name}: [" . $self->get_key_name($lc_primary_index) . "] $secondary_text not found; similiar matches: ";
        $result .= $self->levenshtein_matches($primary_index, $secondary_index);
        return $result;
    }

    my $name1 = $self->get_key_name($lc_primary_index);
    my $name2 = $self->get_key_name($lc_primary_index, $lc_secondary_index);

    $name1 = 'global'     if $name1 eq '.*';
    $name2 = "\"$name2\"" if $name2 =~ / /;

    if (not defined $key) {
        my $result = "[$name1] $name2 keys:\n";
        my $comma  = '';
        foreach my $key (sort keys %{$self->{hash}->{$lc_primary_index}->{$lc_secondary_index}}) {
            next if $key eq '_name';
            $result .= $comma . "$key => " . $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{$key};
            $comma = ";\n";
        }
        $result .= "none" if ($comma eq '');
        return $result;
    }

    if (not defined $value) { $value = $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{$key}; }
    else {
        $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{$key} = $value;
        $self->save unless $dont_save;
    }

    return "[$name1] $name2: $key " . (defined $value ? "set to $value" : "is not set.");
}

sub unset {
    my ($self, $primary_index, $secondary_index, $key) = @_;
    my $lc_primary_index   = lc $primary_index;
    my $lc_secondary_index = lc $secondary_index;

    if (not exists $self->{hash}->{$lc_primary_index}) {
        my $result = "$self->{name}: $primary_index not found; similiar matches: ";
        $result .= $self->levenshtein_matches($primary_index);
        return $result;
    }

    my $name1 = $self->get_key_name($lc_primary_index);
    $name1 = 'global' if $name1 eq '.*';

    if (not exists $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}) {
        my $result = "$self->{name}: [$name1] $secondary_index not found; similiar matches: ";
        $result .= $self->levenshtein_matches($primary_index, $secondary_index);
        return $result;
    }

    my $name2 = $self->get_key_name($lc_primary_index, $lc_secondary_index);
    $name2 = "\"$name2\"" if $name2 =~ / /;

    if (defined delete $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{$key}) {
        $self->save;
        return "$self->{name}: [$name1] $name2: $key unset.";
    } else {
        return "$self->{name}: [$name1] $name2: $key does not exist.";
    }
    $self->save;
}

sub exists {
    my ($self, $primary_index, $secondary_index, $data_index) = @_;
    return 0 if not defined $primary_index;
    $primary_index = lc $primary_index;
    return 0 if not exists $self->{hash}->{$primary_index};
    return 1 if not defined $secondary_index;
    $secondary_index = lc $secondary_index;
    return 0 if not exists $self->{hash}->{$primary_index}->{$secondary_index};
    return 1 if not defined $data_index;
    return exists $self->{hash}->{$primary_index}->{$secondary_index}->{$data_index};
}

sub get_key_name {
    my ($self, $primary_index, $secondary_index) = @_;

    my $lc_primary_index = lc $primary_index;

    return $lc_primary_index if not exists $self->{hash}->{$lc_primary_index};

    if (not defined $secondary_index) {
        if (exists $self->{hash}->{$lc_primary_index}->{_name}) {
            return $self->{hash}->{$lc_primary_index}->{_name};
        } else {
            return $lc_primary_index;
        }
    }

    my $lc_secondary_index = lc $secondary_index;

    return $lc_secondary_index if not exists $self->{hash}->{$lc_primary_index}->{$lc_secondary_index};

    if (exists $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{_name}) {
        return $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{_name};
    } else {
        return $lc_secondary_index;
    }
}

sub get_keys {
    my ($self, $primary_index, $secondary_index) = @_;
    return grep { $_ ne '$metadata$' } keys %{$self->{hash}} if not defined $primary_index;

    my $lc_primary_index = lc $primary_index;

    if (not defined $secondary_index) {
        return () if not exists $self->{hash}->{$lc_primary_index};
        return grep { $_ ne '_name' and $_ ne '$metadata$' } keys %{$self->{hash}->{$lc_primary_index}};
    }

    my $lc_secondary_index = lc $secondary_index;

    return () if not exists $self->{hash}->{$lc_primary_index}
        or not exists $self->{hash}->{$lc_primary_index}->{$lc_secondary_index};

    return grep { $_ ne '_name' } keys %{$self->{hash}->{lc $primary_index}->{lc $secondary_index}};
}

sub get_data {
    my ($self, $primary_index, $secondary_index, $data_index) = @_;
    $primary_index   = lc $primary_index   if defined $primary_index;
    $secondary_index = lc $secondary_index if defined $secondary_index;
    return undef                                               if not exists $self->{hash}->{$primary_index};
    return $self->{hash}->{$primary_index}                     if not defined $secondary_index;
    return $self->{hash}->{$primary_index}->{$secondary_index} if not defined $data_index;
    return $self->{hash}->{$primary_index}->{$secondary_index}->{$data_index};
}

sub add {
    my ($self, $primary_index, $secondary_index, $data, $dont_save, $quiet) = @_;
    my $lc_primary_index   = lc $primary_index;
    my $lc_secondary_index = lc $secondary_index;

    if (not exists $self->{hash}->{$lc_primary_index}) {
        # preserve case
        if ($primary_index ne $lc_primary_index) {
            $self->{hash}->{$lc_primary_index}->{_name} = $primary_index;
        }
    }

    if ($secondary_index ne $lc_secondary_index) {
        # preserve case
        $data->{_name} = $secondary_index;
    }

    $self->{hash}->{$lc_primary_index}->{$lc_secondary_index} = $data;
    $self->save() unless $dont_save;

    my $name1 = $self->get_key_name($lc_primary_index);
    my $name2 = $self->get_key_name($lc_primary_index, $lc_secondary_index);
    $name1 = 'global'     if $name1 eq '.*';
    $name2 = "\"$name2\"" if $name2 =~ / /;
    $self->{pbot}->{logger}->log("$self->{name}: [$name1]: $name2 added.\n") unless $dont_save or $quiet;
    return "$self->{name}: [$name1]: $name2 added.";
}

sub remove {
    my ($self, $primary_index, $secondary_index, $data_index, $dont_save) = @_;
    my $lc_primary_index   = lc $primary_index;
    my $lc_secondary_index = lc $secondary_index;

    if (not exists $self->{hash}->{$lc_primary_index}) {
        my $result = "$self->{name}: $primary_index not found; similiar matches: ";
        $result .= $self->levenshtein_matches($primary_index);
        return $result;
    }

    if (not defined $secondary_index) {
        my $data = delete $self->{hash}->{$lc_primary_index};
        if (defined $data) {
            my $name = exists $data->{_name} ? $data->{_name} : $lc_primary_index;
            $name = 'global' if $name eq '.*';
            $self->save unless $dont_save;
            return "$self->{name}: $name removed.";
        } else {
            return "$self->{name}: $primary_index does not exist.";
        }
    }

    my $name1 = $self->get_key_name($lc_primary_index);
    $name1 = 'global' if $name1 eq '.*';

    if (not exists $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}) {
        my $result = "$self->{name}: [$name1] $secondary_index not found; similiar matches: ";
        $result .= $self->levenshtein_matches($primary_index, $secondary_index);
        return $result;
    }

    if (not defined $data_index) {
        my $data = delete $self->{hash}->{$lc_primary_index}->{$lc_secondary_index};
        if (defined $data) {
            my $name2 = exists $data->{_name} ? $data->{_name} : $lc_secondary_index;
            $name2 = "\"$name2\"" if $name2 =~ / /;

            # remove primary group if no more secondaries
            if (grep { $_ ne '_name' } keys %{$self->{hash}->{$lc_primary_index}} == 0) {
                delete $self->{hash}->{$lc_primary_index};
            }

            $self->save unless $dont_save;
            return "$self->{name}: [$name1] $name2 removed.";
        } else {
            return "$self->{name}: [$name1] $secondary_index does not exist.";
        }
    }

    my $name2 = $self->get_key_name($lc_primary_index, $lc_secondary_index);
    if (defined delete $self->{hash}->{$lc_primary_index}->{$lc_secondary_index}->{$data_index}) {
        return "$self->{name}: [$name1] $name2.$data_index removed.";
    } else {
        return "$self->{name}: [$name1] $name2.$data_index does not exist.";
    }
}

# for compatibility with DualIndexSQLiteObject
sub create_metadata { }

# todo:
sub get_each { }
sub get_next { }
sub get_all  { }

1;
