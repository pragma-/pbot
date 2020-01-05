# File: FactoidCommands.pm
# Author: pragma_
#
# Purpose: Administrative command subroutines.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::FactoidCommands;

use warnings;
use strict;

use feature 'unicode_strings';

use Carp ();
use Time::Duration;
use Time::HiRes qw(gettimeofday);
use Getopt::Long qw(GetOptionsFromString);
use POSIX qw(strftime);
use Storable;
use LWP::UserAgent ();
use JSON;

use PBot::Utils::SafeFilename;

sub new {
  if (ref($_[1]) eq 'HASH') {
    Carp::croak("Options to FactoidCommands should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

our %factoid_metadata_levels = (
  created_on                  => 90,
  enabled                     => 10,
  last_referenced_in          => 90,
  last_referenced_on          => 90,
  modulelauncher_subpattern   => 90,
  owner                       => 90,
  rate_limit                  => 10,
  ref_count                   => 90,
  ref_user                    => 90,
  type                        => 90,
  edited_by                   => 90,
  edited_on                   => 90,
  locked                      => 10,
  add_nick                    => 10,
  nooverride                  => 10,
  'effective-level'           => 40,
  'persist-key'               => 20,
  'interpolate'               => 10,
  # all others are allowed to be factset by anybody/default to level 0
);

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot};
  if (not defined $pbot) {
    Carp::croak("Missing pbot reference to FactoidCommands");
  }

  $self->{pbot} = $pbot;

  $pbot->{registry}->add_default('text', 'general', 'module_repo', $conf{module_repo} // 'https://github.com/pragma-/pbot/blob/master/modules/');

  $pbot->{commands}->register(sub { return $self->factadd(@_)         },       "learn",        0);
  $pbot->{commands}->register(sub { return $self->factadd(@_)         },       "factadd",      0);
  $pbot->{commands}->register(sub { return $self->factrem(@_)         },       "forget",       0);
  $pbot->{commands}->register(sub { return $self->factrem(@_)         },       "factrem",      0);
  $pbot->{commands}->register(sub { return $self->factshow(@_)        },       "factshow",     0);
  $pbot->{commands}->register(sub { return $self->factinfo(@_)        },       "factinfo",     0);
  $pbot->{commands}->register(sub { return $self->factlog(@_)         },       "factlog",      0);
  $pbot->{commands}->register(sub { return $self->factundo(@_)        },       "factundo",     0);
  $pbot->{commands}->register(sub { return $self->factredo(@_)        },       "factredo",     0);
  $pbot->{commands}->register(sub { return $self->factset(@_)         },       "factset",      0);
  $pbot->{commands}->register(sub { return $self->factunset(@_)       },       "factunset",    0);
  $pbot->{commands}->register(sub { return $self->factchange(@_)      },       "factchange",   0);
  $pbot->{commands}->register(sub { return $self->factalias(@_)       },       "factalias",    0);
  $pbot->{commands}->register(sub { return $self->factmove(@_)        },       "factmove",     0);
  $pbot->{commands}->register(sub { return $self->call_factoid(@_)    },       "fact",         0);
  $pbot->{commands}->register(sub { return $self->factfind(@_)        },       "factfind",     0);
  $pbot->{commands}->register(sub { return $self->list(@_)            },       "list",         0);
  $pbot->{commands}->register(sub { return $self->top20(@_)           },       "top20",        0);
  $pbot->{commands}->register(sub { return $self->load_module(@_)     },       "load",        90);
  $pbot->{commands}->register(sub { return $self->unload_module(@_)   },       "unload",      90);
  $pbot->{commands}->register(sub { return $self->histogram(@_)       },       "histogram",    0);
  $pbot->{commands}->register(sub { return $self->count(@_)           },       "count",        0);

  # the following commands have not yet been updated to use the new factoid structure
  # DO NOT USE!!  Factoid corruption may occur.
  $pbot->{commands}->register(sub { return $self->add_regex(@_)       },       "regex",        999);
}

sub call_factoid {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($chan, $keyword, $args) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

  if (not defined $chan or not defined $keyword) {
    return "Usage: fact <channel> <keyword> [arguments]";
  }

  my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($chan, $keyword, arguments => $args, exact_channel => 1, exact_trigger => 1);

  if (not defined $trigger) {
    return "No such factoid '$keyword' exists for channel '$chan'";
  }

  $stuff->{keyword} = $trigger;
  $stuff->{trigger} = $trigger;
  $stuff->{ref_from} = $channel;
  $stuff->{arguments} = $args;
  $stuff->{root_keyword} = $trigger;

  return $self->{pbot}->{factoids}->interpreter($stuff);
}

sub log_factoid {
  my $self = shift;
  my ($channel, $trigger, $hostmask, $msg, $dont_save_undo) = @_;

  my $channel_path = $channel;
  $channel_path = 'global' if $channel_path eq '.*';

  my $channel_path_safe = safe_filename $channel_path;
  my $trigger_safe = safe_filename $trigger;

  my $path = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/factlog';
  open my $fh, ">> $path/$trigger_safe.$channel_path_safe" or do {
    $self->{pbot}->{logger}->log("Failed to open factlog for $channel/$trigger: $!\n");
    return;
  };

  my $now = gettimeofday;
  my $h = {ts => $now, hm => $hostmask, msg => $msg};
  my $json = encode_json $h;
  print $fh "$json\n";
  close $fh;

  return if $dont_save_undo;

  my $undos = eval { retrieve("$path/$trigger_safe.$channel_path_safe.undo"); };

  if (not $undos) {
    $undos = {
      idx  => -1,
      list => []
    };
  }

  # TODO: use registry instead of hardcoded 20... meh
  if (@{$undos->{list}} > 20) {
    shift @{$undos->{list}};
    $undos->{idx}--;
  }

  if ($undos->{idx} > -1 and @{$undos->{list}} > $undos->{idx} + 1) {
    splice @{$undos->{list}}, $undos->{idx} + 1;
  }

  push @{$undos->{list}}, $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger};
  $undos->{idx}++;

  eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
  $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
}

sub find_factoid_with_optional_channel {
  my ($self, $from, $arguments, $command, %opts) = @_;

  my %default_opts = (
    usage => undef,
    explicit => 0,
    exact_channel => 0
  );

  %opts = (%default_opts, %opts);

  my $arglist = $self->{pbot}->{interpreter}->make_args($arguments);
  my ($from_chan, $from_trigger, $remaining_args) = $self->{pbot}->{interpreter}->split_args($arglist, 3);

  if (not defined $from_chan or (not defined $from_chan and not defined $from_trigger)) {
    return "Usage: $command [channel] <keyword>" if not $opts{usage};
    return $opts{usage};
  }

  my $needs_disambig;

  if (not defined $from_trigger) {
    # cmd arg1, so insert $from as channel
    $from_trigger = $from_chan;
    $from_chan = $from;
    $remaining_args = "";
    #$needs_disambig = 1;
  } else {
    # cmd arg1 arg2 [...?]
    if ($from_chan !~ /^#/ and lc $from_chan ne 'global' and $from_chan ne '.*') {
      # not a channel or global, so must be a keyword
      my $keyword = $from_chan;
      $from_chan = $from;
      $from_trigger = $keyword;
      (undef, $remaining_args) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
    }
  }

  $from_chan = '.*' if $from_chan !~ /^#/;
  $from_chan = lc $from_chan;

  my ($channel, $trigger);

  if ($opts{exact_channel} == 1) {
    ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($from_chan, $from_trigger, exact_channel => 1, exact_trigger => 1);

    if (not defined $channel) {
      $from_chan = 'the global channel' if $from_chan eq '.*';
      return "/say $from_trigger not found in $from_chan.";
    }
  } else {
    my @factoids = $self->{pbot}->{factoids}->find_factoid($from_chan, $from_trigger, exact_trigger => 1);

    if (not @factoids or not $factoids[0]) {
      if ($needs_disambig) {
        return "/say $from_trigger not found";
      } else {
        $from_chan = 'global channel' if $from_chan eq '.*';
        return "/say $from_trigger not found in $from_chan";
      }
    }

    if (@factoids > 1) {
      if ($needs_disambig or not grep { $_->[0] eq $from_chan } @factoids) {
        unless ($opts{explicit}) {
          foreach my $factoid (@factoids) {
            if ($factoid->[0] eq '.*') {
              ($channel, $trigger) = ($factoid->[0], $factoid->[1]);
            }
          }
        }
        if (not defined $channel) {
          return "/say $from_trigger found in multiple channels: " . (join ', ', sort map { $_->[0] eq '.*' ? 'global' : $_->[0] } @factoids) . "; use `$command <channel> $from_trigger` to disambiguate.";
        }
      } else {
        foreach my $factoid (@factoids) {
          if ($factoid->[0] eq $from_chan) {
            ($channel, $trigger) = ($factoid->[0], $factoid->[1]);
            last;
          }
        }
      }
    } else {
      ($channel, $trigger) = ($factoids[0]->[0], $factoids[0]->[1]);
    }
  }

  $channel = '.*' if $channel eq 'global';
  $from_chan = '.*' if $channel eq 'global';

  if ($opts{explicit} and $channel =~ /^#/ and $from_chan =~ /^#/ and $channel ne $from_chan) {
    return "/say $trigger belongs to $channel, not $from_chan. Please switch to or explicitly specify $channel.";
  }

  return ($channel, $trigger, $remaining_args);
}

sub hash_differences_as_string {
  my ($self, $old, $new) = @_;

  my @exclude = qw/created_on last_referenced_in last_referenced_on ref_count ref_user edited_by edited_on/;
  my %diff;

  foreach my $key (keys %$new) {
    next if grep { $key eq $_ } @exclude;

    if (not exists $old->{$key} or $old->{$key} ne $new->{$key}) {
      $diff{$key} = $new->{$key};
    }
  }

  foreach my $key (keys %$old) {
    next if grep { $key eq $_ } @exclude;

    if (not exists $new->{$key}) {
      $diff{"deleted $key"} = undef;
    }
  }

  if (not keys %diff) {
    return "No change.";
  }

  my $changes = "";

  my $comma = "";
  foreach my $key (sort keys %diff) {
    if (defined $diff{$key}) {
      $changes .= "$comma$key => $diff{$key}";
    } else {
      $changes .= "$comma$key";
    }
    $comma = ", ";
  }

  return $changes
}

sub list_undo_history {
  my ($self, $undos, $start_from) = @_;

  $start_from-- if defined $start_from;
  $start_from = 0 if not defined $start_from or $start_from < 0;

  my $result = "";
  if ($start_from > @{$undos->{list}}) {
    if (@{$undos->{list}} == 1) {
      return "But there is only one revision available.";
    } else {
      return "But there are only " . @{$undos->{list}} . " revisions available.";
    }
  }

  if ($start_from == 0) {
    if ($undos->{idx} == 0) {
      $result .= "*1*: ";
    } else {
      $result .= "1: ";
    }
    $result .= $self->hash_differences_as_string({}, $undos->{list}->[0]) . ";\n\n";
    $start_from++;
  }

  for (my $i = $start_from; $i < @{$undos->{list}}; $i++) {
    if ($i == $undos->{idx}) {
      $result .= "*" . ($i + 1) . "*: ";
    } else {
      $result .= ($i + 1) . ": ";
    }
    $result .= $self->hash_differences_as_string($undos->{list}->[$i - 1], $undos->{list}->[$i]);
    $result .= ";\n\n";
  }

  return $result;
}

sub factundo {
  my ($self, $from, $nick, $user, $host, $arguments, $stuff) = @_;

  my $usage = "Usage: factundo [-l [N]] [-r N] [channel] <keyword> (-l list undo history, optionally starting from N; -r jump to revision N)";

  my $getopt_error;
  local $SIG{__WARN__} = sub {
    $getopt_error = shift;
    chomp $getopt_error;
  };

  my ($list_undos, $goto_revision);
  my ($ret, $args) = GetOptionsFromString($arguments,
    'l:i'  => \$list_undos,
    'r=i' => \$goto_revision);

  return "/say $getopt_error -- $usage" if defined $getopt_error;
  return $usage if @$args > 2;
  return $usage if not @$args;

  $arguments = join(' ', map { $_ = "'$_'" if $_ =~ m/ /; $_; } @$args);
  my $arglist = $self->{pbot}->{interpreter}->make_args($arguments);

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, $arguments, 'factundo', explicit => 1, exact_channel => 1);
  my $deleted;

  if (not defined $trigger) {
    # factoid not found or some error, try to continue and load undo file if it exists
    $deleted = 1;
    ($channel, $trigger) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
    if (not defined $trigger) {
      $trigger = $channel;
      $channel = $from;
    }
    $channel = '.*' if $channel !~ m/^#/;
  }

  my $channel_path = $channel;
  $channel_path  = 'global' if $channel_path eq '.*';

  my $channel_path_safe = safe_filename $channel_path;
  my $trigger_safe = safe_filename $trigger;

  my $path = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/factlog';
  my $undos = eval { retrieve("$path/$trigger_safe.$channel_path_safe.undo"); };

  if (not $undos) {
    return "There are no undos available for [$channel] $trigger.";
  }

  if (defined $list_undos) {
    $list_undos = 1 if $list_undos == 0;
    return $self->list_undo_history($undos, $list_undos);
  }

  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my $admininfo = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
  if ($factoids->{$channel}->{$trigger}->{'locked'}) {
    return "/say $trigger is locked and cannot be reverted." if not defined $admininfo;

    if (exists $factoids->{$channel}->{$trigger}->{'effective-level'}
        and $admininfo->{level} < $factoids->{$channel}->{$trigger}->{'effective-level'}) {
      return "/say $trigger is locked with an effective-level higher than your level and cannot be reverted.";
    }
  }

  if (defined $goto_revision) {
    return "Don't be absurd." if $goto_revision < 1;
    if ($goto_revision > @{$undos->{list}}) {
      if (@{$undos->{list}} == 1) {
        return "There is only one revision available for [$channel] $trigger.";
      } else {
        return "There are " . @{$undos->{list}} . " revisions available for [$channel] $trigger.";
      }
    }

    if ($goto_revision == $undos->{idx} + 1) {
      return "[$channel] $trigger is already at revision $goto_revision.";
    }

    $undos->{idx} = $goto_revision - 1;
    eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
    $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
  } else {
    unless ($deleted) {
      return "There are no more undos remaining for [$channel] $trigger." if not $undos->{idx};
      $undos->{idx}--;
      eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
      $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
    }
  }

  $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger} = $undos->{list}->[$undos->{idx}];

  my $changes = $self->hash_differences_as_string($undos->{list}->[$undos->{idx} + 1], $undos->{list}->[$undos->{idx}]);
  $self->log_factoid($channel, $trigger, "$nick!$user\@$host", "reverted (undo): $changes", 1);
  return "[$channel] $trigger reverted (revision " . ($undos->{idx} + 1) . "): $changes\n";
}

sub factredo {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  my $usage = "Usage: factredo [-l [N]] [-r N] [channel] <keyword> (-l list undo history, optionally starting from N; -r jump to revision N)";

  my $getopt_error;
  local $SIG{__WARN__} = sub {
    $getopt_error = shift;
    chomp $getopt_error;
  };

  my ($list_undos, $goto_revision);
  my ($ret, $args) = GetOptionsFromString($arguments,
    'l:i'  => \$list_undos,
    'r=i' => \$goto_revision);

  return "/say $getopt_error -- $usage" if defined $getopt_error;
  return $usage if @$args > 2;
  return $usage if not @$args;

  $arguments = join(' ', map { $_ = "'$_'" if $_ =~ m/ /; $_; } @$args);

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, $arguments, 'factredo', explicit => 1, exact_channel => 1);
  return $channel if not defined $trigger; # if $trigger is not defined, $channel is an error message

  my $channel_path = $channel;
  $channel_path  = 'global' if $channel_path eq '.*';

  my $channel_path_safe = safe_filename $channel_path;
  my $trigger_safe = safe_filename $trigger;

  my $path = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/factlog';
  my $undos = eval { retrieve("$path/$trigger_safe.$channel_path_safe.undo"); };

  if (not $undos) {
    return "There are no redos available for [$channel] $trigger.";
  }

  if (defined $list_undos) {
    $list_undos = 1 if $list_undos == 0;
    return $self->list_undo_history($undos, $list_undos);
  }

  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my $admininfo = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
  if ($factoids->{$channel}->{$trigger}->{'locked'}) {
    return "/say $trigger is locked and cannot be reverted." if not defined $admininfo;

    if (exists $factoids->{$channel}->{$trigger}->{'effective-level'}
        and $admininfo->{level} < $factoids->{$channel}->{$trigger}->{'effective-level'}) {
      return "/say $trigger is locked with an effective-level higher than your level and cannot be reverted.";
    }
  }

  if (not defined $goto_revision and $undos->{idx} + 1 == @{$undos->{list}}) {
    return "There are no more redos remaining for [$channel] $trigger.";
  }

  if (defined $goto_revision) {
    return "Don't be absurd." if $goto_revision < 1;
    if ($goto_revision > @{$undos->{list}}) {
      if (@{$undos->{list}} == 1) {
        return "There is only one revision available for [$channel] $trigger.";
      } else {
        return "There are " . @{$undos->{list}} . " revisions available for [$channel] $trigger.";
      }
    }

    if ($goto_revision == $undos->{idx} + 1) {
      return "[$channel] $trigger is already at revision $goto_revision.";
    }

    $undos->{idx} = $goto_revision - 1;
    eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
    $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
  } else {
    $undos->{idx}++;
    eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
    $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
  }

  $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger} = $undos->{list}->[$undos->{idx}];

  my $changes = $self->hash_differences_as_string($undos->{list}->[$undos->{idx} - 1], $undos->{list}->[$undos->{idx}]);
  $self->log_factoid($channel, $trigger, "$nick!$user\@$host", "reverted (redo): $changes", 1);
  return "[$channel] $trigger restored (revision " . ($undos->{idx} + 1) . "): $changes\n";
}

sub factset {
  my $self = shift;
  my ($from, $nick, $user, $host, $args) = @_;

  my ($channel, $trigger, $arguments) = $self->find_factoid_with_optional_channel($from, $args, 'factset', usage => 'Usage: factset [channel] <factoid> [key [value]]', explicit => 1);
  return $channel if not defined $trigger; # if $trigger is not defined, $channel is an error message

  my $arglist = $self->{pbot}->{interpreter}->make_args($arguments);
  my ($key, $value) = $self->{pbot}->{interpreter}->split_args($arglist, 2);

  $channel = '.*' if $channel !~ /^#/;
  my ($owner_channel, $owner_trigger) = $self->{pbot}->{factoids}->find_factoid($channel, $trigger, exact_channel => 1, exact_trigger => 1);

  my $admininfo;
  if (defined $owner_channel) {
    $admininfo  = $self->{pbot}->{admins}->loggedin($owner_channel, "$nick!$user\@$host");
  } else {
    $admininfo  = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
  }

  my $level = 0;
  my $meta_level = 0;

  if (defined $admininfo) {
    $level = $admininfo->{level};
  }

  if (defined $key) {
    if (defined $factoid_metadata_levels{$key}) {
      $meta_level = $factoid_metadata_levels{$key};
    }

    if ($meta_level > 0) {
      if ($level == 0) {
        return "You must login to set '$key'";
      } elsif ($level < $meta_level) {
        return "You must be at least level $meta_level to set '$key'";
      }
    }

    if (defined $value and !$level and $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{'locked'}) {
      return "/say $trigger is locked; unlock before setting.";
    }

    if (lc $key eq 'effective-level' and defined $value and $level > 0) {
      if ($value > $level) {
        return "You cannot set `effective-level` greater than your level, which is $level.";
      } elsif ($value < 0) {
        return "You cannot set a negative effective-level.";
      }

      $self->{pbot}->{factoids}->{factoids}->set($channel, $trigger, 'locked', '1');
    }

    if (lc $key eq 'locked' and exists $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{'effective-level'}) {
      if ($level < $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{'effective-level'}) {
        return "You cannot unlock this factoid because its effective-level is greater than your level.";
      }
    }
  }

  if (defined $owner_channel) {
    my $factoid = $self->{pbot}->{factoids}->{factoids}->hash->{$owner_channel}->{$owner_trigger};

    my $owner;
    my $mask;
    if ($factoid->{'locked'}) {
      # check owner against full hostmask for locked factoids
      $owner = $factoid->{'owner'};
      $mask = "$nick!$user\@$host";
    } else {
      # otherwise just the nick
      ($owner) = $factoid->{'owner'} =~ m/([^!]+)/;
      $mask = $nick;
    }

    if ((defined $value and $key ne 'action') and lc $mask ne lc $owner and $level == 0) {
      return "You are not the owner of $trigger.";
    }
  }

  my $result = $self->{pbot}->{factoids}->{factoids}->set($channel, $trigger, $key, $value);

  if (defined $value and $result =~ m/set to/) {
    $self->log_factoid($channel, $trigger, "$nick!$user\@$host", "set $key to $value");
  }

  return $result;
}

sub factunset {
  my $self = shift;
  my ($from, $nick, $user, $host, $args) = @_;

  my $usage = 'Usage: factunset [channel] <factoid> <key>';

  my ($channel, $trigger, $arguments) = $self->find_factoid_with_optional_channel($from, $args, 'factunset', usage => $usage, explicit => 1);
  return $channel if not defined $trigger; # if $trigger is not defined, $channel is an error message

  my ($key) = $self->{pbot}->{interpreter}->split_line($arguments, strip_quotes => 1);

  return $usage if not length $key;

  my ($owner_channel, $owner_trigger) = $self->{pbot}->{factoids}->find_factoid($channel, $trigger, exact_channel => 1, exact_trigger => 1);

  my $admininfo;

  if (defined $owner_channel) {
    $admininfo = $self->{pbot}->{admins}->loggedin($owner_channel, "$nick!$user\@$host");
  } else {
    $admininfo = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
  }

  my $level = 0;
  my $meta_level = 0;

  if (defined $admininfo) {
    $level = $admininfo->{level};
  }

  if (defined $factoid_metadata_levels{$key}) {
    $meta_level = $factoid_metadata_levels{$key};
  }

  if ($meta_level > 0) {
    if ($level == 0) {
      return "You must login to unset '$key'";
    } elsif ($level < $meta_level) {
      return "You must be at least level $meta_level to unset '$key'";
    }
  }

  if (exists $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{'effective-level'}) {
    if (lc $key eq 'locked') {
      if ($level >= $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{'effective-level'}) {
        $self->{pbot}->{factoids}->{factoids}->unset($channel, $trigger, 'effective-level');
      } else {
        return "You cannot unlock this factoid because its effective-level is higher than your level.";
      }
    } elsif (lc $key eq 'effective-level') {
      if ($level < $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{'effective-level'}) {
        return "You cannot unset the effective-level because it is higher than your level.";
      }
    }
  }

  my $oldvalue;

  if (defined $owner_channel) {
    my $factoid = $self->{pbot}->{factoids}->{factoids}->hash->{$owner_channel}->{$owner_trigger};

    my ($owner) = $factoid->{'owner'} =~ m/([^!]+)/;

    if (lc $nick ne lc $owner and $level == 0) {
      return "You are not the owner of $trigger.";
    }
    $oldvalue = $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger}->{$key};
  }

  return "[$channel] $trigger: key '$key' does not exist." if not defined $oldvalue;

  my $result = $self->{pbot}->{factoids}->{factoids}->unset($channel, $trigger, $key);

  if ($result =~ m/unset/) {
    $self->log_factoid($channel, $trigger, "$nick!$user\@$host", "unset $key (value: $oldvalue)");
  }

  return $result;
}

sub list {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $text;

  my $usage = "Usage: list <modules|commands|admins>";

  if (not defined $arguments) {
    return $usage;
  }

  if ($arguments =~ /^modules$/i) {
    $text = "Loaded modules: ";
    foreach my $channel (sort keys %{ $self->{pbot}->{factoids}->{factoids}->hash }) {
      foreach my $command (sort keys %{ $self->{pbot}->{factoids}->{factoids}->hash->{$channel} }) {
        if ($self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$command}->{type} eq 'module') {
          $text .= "$command ";
        }
      }
    }
    return $text;
  }

  if ($arguments =~ /^commands$/i) {
    $text = "Registered commands: ";
    foreach my $command (sort { $a->{name} cmp $b->{name} } @{ $self->{pbot}->{commands}->{handlers} }) {
      $text .= "$command->{name} ";
      $text .= "($command->{level}) " if $command->{level} > 0;
    }
    return $text;
  }

  if ($arguments =~ /^admins$/i) {
    $text = "Admins: ";
    my $last_channel = "";
    my $sep = "";
    foreach my $channel (sort keys %{ $self->{pbot}->{admins}->{admins}->hash }) {
      next if $from =~ m/^#/ and $channel ne $from and $channel ne '.*';
      if ($last_channel ne $channel) {
        $text .= $sep . ($channel eq ".*" ? "all" : $channel) . ": ";
        $last_channel = $channel;
        $sep = "";
      }
      foreach my $hostmask (sort keys %{ $self->{pbot}->{admins}->{admins}->hash->{$channel} }) {
        $text .= $sep;
        $text .= "*" if $self->{pbot}->{admins}->{admins}->hash->{$channel}->{$hostmask}->{loggedin};
        $text .= $self->{pbot}->{admins}->{admins}->hash->{$channel}->{$hostmask}->{name} . " (" . $self->{pbot}->{admins}->{admins}->hash->{$channel}->{$hostmask}->{level} . ")";
        $sep = "; ";
      }
    }
    return $text;
  }
  return $usage;
}

sub factmove {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($src_channel, $source, $target_channel, $target) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 5);

  my $usage = "Usage: factmove <source channel> <source factoid> <target channel/factoid> [target factoid]";

  if (not defined $target_channel) {
    return $usage;
  }

  if ($target_channel !~ /^#/ and $target_channel ne '.*') {
    if (defined $target) {
      return "Unexpected argument '$target' when renaming to '$target_channel'. Perhaps '$target_channel' is missing #s? $usage";
    }

    $target = $target_channel;
    $target_channel = $src_channel;
  } else {
    if (not defined $target) {
      $target = $source;
    }
  }

  if (length $target > $self->{pbot}->{registry}->get_value('factoids', 'max_name_length')) {
    return "/say $nick: I don't think the factoid name needs to be that long.";
  }

  if (length $target_channel > $self->{pbot}->{registry}->get_value('factoids', 'max_channel_length')) {
    return "/say $nick: I don't think the channel name needs to be that long.";
  }

  my ($found_src_channel, $found_source) = $self->{pbot}->{factoids}->find_factoid($src_channel, $source, exact_channel => 1, exact_trigger => 1);

  if (not defined $found_src_channel) {
    return "Source factoid $source not found in channel $src_channel";
  }

  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my ($owner) = $factoids->{$found_src_channel}->{$found_source}->{'owner'} =~ m/([^!]+)/;

  if ((lc $nick ne lc $owner) and (not $self->{pbot}->{admins}->loggedin($found_src_channel, "$nick!$user\@$host"))) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempted to move [$found_src_channel] $found_source (not owner)\n");
    my $chan = ($found_src_channel eq '.*' ? 'the global channel' : $found_src_channel);
    return "You are not the owner of $found_source for $chan";
  }

  if ($factoids->{$found_src_channel}->{$found_source}->{'locked'}) {
    return "/say $found_source is locked; unlock before moving.";
  }

  my ($found_target_channel, $found_target) = $self->{pbot}->{factoids}->find_factoid($target_channel, $target, exact_channel => 1, exact_trigger => 1);

  if (defined $found_target_channel) {
    return "Target factoid $target already exists in channel $target_channel";
  }

  my ($overchannel, $overtrigger) = $self->{pbot}->{factoids}->find_factoid('.*', $target, exact_channel => 1, exact_trigger => 1);
  if (defined $overtrigger and $self->{pbot}->{factoids}->{factoids}->hash->{'.*'}->{$overtrigger}->{'nooverride'}) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempt to override $target\n");
    return "/say $target already exists for the global channel and cannot be overridden for " . ($target_channel eq '.*' ? 'the global channel' : $target_channel) . ".";
  }

  if ($self->{pbot}->{commands}->exists($target)) {
    return "/say $target already exists as a built-in command.";
  }

  $target_channel = lc $target_channel;
  $target_channel = '.*' if $target_channel !~ /^#/;

  $factoids->{$target_channel}->{$target} = $factoids->{$found_src_channel}->{$found_source};
  delete $factoids->{$found_src_channel}->{$found_source};

  $self->{pbot}->{factoids}->save_factoids;

  $found_src_channel = 'global' if $found_src_channel eq '.*';
  $target_channel = 'global' if $target_channel eq '.*';

  if ($src_channel eq $target_channel) {
    $self->log_factoid($found_src_channel, $found_source, "$nick!$user\@$host", "renamed from $found_source to $target");
    $self->log_factoid($target_channel, $target, "$nick!$user\@$host", "renamed from $found_source to $target");
    return "[$found_src_channel] $found_source renamed to $target";
  } else {
    $self->log_factoid($found_src_channel, $found_source, "$nick!$user\@$host", "moved from $found_src_channel/$found_source to $target_channel/$target");
    $self->log_factoid($target_channel, $target, "$nick!$user\@$host", "moved from $found_src_channel/$found_source to $target_channel/$target");
    return "[$found_src_channel] $found_source moved to [$target_channel] $target";
  }
}

sub factalias {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;

  my ($chan, $alias, $command) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 3);

  if (defined $chan and not ($chan eq '.*' or $chan =~ m/^#/)) {
    # $chan doesn't look like a channel, so shift everything right
    # and replace $chan with $from
    if (defined $command and length $command) {
      $command = "$alias $command";
    } else {
      $command = $alias;
    }
    $alias = $chan;
    $chan = $from;
  }

  $chan = '.*' if $chan !~ /^#/;

  if (not length $alias or not length $command) {
    return "Usage: factalias [channel] <keyword> <command>";
  }

  if (length $alias > $self->{pbot}->{registry}->get_value('factoids', 'max_name_length')) {
    return "/say $nick: I don't think the factoid name needs to be that long.";
  }

  if (length $chan > $self->{pbot}->{registry}->get_value('factoids', 'max_channel_length')) {
    return "/say $nick: I don't think the channel name needs to be that long.";
  }

  my ($channel, $alias_trigger) = $self->{pbot}->{factoids}->find_factoid($chan, $alias, exact_channel => 1, exact_trigger => 1);

  if (defined $alias_trigger) {
    $self->{pbot}->{logger}->log("attempt to overwrite existing command\n");
    return "'$alias_trigger' already exists for channel $channel";
  }

  my ($overchannel, $overtrigger) = $self->{pbot}->{factoids}->find_factoid('.*', $alias, exact_channel => 1, exact_trigger => 1);
  if (defined $overtrigger and $self->{pbot}->{factoids}->{factoids}->hash->{'.*'}->{$overtrigger}->{'nooverride'}) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempt to override $alias\n");
    return "/say $alias already exists for the global channel and cannot be overridden for " . ($chan eq '.*' ? 'the global channel' : $chan) . ".";
  }

  if ($self->{pbot}->{commands}->exists($alias)) {
    return "/say $alias already exists as a built-in command.";
  }

  $self->{pbot}->{factoids}->add_factoid('text', $chan, "$nick!$user\@$host", $alias, "/call $command");

  $self->{pbot}->{logger}->log("$nick!$user\@$host [$chan] aliased $alias => $command\n");
  $self->{pbot}->{factoids}->save_factoids();
  return "'$alias' aliases '$command' for " . ($chan eq '.*' ? 'the global channel' : $chan);
}

sub add_regex {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my ($keyword, $text) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  $from = '.*' if not defined $from or $from !~ /^#/;

  if (not defined $keyword) {
    $text = "";
    foreach my $trigger (sort keys %{ $factoids->{$from} }) {
      if ($factoids->{$from}->{$trigger}->{type} eq 'regex') {
        $text .= $trigger . " ";
      }
    }
    return "Stored regexs for channel $from: $text";
  }

  if (not defined $text) {
    return "Usage: regex <regex> <command>";
  }

  my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($from, $keyword, exact_channel => 1, exact_trigger => 1);

  if (defined $trigger) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempt to overwrite $trigger\n");
    return "/say $trigger already exists for channel $channel.";
  }

  $self->{pbot}->{factoids}->add_factoid('regex', $from, "$nick!$user\@$host", $keyword, $text);
  $self->{pbot}->{logger}->log("$nick!$user\@$host added [$keyword] => [$text]\n");
  return "/say $keyword added.";
}

sub factadd {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my ($from_chan, $keyword, $text, $force);

  my @arglist = @{$stuff->{arglist}};

  if (@arglist) {
    # check for -f since we allow it to be before optional channel argument
    if ($arglist[0] eq '-f') {
      $force = 1;
      $self->{pbot}->{interpreter}->shift_arg(\@arglist);
    }

    # check if this is an optional channel argument
    if ($arglist[0] =~ m/(?:^#|^global$|^\.\*$)/i) {
      $from_chan = $self->{pbot}->{interpreter}->shift_arg(\@arglist);
    } else {
      $from_chan = $from;
    }

    # check for -f again since we also allow it to appear after the channel argument
    if ($arglist[0] eq '-f') {
      $force = 1;
      $self->{pbot}->{interpreter}->shift_arg(\@arglist);
    }

    # now this is the keyword
    $keyword = $self->{pbot}->{interpreter}->shift_arg(\@arglist);

    # check for -url
    if ($arglist[0] eq '-url') {
      # discard it
      $self->{pbot}->{interpreter}->shift_arg(\@arglist);

      # the URL is the remaining arguments
      my ($url) = $self->{pbot}->{interpreter}->split_args(\@arglist, 1);

      if ($url !~ m/^https?:\/\/(?:sprunge.us|ix.io)\/\w+$/) {
        return "Invalid URL: acceptable URLs are: http://sprunge.us, http://ix.io";
      }

      # create a UserAgent
      my $ua = LWP::UserAgent->new(timeout => 10);

      # get the factoid's text from the URL
      my $response = $ua->get($url);

      # process the response
      if ($response->is_success) {
        $text = $response->decoded_content;
      } else {
        return "Failed to get URL: " . $response->status_line;
      }
    } else {
      # check for optional "is" and discard
      if (lc $arglist[0] eq 'is') {
        $self->{pbot}->{interpreter}->shift_arg(\@arglist);
      }

      # and the text is the remaining arguments with quotes preserved
      ($text) = $self->{pbot}->{interpreter}->split_args(\@arglist, 1);
    }
  }

  if (not defined $from_chan or not defined $text or not defined $keyword) {
    return "Usage: factadd [-f] [channel] <keyword> (<factoid> | -url <paste site>); -f to force overwrite; -url to download from paste site";
  }

  $from_chan = '.*' if $from_chan !~ /^#/;

  if (length $keyword > $self->{pbot}->{registry}->get_value('factoids', 'max_name_length')) {
    return "/say $nick: I don't think the factoid name needs to be that long.";
  }

  if (length $from_chan > $self->{pbot}->{registry}->get_value('factoids', 'max_channel_length')) {
    return "/say $nick: I don't think the channel needs to be that long.";
  }

  $from_chan = '.*' if lc $from_chan eq 'global';
  $from_chan = '.*' if not $from_chan =~ m/^#/;

  my $keyword_text = $keyword =~ / / ? "\"$keyword\"" : $keyword;

  my ($channel, $trigger)  = $self->{pbot}->{factoids}->find_factoid($from_chan, $keyword, exact_channel => 1, exact_trigger => 1);
  if (defined $trigger) {
    if (not $force) {
      $self->{pbot}->{logger}->log("$nick!$user\@$host attempt to overwrite $keyword\n");
      return "/say $keyword_text already exists for " . ($from_chan eq '.*' ? 'the global channel' : $from_chan) . ".";
    } else {
      my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

      if ($factoids->{$channel}->{$trigger}->{'locked'}) {
        return "/say $keyword_text is locked; unlock before overwriting.";
      }

      my ($owner) = $factoids->{$channel}->{$trigger}->{'owner'} =~ m/([^!]+)/;

      if ((lc $nick ne lc $owner) and (not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host"))) {
        $self->{pbot}->{logger}->log("$nick!$user\@$host attempted to overwrite $trigger [not owner]\n");
        my $chan = ($channel eq '.*' ? 'the global channel' : $channel);
        return "You are not the owner of $keyword_text for $chan; cannot overwrite";
      }
    }
  }

  ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid('.*', $keyword, exact_channel => 1, exact_trigger => 1);
  if (defined $trigger and $self->{pbot}->{factoids}->{factoids}->hash->{'.*'}->{$trigger}->{'nooverride'}) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempt to override $keyword_text\n");
    return "/say $keyword_text already exists for the global channel and cannot be overridden for " . ($from_chan eq '.*' ? 'the global channel' : $from_chan) . ".";
  }

  if ($self->{pbot}->{commands}->exists($keyword)) {
    return "/say $keyword_text already exists as a built-in command.";
  }

  $self->{pbot}->{factoids}->add_factoid('text', $from_chan, "$nick!$user\@$host", $keyword, $text);

  $self->{pbot}->{logger}->log("$nick!$user\@$host added [$from_chan] $keyword_text => $text\n");
  return "/say $keyword_text added to " . ($from_chan eq '.*' ? 'global channel' : $from_chan) . ".";
}

sub factrem {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my ($from_chan, $from_trig) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (not defined $from_trig) {
    $from_trig = $from_chan;
    $from_chan = $from;
  }

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, $arguments, 'factrem', explicit => 1);
  return $channel if not defined $trigger; # if $trigger is not defined, $channel is an error message

  $channel = '.*' if $channel eq 'global';
  $from_chan = '.*' if $channel eq 'global';

  my $trigger_text = $trigger =~ / / ? "\"$trigger\"" : $trigger;

  if ($factoids->{$channel}->{$trigger}->{type} eq 'module') {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempted to remove $trigger_text [not factoid]\n");
    return "/say $trigger_text is not a factoid.";
  }

  if ($channel =~ /^#/ and $from_chan =~ /^#/ and $channel ne $from_chan) {
    return "/say $trigger_text belongs to $channel, but this is $from_chan. Please switch to $channel or /msg to remove this factoid.";
  }

  my ($owner) = $factoids->{$channel}->{$trigger}->{'owner'} =~ m/([^!]+)/;

  if ((lc $nick ne lc $owner) and (not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host"))) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempted to remove $trigger_text [not owner]\n");
    my $chan = ($channel eq '.*' ? 'the global channel' : $channel);
    return "You are not the owner of $trigger_text for $chan";
  }

  if ($factoids->{$channel}->{$trigger}->{'locked'}) {
    return "/say $trigger_text is locked; unlock before deleting.";
  }

  $self->{pbot}->{logger}->log("$nick!$user\@$host removed [$channel][$trigger][" . $factoids->{$channel}->{$trigger}->{action} . "]\n");
  $self->{pbot}->{factoids}->remove_factoid($channel, $trigger);
  $self->log_factoid($channel, $trigger, "$nick!$user\@$host", "deleted", 1);
  return "/say $trigger_text removed from " . ($channel eq '.*' ? 'the global channel' : $channel) . ".";
}

sub histogram {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my %hash;
  my $factoid_count = 0;

  foreach my $channel (keys %$factoids) {
    foreach my $command (keys %{ $factoids->{$channel} }) {
      if ($factoids->{$channel}->{$command}->{type} eq 'text') {
        $hash{$factoids->{$channel}->{$command}->{owner}}++;
        $factoid_count++;
      }
    }
  }

  my $text;
  my $i = 0;

  foreach my $owner (sort {$hash{$b} <=> $hash{$a}} keys %hash) {
    my $percent = int($hash{$owner} / $factoid_count * 100);
    $text .= "$owner: $hash{$owner} ($percent". "%)\n";
    $i++;
    last if $i >= 10;
  }
  return "/say $factoid_count factoids, top 10 submitters:\n$text";
}

sub factshow {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  $stuff->{preserve_whitespace} = 1;

  my $usage = "Usage: factshow [-p] [channel] <keyword>; -p to paste";
  return $usage if not $arguments;

  my $getopt_error;
  local $SIG{__WARN__} = sub {
    $getopt_error = shift;
    chomp $getopt_error;
  };

  my ($paste);
  my ($ret, $args) = GetOptionsFromString($arguments,
    'p'  => \$paste);

  return "/say $getopt_error -- $usage" if defined $getopt_error;
  return "Too many arguments -- $usage" if @$args > 2;
  return "Missing argument -- $usage" if not @$args;

  my ($chan, $trig) = @$args;

  if (not defined $trig) {
    $chan = $from;
  }

  $args = join(' ', map { $_ = "'$_'" if $_ =~ m/ /; $_; } @$args);

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, $args, 'factshow', usage => $usage);
  return $channel if not defined $trigger; # if $trigger is not defined, $channel is an error message

  my $trigger_text = $trigger =~ / / ? "\"$trigger\"" : $trigger;

  my $result = "$trigger_text: ";

  if ($paste) {
    $result .= $self->{pbot}->{webpaste}->paste($factoids->{$channel}->{$trigger}->{action}, no_split => 1);
    $channel = 'global' if $channel eq '.*';
    $chan = 'global' if $chan eq '.*';
    $result = "[$channel] $result" if $channel ne $chan;
    return $result;
  }

  $result .= $factoids->{$channel}->{$trigger}->{action};

  if ($factoids->{$channel}->{$trigger}->{type} eq 'module') {
    $result .= ' [module]';
  }

  $channel = 'global' if $channel eq '.*';
  $chan = 'global' if $chan eq '.*';
  $result = "[$channel] $result" if $channel ne $chan;
  return $result;
}

sub factlog {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  my $usage = "Usage: factlog [-h] [-t] [channel] <keyword>; -h show full hostmask; -t show actual timestamp instead of relative";

  return $usage if not $arguments;

  my $getopt_error;
  local $SIG{__WARN__} = sub {
    $getopt_error = shift;
    chomp $getopt_error;
  };

  my ($show_hostmask, $actual_timestamp);
  my ($ret, $args) = GetOptionsFromString($arguments,
    'h'  => \$show_hostmask,
    't'  => \$actual_timestamp);

  return "/say $getopt_error -- $usage" if defined $getopt_error;
  return "Too many arguments -- $usage" if @$args > 2;
  return "Missing argument -- $usage" if not @$args;

  $args = join(' ', map { $_ = "'$_'" if $_ =~ m/ /; $_; } @$args);

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, $args, 'factlog', usage => $usage, exact_channel => 1);

  if (not defined $trigger) {
    # factoid not found or some error, try to continue and load factlog file if it exists
    my $arglist = $self->{pbot}->{interpreter}->make_args($args);
    ($channel, $trigger) = $self->{pbot}->{interpreter}->split_args($arglist, 2);
    if (not defined $trigger) {
      $trigger = $channel;
      $channel = $from;
    }
    $channel = '.*' if $channel !~ m/^#/;
  }

  my $path = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/factlog';

  $channel = 'global' if $channel eq '.*';

  my $channel_safe = safe_filename $channel;
  my $trigger_safe = safe_filename $trigger;

  open my $fh, "< $path/$trigger_safe.$channel_safe" or do {
    $self->{pbot}->{logger}->log("Could not open $path/$trigger_safe.$channel_safe: $!\n");
    $channel = 'the global channel' if $channel eq 'global';
    return "No factlog available for $trigger in $channel.";
  };

  my @entries;
  while (my $line = <$fh>) {
    my ($timestamp, $hostmask, $msg);

    ($timestamp, $hostmask, $msg) = eval {
      my $h = decode_json $line;
      return ($h->{ts}, $h->{hm}, $h->{msg});
    };

    if ($@) {
      ($timestamp, $hostmask, $msg) = split /\s+/, $line, 3;
    }

    if (not $show_hostmask) {
      $hostmask =~ s/!.*$//;
    }

    if ($actual_timestamp) {
      $timestamp = strftime "%a %b %e %H:%M:%S %Z %Y", localtime $timestamp;
    } else {
      $timestamp = concise ago gettimeofday - $timestamp;
    }

    push @entries, "[$timestamp] $hostmask $msg\n";
  }
  close $fh;

  my $result = join "", reverse @entries;
  return $result;
}

sub factinfo {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my ($chan, $trig) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (not defined $trig) {
    $trig = $chan;
    $chan = $from;
  }

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, $arguments, 'factinfo');
  return $channel if not defined $trigger; # if $trigger is not defined, $channel is an error message

  my $created_ago = ago(gettimeofday - $factoids->{$channel}->{$trigger}->{created_on});
  my $ref_ago = ago(gettimeofday - $factoids->{$channel}->{$trigger}->{last_referenced_on}) if defined $factoids->{$channel}->{$trigger}->{last_referenced_on};

  $chan = ($channel eq '.*' ? 'global channel' : $channel);

  # factoid
  if ($factoids->{$channel}->{$trigger}->{type} eq 'text') {
    return "/say $trigger: Factoid submitted by " . $factoids->{$channel}->{$trigger}->{owner} . " for $chan on " . localtime($factoids->{$channel}->{$trigger}->{created_on}) . " [$created_ago], " . (defined $factoids->{$channel}->{$trigger}->{edited_by} ? "last edited by $factoids->{$channel}->{$trigger}->{edited_by} on " . localtime($factoids->{$channel}->{$trigger}->{edited_on}) . " [" . ago(gettimeofday - $factoids->{$channel}->{$trigger}->{edited_on}) . "], " : "") . "referenced " . $factoids->{$channel}->{$trigger}->{ref_count} . " times (last by " . $factoids->{$channel}->{$trigger}->{ref_user} . (exists $factoids->{$channel}->{$trigger}->{last_referenced_on} ? " on " . localtime($factoids->{$channel}->{$trigger}->{last_referenced_on}) . " [$ref_ago]" : "") . ")";
  }

  # module
  if ($factoids->{$channel}->{$trigger}->{type} eq 'module') {
    my $module_repo = $self->{pbot}->{registry}->get_value('general', 'module_repo');
    $module_repo .= "$factoids->{$channel}->{$trigger}->{workdir}/" if exists $factoids->{$channel}->{$trigger}->{workdir};
    return "/say $trigger: Module loaded by " . $factoids->{$channel}->{$trigger}->{owner} . " for $chan on " . localtime($factoids->{$channel}->{$trigger}->{created_on}) . " [$created_ago] -> $module_repo" . $factoids->{$channel}->{$trigger}->{action} . ", used " . $factoids->{$channel}->{$trigger}->{ref_count} . " times (last by " . $factoids->{$channel}->{$trigger}->{ref_user} . (exists $factoids->{$channel}->{$trigger}->{last_referenced_on} ? " on " . localtime($factoids->{$channel}->{$trigger}->{last_referenced_on}) . " [$ref_ago]" : "") . ")";
  }

  # regex
  if ($factoids->{$channel}->{$trigger}->{type} eq 'regex') {
    return "/say $trigger: Regex created by " . $factoids->{$channel}->{$trigger}->{owner} . " for $chan on " . localtime($factoids->{$channel}->{$trigger}->{created_on}) . " [$created_ago], " . (defined $factoids->{$channel}->{$trigger}->{edited_by} ? "last edited by $factoids->{$channel}->{$trigger}->{edited_by} on " . localtime($factoids->{$channel}->{$trigger}->{edited_on}) . " [" . ago(gettimeofday - $factoids->{$channel}->{$trigger}->{edited_on}) . "], " : "") . " used " . $factoids->{$channel}->{$trigger}->{ref_count} . " times (last by " . $factoids->{$channel}->{$trigger}->{ref_user} . (exists $factoids->{$channel}->{$trigger}->{last_referenced_on} ? " on " . localtime($factoids->{$channel}->{$trigger}->{last_referenced_on}) . " [$ref_ago]" : "") . ")";
  }

  return "/say $arguments is not a factoid or a module";
}

sub top20 {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my %hash = ();
  my $text = "";
  my $i = 0;

  my ($channel, $args) = $self->{pbot}->{interpreter}->split_args($stuff->{arglist}, 2);

  if (not defined $channel) {
    return "Usage: top20 <channel> [nick or 'recent']";
  }

  if (not defined $args) {
    foreach my $chan (sort keys %{ $factoids }) {
      next if lc $chan ne lc $channel;
      foreach my $command (sort {$factoids->{$chan}->{$b}{ref_count} <=> $factoids->{$chan}->{$a}{ref_count}} keys %{ $factoids->{$chan} }) {
        if ($factoids->{$chan}->{$command}{ref_count} > 0 and $factoids->{$chan}->{$command}{type} eq 'text') {
          $text .= "$command ($factoids->{$chan}->{$command}{ref_count}) ";
          $i++;
          last if $i >= 20;
        }
      }
      $channel = "the global channel" if $channel eq '.*';
      $text = "Top $i referenced factoids for $channel: $text" if $i > 0;
      return $text;
    }
  } else {
    if (lc $args eq "recent") {
      foreach my $chan (sort keys %{ $factoids }) {
        next if lc $chan ne lc $channel;
        foreach my $command (sort { $factoids->{$chan}->{$b}{created_on} <=> $factoids->{$chan}->{$a}{created_on} } keys %{ $factoids->{$chan} }) {
          my $ago = concise ago gettimeofday - $factoids->{$chan}->{$command}->{created_on};
          my $owner = $factoids->{$chan}->{$command}->{owner};
          $owner =~ s/!.*$//;
          $text .= "   $command [$ago by $owner]\n";
          $i++;
          last if $i >= 50;
        }
        $channel = "global channel" if $channel eq '.*';
        $text = "$i most recent $channel submissions:\n\n$text" if $i > 0;
        return $text;
      }
    }

    my $user = lc $args;
    foreach my $chan (sort keys %{ $factoids }) {
      next if lc $chan ne lc $channel;
      foreach my $command (sort { ($factoids->{$chan}->{$b}{last_referenced_on} || 0) <=> ($factoids->{$chan}->{$a}{last_referenced_on} || 0) } keys %{ $factoids->{$chan} }) {
        if ($factoids->{$chan}->{$command}{ref_user} =~ /\Q$args\E/i) {
          if ($user ne lc $factoids->{$chan}->{$command}{ref_user} && not $user =~ /$factoids->{$chan}->{$command}{ref_user}/i) {
            $user .= " ($factoids->{$chan}->{$command}{ref_user})";
          }
          my $ago = $factoids->{$chan}->{$command}{last_referenced_on} ? ago(gettimeofday - $factoids->{$chan}->{$command}{last_referenced_on}) : "unknown";
          $text .= "   $command [$ago]\n";
          $i++;
          last if $i >= 20;
        }
      }
      $text = "$i factoids last referenced by $user:\n\n$text" if $i > 0;
      return $text;
    }
  }
}

sub count {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my $i = 0;
  my $total = 0;

  if (not length $arguments) {
    return "Usage: count <nick|factoids>";
  }

  $arguments = ".*" if ($arguments =~ /^factoids$/);

  eval {
    foreach my $channel (keys %{ $factoids }) {
      foreach my $command (keys %{ $factoids->{$channel} }) {
        next if $factoids->{$channel}->{$command}->{type} ne 'text';
        $total++;
        if ($factoids->{$channel}->{$command}->{owner} =~ /^\Q$arguments\E$/i) {
          $i++;
        }
      }
    }
  };
  return "/msg $nick $arguments: $@" if $@;

  return "I have $i factoids." if $arguments eq ".*";

  if ($i > 0) {
    my $percent = int($i / $total * 100);
    $percent = 1 if $percent == 0;
    return "/say $arguments has submitted $i factoids out of $total ($percent"."%)";
  } else {
    return "/say $arguments hasn't submitted any factoids";
  }
}

sub factfind {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my $usage = "Usage: factfind [-channel channel] [-owner regex] [-editby regex] [-refby regex] [-regex] [text]";

  if (not defined $arguments) {
    return $usage;
  }

  my ($channel, $owner, $refby, $editby, $use_regex);

  $channel = $1 if $arguments =~ s/\s*-channel\s+([^\b\s]+)//i;
  $owner = $1 if $arguments =~ s/\s*-owner\s+([^\b\s]+)//i;
  $refby = $1 if $arguments =~ s/\s*-refby\s+([^\b\s]+)//i;
  $editby = $1 if $arguments =~ s/\s*-editby\s+([^\b\s]+)//i;
  $use_regex = 1 if $arguments =~ s/\s*-regex\b//i;

  $owner = '.*' if not defined $owner;
  $refby = '.*' if not defined $refby;
  $editby = '.*' if not defined $editby;

  $arguments =~ s/^\s+//;
  $arguments =~ s/\s+$//;
  $arguments =~ s/\s+/ /g;

  $arguments = substr($arguments, 0, 30);

  my $argtype = undef;

  if ($owner ne '.*') {
    $argtype = "owned by $owner";
  }

  if ($refby ne '.*') {
    if (not defined $argtype) {
      $argtype = "last referenced by $refby";
    } else {
      $argtype .= " and last referenced by $refby";
    }
  }

  if ($editby ne '.*') {
    if (not defined $argtype) {
      $argtype = "last edited by $editby";
    } else {
      $argtype .= " and last edited by $editby";
    }
  }

  if ($arguments ne "") {
    my $unquoted_args = $arguments;
    $unquoted_args =~ s/(?:\\(?!\\))//g;
    $unquoted_args =~ s/(?:\\\\)/\\/g;
    if (not defined $argtype) {
      $argtype = "with text containing '$unquoted_args'";
    } else {
      $argtype .= " and with text containing '$unquoted_args'";
    }
  }

  if (not defined $argtype) {
    return $usage;
  }

  my ($text, $last_trigger, $last_chan, $i);
  $last_chan = "";
  $i = 0;
  eval {
    use re::engine::RE2 -strict => 1;
    my $regex;
    if ($use_regex) {
      $regex = $arguments;
    } else {
      $regex = ($arguments =~ m/^\w/) ? '\b' : '\B';
      $regex .= quotemeta $arguments;
      $regex .= ($arguments =~ m/\w$/) ? '\b' : '\B';
    }

    foreach my $chan (sort keys %{ $factoids }) {
      next if defined $channel and $chan !~ /^$channel$/i;
      foreach my $trigger (sort keys %{ $factoids->{$chan} }) {
        if ($factoids->{$chan}->{$trigger}->{type} eq 'text' or $factoids->{$chan}->{$trigger}->{type} eq 'regex') {
          if ($factoids->{$chan}->{$trigger}->{owner} =~ /^$owner$/i
            && $factoids->{$chan}->{$trigger}->{ref_user} =~ /^$refby$/i
            && (exists $factoids->{$chan}->{$trigger}->{edited_by} ? $factoids->{$chan}->{$trigger}->{edited_by} =~ /^$editby$/i : 1)) {
            next if ($arguments ne "" && $factoids->{$chan}->{$trigger}->{action} !~ /$regex/i && $trigger !~ /$regex/i);

            $i++;

            if ($chan ne $last_chan) {
              $text .= $chan eq '.*' ? "[global channel] " : "[$chan] ";
              $last_chan = $chan;
            }
            if ($trigger =~ / /) {
              $text .= "\"$trigger\" ";
            } else {
              $text .= "$trigger ";
            }
            $last_trigger = $trigger;
          }
        }
      }
    }
  };

  return "/msg $nick $arguments: $@" if $@;

  if ($i == 1) {
    chop $text;
    return "Found one factoid submitted for " . ($last_chan eq '.*' ? 'global channel' : $last_chan) . " " . $argtype . ": $last_trigger is $factoids->{$last_chan}->{$last_trigger}->{action}";
  } else {
    return "Found $i factoids " . $argtype . ": $text" unless $i == 0;

    my $chans = (defined $channel ? ($channel eq '.*' ? 'global channel' : $channel) : 'any channels');
    return "No factoids " . $argtype . " submitted for $chans";
  }
}

sub factchange {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments, $stuff) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my ($channel, $trigger, $keyword, $delim, $tochange, $changeto, $modifier, $url);

  $stuff->{preserve_whitespace} = 1;

  my $needs_disambig;

  if (length $arguments) {
    my $args = $stuff->{arglist};
    my $sub;

    my $arg_count = $self->{pbot}->{interpreter}->arglist_size($args);

    if ($arg_count >= 4 and ($args->[0] =~ m/^#/ or $args->[0] eq '.*' or lc $args->[0] eq 'global') and ($args->[2] eq '-url')) {
      $channel = $args->[0];
      $keyword = $args->[1];
      $url = $args->[3];
      $needs_disambig = 0;
    } elsif ($arg_count >= 3 and $args->[1] eq '-url') {
      $keyword = $args->[0];
      $url = $args->[2];
      $channel = $from;
      $needs_disambig = 1;
    } elsif ($arg_count >= 3 and ($args->[0] =~ m/^#/ or $args->[0] eq '.*' or lc $args->[0] eq 'global') and ($args->[2] =~ m/^s([[:punct:]])/)) {
      $delim = $1;
      $channel = $args->[0];
      $keyword = $args->[1];
      ($sub) = $self->{pbot}->{interpreter}->split_args($args, 1, 2);
      $needs_disambig = 0;
    } elsif ($arg_count >= 2 and $args->[1] =~ m/^s([[:punct:]])/) {
      $delim = $1;
      $keyword = $args->[0];
      $channel = $from;
      ($sub) = $self->{pbot}->{interpreter}->split_args($args, 1, 1);
      $needs_disambig = 1;
    }

    if (defined $sub) {
      $delim = quotemeta $delim;

      if ($sub =~ /^s$delim(.*?)$delim(.*)$delim(.*)$/) {
        $tochange = $1;
        $changeto = $2;
        $modifier  = $3;
      } elsif ($sub =~ /^s$delim(.*?)$delim(.*)$/) {
        $tochange = $1;
        $changeto = $2;
        $modifier  = '';
      }
    }
  }

  if (not defined $channel or (not defined $changeto and not defined $url)) {
    return "Usage: factchange [channel] <keyword> (s/<pattern>/<replacement>/ | -url <paste site>)";
  }

  my ($from_trigger, $from_chan) = ($keyword, $channel);
  my @factoids = $self->{pbot}->{factoids}->find_factoid($from_chan, $keyword, exact_trigger => 1);

  if (not @factoids or not $factoids[0]) {
    $from_chan = 'global channel' if $from_chan eq '.*';
    return "/say $keyword not found in $from_chan";
  }

  if (@factoids > 1) {
    if (not grep { $_->[0] eq $from_chan } @factoids) {
      return "/say $from_trigger found in multiple channels: " . (join ', ', sort map { $_->[0] eq '.*' ? 'global' : $_->[0] } @factoids) . "; use `factchange <channel> $from_trigger` to disambiguate.";
    } else {
      foreach my $factoid (@factoids) {
        if ($factoid->[0] eq $from_chan) {
          ($channel, $trigger) = ($factoid->[0], $factoid->[1]);
          last;
        }
      }
    }
  } else {
    ($channel, $trigger) = ($factoids[0]->[0], $factoids[0]->[1]);
  }

  if (not defined $trigger) {
    return "/say $keyword not found in channel $from_chan.";
  }

  $from_chan = '.*' if $from_chan eq 'global';

  if ($channel =~ /^#/ and $from_chan =~ /^#/ and $channel ne $from_chan) {
    return "/say $trigger belongs to $channel, but this is $from_chan. Please switch to $channel or use /msg to change this factoid.";
  }

  my $admininfo = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
  if ($factoids->{$channel}->{$trigger}->{'locked'}) {
    return "/say $trigger is locked and cannot be changed." if not defined $admininfo;

    if (exists $factoids->{$channel}->{$trigger}->{'effective-level'}
        and $admininfo->{level} < $factoids->{$channel}->{$trigger}->{'effective-level'}) {
      return "/say $trigger is locked with an effective-level higher than your level and cannot be changed.";
    }
  }

  my $action = $factoids->{$channel}->{$trigger}->{action};

  if (defined $url) {
    if ($url !~ m/^https?:\/\/(?:sprunge.us|ix.io)\/\w+$/) {
      return "Invalid URL: acceptable URLs are: http://sprunge.us, http://ix.io";
    }

    my $ua = LWP::UserAgent->new(timeout => 10);
    my $response = $ua->get($url);

    if ($response->is_success) {
      $action = $response->decoded_content;
    } else {
      return "Failed to get URL: " . $response->status_line;
    }
  } else {
    my $ret = eval {
      use re::engine::RE2 -strict => 1;
      my $changed;

      if ($modifier eq 'gi' or $modifier eq 'ig' or $modifier eq 'g') {
        my @chars = ("A".."Z", "a".."z", "0".."9");
        my $magic = '';
        $magic .= $chars[rand @chars] for 1..(10 * rand) + 10;
        my $insensitive = index ($modifier, 'i') + 1;
        my $count = 0;
        my $max = 50;

        while (1) {
          if ($count == 0) {
            if ($insensitive) {
              $changed = $action =~ s|$tochange|$changeto$magic|i;
            } else {
              $changed = $action =~ s|$tochange|$changeto$magic|;
            }
          } else {
            if ($insensitive) {
              $changed = $action =~ s|$tochange|$1$changeto$magic|i;
            } else {
              $changed = $action =~ s|$tochange|$1$changeto$magic|;
            }
          }

          if ($changed) {
            $count++;
            if ($count == $max) {
              $action =~ s/$magic//;
              last;
            }
            $tochange = "$magic(.*?)$tochange" if $count == 1;
          } else {
            $changed = $count;
            $action =~ s/$magic// if $changed;
            last;
          }
        }
      } elsif ($modifier eq 'i') {
        $changed = $action =~ s|$tochange|$changeto|i;
      } else {
        $changed = $action =~ s|$tochange|$changeto|;
      }

      if (not $changed) {
        $self->{pbot}->{logger}->log("($from) $nick!$user\@$host: failed to change '$trigger' 's$delim$tochange$delim$changeto$delim\n");
        return "Change $trigger failed.";
      }
      return "";
    };

    return "/msg $nick Change $trigger: $@" if $@;
    return $ret if length $ret;
  }

  if (length $action > 8000 and not defined $admininfo) {
    return "Change $trigger failed; result is too long.";
  }

  if (not length $action) {
    return "Change $trigger failed; factoids cannot be empty.";
  }

  $self->{pbot}->{logger}->log("($from) $nick!$user\@$host: changed '$trigger' 's/$tochange/$changeto/\n");

  $factoids->{$channel}->{$trigger}->{action}    = $action;
  $factoids->{$channel}->{$trigger}->{edited_by} = "$nick!$user\@$host";
  $factoids->{$channel}->{$trigger}->{edited_on} = gettimeofday;
  $self->{pbot}->{factoids}->save_factoids();
  $self->log_factoid($channel, $trigger, "$nick!$user\@$host", "changed to $factoids->{$channel}->{$trigger}->{action}");
  return "Changed: $trigger is " . $factoids->{$channel}->{$trigger}->{action};
}

sub load_module {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my ($keyword, $module) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  if (not defined $module) {
    return "Usage: load <keyword> <module>";
  }

  if (not exists($factoids->{'.*'}->{$keyword})) {
    $self->{pbot}->{factoids}->add_factoid('module', '.*', "$nick!$user\@$host", $keyword, $module);
    $factoids->{'.*'}->{$keyword}->{add_nick} = 1;
    $factoids->{'.*'}->{$keyword}->{nooverride} = 1;
    $self->{pbot}->{logger}->log("$nick!$user\@$host loaded module $keyword => $module\n");
    $self->{pbot}->{factoids}->save_factoids();
    return "Loaded module $keyword => $module";
  } else {
    return "There is already a keyword named $keyword.";
  }
}

sub unload_module {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  if (not defined $arguments) {
    return "Usage: unload <keyword>";
  } elsif (not exists $factoids->{'.*'}->{$arguments}) {
    return "/say $arguments not found.";
  } elsif ($factoids->{'.*'}->{$arguments}{type} ne 'module') {
    return "/say $arguments is not a module.";
  } else {
    delete $factoids->{'.*'}->{$arguments};
    $self->{pbot}->{factoids}->save_factoids();
    $self->{pbot}->{logger}->log("$nick!$user\@$host unloaded module $arguments\n");
    return "/say $arguments unloaded.";
  }
}

1;
