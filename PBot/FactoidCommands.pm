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

use Carp ();
use Time::Duration;
use Time::HiRes qw(gettimeofday);
use Getopt::Long qw(GetOptionsFromString);
use POSIX qw(strftime);
use Storable;

use PBot::Utils::SafeFilename;
use PBot::Utils::ValidateString;

sub new {
  if(ref($_[1]) eq 'HASH') {
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
  'effective-level'           => 20,
  'persist-key'               => 20,
  'interpolate'               => 10,
  'action'                    => 10,
  # all others are allowed to be factset by anybody/default to level 0
);

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot};
  if(not defined $pbot) {
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
  my ($chan, $keyword, $args) = split /\s+/, $arguments, 3;

  if(not defined $chan or not defined $keyword) {
    return "Usage: fact <channel> <keyword> [arguments]";
  }

  my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($chan, $keyword, $args, 1, 1);

  if(not defined $trigger) {
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
  print $fh "$now $hostmask $msg\n";
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
  my ($self, $from, $arguments, $command, $usage, $explicit) = @_;
  my ($from_chan, $from_trigger, $remaining_args) = split /\s+/, $arguments, 3;

  if (not defined $from_chan or (not defined $from_chan and not defined $from_trigger)) {
    return "Usage: $command [channel] <keyword>" if not $usage;
    return $usage;
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
      $remaining_args = $from_trigger . (length $remaining_args ? " $remaining_args" : "");
      $from_trigger = $keyword;
    }
  }

  $from_chan = '.*' if $from_chan !~ /^#/;
  $from_chan = lc $from_chan;

  my @factoids = $self->{pbot}->{factoids}->find_factoid($from_chan, $from_trigger, undef, 0, 1);

  if (not @factoids or not $factoids[0]) {
    if ($needs_disambig) {
      return "/say $from_trigger not found";
    } else {
      $from_chan = 'global channel' if $from_chan eq '.*';
      return "/say $from_trigger not found in $from_chan";
    }
  }

  my ($channel, $trigger);

  if (@factoids > 1) {
    if ($needs_disambig or not grep { $_->[0] eq $from_chan } @factoids) {
      unless ($explicit) {
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

  $channel = '.*' if $channel eq 'global';
  $from_chan = '.*' if $channel eq 'global';

  if ($explicit and $channel =~ /^#/ and $from_chan =~ /^#/ and $channel ne $from_chan) {
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


  if (not keys %diff) {
    return "No change.";
  }

  my $changes = "";

  my $comma = "";
  foreach my $key (sort keys %diff) {
    $changes .= "$comma$key => $diff{$key}";
    $comma = ", ";
  }

  return $changes
}

sub factundo {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, $arguments, 'factundo', undef, 1);
  my $deleted;

  if (not defined $trigger) {
    # factoid not found or some error, try to continue and load undo file if it exists
    $deleted = 1;
    ($channel, $trigger) = split /\s+/, $arguments, 2;
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

  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my $admininfo = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
  if ($factoids->{$channel}->{$trigger}->{'locked'}) {
    return "/say $trigger is locked and cannot be reverted." if not defined $admininfo;

    if (exists $factoids->{$channel}->{$trigger}->{'effective-level'}
        and $admininfo->{level} < $factoids->{$channel}->{$trigger}->{'effective-level'}) {
      return "/say $trigger is locked with an effective-level higher than your level and cannot be reverted.";
    }
  }

  unless ($deleted) {
    return "There are no more undos remaining for [$channel] $trigger." if not $undos->{idx};
    $undos->{idx}--;
    eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
    $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;
  }

  $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger} = $undos->{list}->[$undos->{idx}];

  my $changes = $self->hash_differences_as_string($undos->{list}->[$undos->{idx} + 1], $undos->{list}->[$undos->{idx}]);
  $self->log_factoid($channel, $trigger, "$nick!$user\@$host", "reverted (undo): $changes", 1);
  return "[$channel] $trigger reverted (revision " . ($undos->{idx} + 1) . "): $changes\n";
}

sub factredo {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, $arguments, 'factredo', undef, 1);
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

  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my $admininfo = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
  if ($factoids->{$channel}->{$trigger}->{'locked'}) {
    return "/say $trigger is locked and cannot be reverted." if not defined $admininfo;

    if (exists $factoids->{$channel}->{$trigger}->{'effective-level'}
        and $admininfo->{level} < $factoids->{$channel}->{$trigger}->{'effective-level'}) {
      return "/say $trigger is locked with an effective-level higher than your level and cannot be reverted.";
    }
  }

  if ($undos->{idx} + 1 == @{$undos->{list}}) {
    return "There are no more redos remaining for [$channel] $trigger.";
  }

  $undos->{idx}++;
  eval { store $undos, "$path/$trigger_safe.$channel_path_safe.undo"; };
  $self->{pbot}->{logger}->log("Error storing undo: $@\n") if $@;

  $self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$trigger} = $undos->{list}->[$undos->{idx}];

  my $changes = $self->hash_differences_as_string($undos->{list}->[$undos->{idx} - 1], $undos->{list}->[$undos->{idx}]);
  $self->log_factoid($channel, $trigger, "$nick!$user\@$host", "reverted (redo): $changes", 1);
  return "[$channel] $trigger restored (revision " . ($undos->{idx} + 1) . "): $changes\n";
}

sub factset {
  my $self = shift;
  my ($from, $nick, $user, $host, $args) = @_;

  $args = validate_string($args);

  my ($channel, $trigger, $arguments) = $self->find_factoid_with_optional_channel($from, $args, 'factset', 'Usage: factset [channel] <factoid> [key [value]]', 1);
  return $channel if not defined $trigger; # if $trigger is not defined, $channel is an error message

  my ($key, $value) = split /\s+/, $arguments, 2;

  $channel = '.*' if $channel !~ /^#/;

  my ($owner_channel, $owner_trigger) = $self->{pbot}->{factoids}->find_factoid($channel, $trigger, undef, 1, 1);

  my $admininfo;

  if (defined $owner_channel) {
    $admininfo  = $self->{pbot}->{admins}->loggedin($owner_channel, "$nick!$user\@$host");
  } else {
    $admininfo  = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
  }

  my $level = 0;
  my $meta_level = 0;

  if(defined $admininfo) {
    $level = $admininfo->{level};
  }

  if(defined $key) {
    if(defined $factoid_metadata_levels{$key}) {
      $meta_level = $factoid_metadata_levels{$key};
    }

    if($meta_level > 0) {
      if($level == 0) {
        return "You must login to set '$key'";
      } elsif($level < $meta_level) {
        return "You must be at least level $meta_level to set '$key'";
      }
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

  if(defined $owner_channel) {
    my $factoid = $self->{pbot}->{factoids}->{factoids}->hash->{$owner_channel}->{$owner_trigger};

    my ($owner) = $factoid->{'owner'} =~ m/([^!]+)/;

    if(lc $nick ne lc $owner and $level == 0) {
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

  my ($channel, $trigger, $key) = $self->find_factoid_with_optional_channel($from, $args, 'factset', $usage, 1);
  return $channel if not defined $trigger; # if $trigger is not defined, $channel is an error message

  return $usage if not length $key;

  my ($owner_channel, $owner_trigger) = $self->{pbot}->{factoids}->find_factoid($channel, $trigger, undef, 1, 1);

  my $admininfo;

  if (defined $owner_channel) {
    $admininfo = $self->{pbot}->{admins}->loggedin($owner_channel, "$nick!$user\@$host");
  } else {
    $admininfo = $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host");
  }

  my $level = 0;
  my $meta_level = 0;

  if(defined $admininfo) {
    $level = $admininfo->{level};
  }

  if(defined $factoid_metadata_levels{$key}) {
    $meta_level = $factoid_metadata_levels{$key};
  }

  if($meta_level > 0) {
    if($level == 0) {
      return "You must login to unset '$key'";
    } elsif($level < $meta_level) {
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

  if(defined $owner_channel) {
    my $factoid = $self->{pbot}->{factoids}->{factoids}->hash->{$owner_channel}->{$owner_trigger};

    my ($owner) = $factoid->{'owner'} =~ m/([^!]+)/;

    if(lc $nick ne lc $owner and $level == 0) {
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
  
  if(not defined $arguments) {
    return "Usage: list <modules|factoids|commands|admins>";
  }

  if($arguments =~ /^modules$/i) {
    $from = '.*' if not defined $from or $from !~ /^#/;
    $text = "Loaded modules for channel $from: ";
    foreach my $channel (sort keys %{ $self->{pbot}->{factoids}->{factoids}->hash }) {
      foreach my $command (sort keys %{ $self->{pbot}->{factoids}->{factoids}->hash->{$channel} }) {
        if($self->{pbot}->{factoids}->{factoids}->hash->{$channel}->{$command}->{type} eq 'module') {
          $text .= "$command ";
        }
      }
    }
    return $text;
  }

  if($arguments =~ /^commands$/i) {
    $text = "Registered commands: ";
    foreach my $command (sort { $a->{name} cmp $b->{name} } @{ $self->{pbot}->{commands}->{handlers} }) {
      $text .= "$command->{name} ";
      $text .= "($command->{level}) " if $command->{level} > 0;
    }
    return $text;
  }

  if($arguments =~ /^factoids$/i) {
    return "For a list of factoids see " . $self->{pbot}->{factoids}->export_site;
  }

  if($arguments =~ /^admins$/i) {
    $text = "Admins: ";
    my $last_channel = "";
    my $sep = "";
    foreach my $channel (sort keys %{ $self->{pbot}->{admins}->{admins}->hash }) {
      if($last_channel ne $channel) {
        $text .= $sep . "Channel " . ($channel eq ".*" ? "all" : $channel) . ": ";
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
  return "Usage: list <modules|commands|factoids|admins>";
}

sub factmove {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  $arguments = validate_string($arguments);
  my ($src_channel, $source, $target_channel, $target) = split /\s+/, $arguments, 5 if length $arguments;

  my $usage = "Usage: factmove <source channel> <source factoid> <target channel/factoid> [target factoid]";

  if(not defined $target_channel) {
    return $usage;
  }

  if($target_channel !~ /^#/ and $target_channel ne '.*') {
    if(defined $target) {
      return "Unexpected argument '$target' when renaming to '$target_channel'. Perhaps '$target_channel' is missing #s? $usage";
    }

    $target = $target_channel;
    $target_channel = $src_channel;
  } else {
    if(not defined $target) {
      $target = $source;
    }
  }

  if (length $target > 30) {
    return "/say $nick: I don't think the factoid name needs to be that long.";
  }

  if (length $target_channel > 20) {
    return "/say $nick: I don't think the channel name needs to be that long.";
  }

  my ($found_src_channel, $found_source) = $self->{pbot}->{factoids}->find_factoid($src_channel, $source, undef, 1, 1);

  if(not defined $found_src_channel) {
    return "Source factoid $source not found in channel $src_channel";
  }

  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my ($owner) = $factoids->{$found_src_channel}->{$found_source}->{'owner'} =~ m/([^!]+)/;

  if((lc $nick ne lc $owner) and (not $self->{pbot}->{admins}->loggedin($found_src_channel, "$nick!$user\@$host"))) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempted to move [$found_src_channel] $found_source (not owner)\n");
    my $chan = ($found_src_channel eq '.*' ? 'the global channel' : $found_src_channel);
    return "You are not the owner of $found_source for $chan";
  }

  if($factoids->{$found_src_channel}->{$found_source}->{'locked'}) {
    return "/say $found_source is locked; unlock before moving.";
  }

  my ($found_target_channel, $found_target) = $self->{pbot}->{factoids}->find_factoid($target_channel, $target, undef, 1, 1);

  if(defined $found_target_channel) {
    return "Target factoid $target already exists in channel $target_channel";
  }

  my ($overchannel, $overtrigger) = $self->{pbot}->{factoids}->find_factoid('.*', $target, undef, 1, 1);
  if(defined $overtrigger and $self->{pbot}->{factoids}->{factoids}->hash->{'.*'}->{$overtrigger}->{'nooverride'}) {
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

  if($src_channel eq $target_channel) {
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
  my ($from, $nick, $user, $host, $arguments) = @_;
  $arguments = validate_string($arguments);
  my ($chan, $alias, $command) = split /\s+/, $arguments, 3 if defined $arguments;
  
  if(not defined $command) {
    return "Usage: factalias <channel> <keyword> <command>";
  }

  $chan = '.*' if $chan !~ /^#/;

  if (length $alias > 30) {
    return "/say $nick: I don't think the factoid name needs to be that long.";
  }

  if (length $chan > 20) {
    return "/say $nick: I don't think the channel name needs to be that long.";
  }

  my ($channel, $alias_trigger) = $self->{pbot}->{factoids}->find_factoid($chan, $alias, undef, 1, 1);
  
  if(defined $alias_trigger) {
    $self->{pbot}->{logger}->log("attempt to overwrite existing command\n");
    return "'$alias_trigger' already exists for channel $channel";
  }

  my ($overchannel, $overtrigger) = $self->{pbot}->{factoids}->find_factoid('.*', $alias, undef, 1, 1);
  if(defined $overtrigger and $self->{pbot}->{factoids}->{factoids}->hash->{'.*'}->{$overtrigger}->{'nooverride'}) {
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
  $arguments = validate_string($arguments);
  my ($keyword, $text) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  $from = '.*' if not defined $from or $from !~ /^#/;

  if(not defined $keyword) {
    $text = "";
    foreach my $trigger (sort keys %{ $factoids->{$from} }) {
      if($factoids->{$from}->{$trigger}->{type} eq 'regex') {
        $text .= $trigger . " ";
      }
    }
    return "Stored regexs for channel $from: $text";
  }

  if(not defined $text) {
    return "Usage: regex <regex> <command>";
  }

  my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($from, $keyword, undef, 1, 1);

  if(defined $trigger) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempt to overwrite $trigger\n");
    return "/say $trigger already exists for channel $channel.";
  }

  $self->{pbot}->{factoids}->add_factoid('regex', $from, "$nick!$user\@$host", $keyword, $text);
  $self->{pbot}->{logger}->log("$nick!$user\@$host added [$keyword] => [$text]\n");
  return "/say $keyword added.";
}

sub factadd {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($from_chan, $keyword, $text);

  $arguments = validate_string($arguments);

  if (defined $arguments) {
    if ($arguments =~ /^(#\S+|global|\.\*)\s+(\S+)\s+(?:is\s+)?(.*)$/i) {
      ($from_chan, $keyword, $text) = ($1, $2, $3);
    } elsif ($arguments =~ /^(\S+)\s+(?:is\s+)?(.*)$/i) {
      ($from_chan, $keyword, $text) = ($from, $1, $2);
    }
  }

  if(not defined $from_chan or not defined $text or not defined $keyword) {
    return "Usage: factadd [channel] <keyword> <factoid>";
  }

  if ($from_chan !~ /^#/) {
    if (lc $from_chan ne 'global' and $from_chan ne '.*') {
      return "Usage: factadd [channel] <keyword> <text>";
    }
  }

  if (length $keyword > 30) {
    return "/say $nick: I don't think the factoid name needs to be that long.";
  }

  if (length $from_chan > 20) {
    return "/say $nick: I don't think the channel needs to be that long.";
  }

  $from_chan = '.*' if lc $from_chan eq 'global';
  $from_chan = '.*' if not $from_chan =~ m/^#/;

  my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($from_chan, $keyword, undef, 1, 1);
  if(defined $trigger) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempt to overwrite $keyword\n");
    return "/say $keyword already exists for " . ($from_chan eq '.*' ? 'the global channel' : $from_chan) . ".";
  }

  ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid('.*', $keyword, undef, 1, 1);
  if(defined $trigger and $self->{pbot}->{factoids}->{factoids}->hash->{'.*'}->{$trigger}->{'nooverride'}) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempt to override $keyword\n");
    return "/say $keyword already exists for the global channel and cannot be overridden for " . ($from_chan eq '.*' ? 'the global channel' : $from_chan) . ".";
  }

  if ($self->{pbot}->{commands}->exists($keyword)) {
    return "/say $keyword already exists as a built-in command.";
  }

  $self->{pbot}->{factoids}->add_factoid('text', $from_chan, "$nick!$user\@$host", $keyword, $text);
  
  $self->{pbot}->{logger}->log("$nick!$user\@$host added [$from_chan] $keyword => $text\n");
  return "/say $keyword added to " . ($from_chan eq '.*' ? 'global channel' : $from_chan) . ".";
}

sub factrem {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my ($from_chan, $from_trig) = split /\s+/, $arguments;

  if (not defined $from_trig) {
    $from_trig = $from_chan;
    $from_chan = $from;
  }

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, $arguments, 'factrem', undef, 1);
  return $channel if not defined $trigger; # if $trigger is not defined, $channel is an error message

  $channel = '.*' if $channel eq 'global';
  $from_chan = '.*' if $channel eq 'global';

  if($factoids->{$channel}->{$trigger}->{type} eq 'module') {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempted to remove $trigger [not factoid]\n");
    return "/say $trigger is not a factoid.";
  }

  if ($channel =~ /^#/ and $from_chan =~ /^#/ and $channel ne $from_chan) {
    return "/say $trigger belongs to $channel, but this is $from_chan. Please switch to $channel or /msg to remove this factoid.";
  }

  my ($owner) = $factoids->{$channel}->{$trigger}->{'owner'} =~ m/([^!]+)/;

  if((lc $nick ne lc $owner) and (not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host"))) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempted to remove $trigger [not owner]\n");
    my $chan = ($channel eq '.*' ? 'the global channel' : $channel);
    return "You are not the owner of $trigger for $chan";
  }

  if($factoids->{$channel}->{$trigger}->{'locked'}) {
    return "/say $trigger is locked; unlock before deleting.";
  }

  $self->{pbot}->{logger}->log("$nick!$user\@$host removed [$channel][$trigger][" . $factoids->{$channel}->{$trigger}->{action} . "]\n");
  $self->{pbot}->{factoids}->remove_factoid($channel, $trigger);
  $self->log_factoid($channel, $trigger, "$nick!$user\@$host", "deleted", 1);
  return "/say $trigger removed from " . ($channel eq '.*' ? 'the global channel' : $channel) . ".";
}

sub histogram {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my %hash;
  my $factoid_count = 0;

  foreach my $channel (keys %$factoids) {
    foreach my $command (keys %{ $factoids->{$channel} }) {
      if($factoids->{$channel}->{$command}->{type} eq 'text') {
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
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my ($chan, $trig) = split /\s+/, $arguments;

  if (not defined $trig) {
    $trig = $chan;
    $chan = $from;
  }

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, $arguments, 'factshow');
  return $channel if not defined $trigger; # if $trigger is not defined, $channel is an error message

  my $result = "$trigger: " . $factoids->{$channel}->{$trigger}->{action};

  if($factoids->{$channel}->{$trigger}->{type} eq 'module') {
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

  $arguments =~ s/(?<!\\)'/\\'/g;
  my ($show_hostmask, $actual_timestamp);
  my ($ret, $args) = GetOptionsFromString($arguments,
    'h'  => \$show_hostmask,
    't'  => \$actual_timestamp);

  return "/say $getopt_error -- $usage" if defined $getopt_error;
  return "Too many arguments -- $usage" if @$args > 2;
  return "Missing argument -- $usage" if not @$args;

  my ($channel, $trigger) = $self->find_factoid_with_optional_channel($from, "@$args", 'factlog', $usage);

  if (not defined $trigger) {
    # factoid not found or some error, try to continue and load factlog file if it exists
    ($channel, $trigger) = split /\s+/, "@$args", 2;
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
    $self->{pbot}->{logger}->log("Could not open $path/$trigger.$channel: $!\n");
    $channel = 'the global channel' if $channel eq 'global';
    return "No factlog available for $trigger in $channel.";
  };

  my @entries;
  while (my $line = <$fh>) {
    my ($timestamp, $hostmask, $msg) = split /\s+/, $line, 3;

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
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my ($chan, $trig) = split /\s+/, $arguments;

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
  if($factoids->{$channel}->{$trigger}->{type} eq 'text') {
    return "/say $trigger: Factoid submitted by " . $factoids->{$channel}->{$trigger}->{owner} . " for $chan on " . localtime($factoids->{$channel}->{$trigger}->{created_on}) . " [$created_ago], " . (defined $factoids->{$channel}->{$trigger}->{edited_by} ? "last edited by $factoids->{$channel}->{$trigger}->{edited_by} on " . localtime($factoids->{$channel}->{$trigger}->{edited_on}) . " [" . ago(gettimeofday - $factoids->{$channel}->{$trigger}->{edited_on}) . "], " : "") . "referenced " . $factoids->{$channel}->{$trigger}->{ref_count} . " times (last by " . $factoids->{$channel}->{$trigger}->{ref_user} . (exists $factoids->{$channel}->{$trigger}->{last_referenced_on} ? " on " . localtime($factoids->{$channel}->{$trigger}->{last_referenced_on}) . " [$ref_ago]" : "") . ")"; 
  }

  # module
  if($factoids->{$channel}->{$trigger}->{type} eq 'module') {
    my $module_repo = $self->{pbot}->{registry}->get_value('general', 'module_repo');
    $module_repo .= "$factoids->{$channel}->{$trigger}->{workdir}/" if exists $factoids->{$channel}->{$trigger}->{workdir};
    return "/say $trigger: Module loaded by " . $factoids->{$channel}->{$trigger}->{owner} . " for $chan on " . localtime($factoids->{$channel}->{$trigger}->{created_on}) . " [$created_ago] -> $module_repo" . $factoids->{$channel}->{$trigger}->{action} . ", used " . $factoids->{$channel}->{$trigger}->{ref_count} . " times (last by " . $factoids->{$channel}->{$trigger}->{ref_user} . (exists $factoids->{$channel}->{$trigger}->{last_referenced_on} ? " on " . localtime($factoids->{$channel}->{$trigger}->{last_referenced_on}) . " [$ref_ago]" : "") . ")"; 
  }

  # regex
  if($factoids->{$channel}->{$trigger}->{type} eq 'regex') {
    return "/say $trigger: Regex created by " . $factoids->{$channel}->{$trigger}->{owner} . " for $chan on " . localtime($factoids->{$channel}->{$trigger}->{created_on}) . " [$created_ago], " . (defined $factoids->{$channel}->{$trigger}->{edited_by} ? "last edited by $factoids->{$channel}->{$trigger}->{edited_by} on " . localtime($factoids->{$channel}->{$trigger}->{edited_on}) . " [" . ago(gettimeofday - $factoids->{$channel}->{$trigger}->{edited_on}) . "], " : "") . " used " . $factoids->{$channel}->{$trigger}->{ref_count} . " times (last by " . $factoids->{$channel}->{$trigger}->{ref_user} . (exists $factoids->{$channel}->{$trigger}->{last_referenced_on} ? " on " . localtime($factoids->{$channel}->{$trigger}->{last_referenced_on}) . " [$ref_ago]" : "") . ")"; 
  }

  return "/say $arguments is not a factoid or a module";
}

sub top20 {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my %hash = ();
  my $text = "";
  my $i = 0;

  my ($channel, $args) = split /\s+/, $arguments, 2 if defined $arguments;

  if(not defined $channel) {
    return "Usage: top20 <channel> [nick or 'recent']";
  }

  if(not defined $args) {
    foreach my $chan (sort keys %{ $factoids }) {
      next if lc $chan ne lc $channel;
      foreach my $command (sort {$factoids->{$chan}->{$b}{ref_count} <=> $factoids->{$chan}->{$a}{ref_count}} keys %{ $factoids->{$chan} }) {
        if($factoids->{$chan}->{$command}{ref_count} > 0 and $factoids->{$chan}->{$command}{type} eq 'text') {
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
    if(lc $args eq "recent") {
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
        if($factoids->{$chan}->{$command}{ref_user} =~ /\Q$args\E/i) {
          if($user ne lc $factoids->{$chan}->{$command}{ref_user} && not $user =~ /$factoids->{$chan}->{$command}{ref_user}/i) {
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

  $arguments = ".*" if($arguments =~ /^factoids$/);

  eval {
    foreach my $channel (keys %{ $factoids }) {
      foreach my $command (keys %{ $factoids->{$channel} }) {
        next if $factoids->{$channel}->{$command}->{type} ne 'text';
        $total++; 
        if($factoids->{$channel}->{$command}->{owner} =~ /^\Q$arguments\E$/i) {
          $i++;
        }
      }
    }
  };
  return "/msg $nick $arguments: $@" if $@;

  return "I have $i factoids." if $arguments eq ".*";

  if($i > 0) {
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

  if(not defined $arguments) {
    return "Usage: factfind [-channel channel] [-owner regex] [-editby regex] [-refby regex] [text]";
  }

  my ($channel, $owner, $refby, $editby);

  $channel = $1 if $arguments =~ s/-channel\s+([^\b\s]+)//i;
  $owner = $1 if $arguments =~ s/-owner\s+([^\b\s]+)//i;
  $refby = $1 if $arguments =~ s/-refby\s+([^\b\s]+)//i;
  $editby = $1 if $arguments =~ s/-editby\s+([^\b\s]+)//i;

  $owner = '.*' if not defined $owner;
  $refby = '.*' if not defined $refby;
  $editby = '.*' if not defined $editby;

  $arguments =~ s/^\s+//;
  $arguments =~ s/\s+$//;
  $arguments =~ s/\s+/ /g;

  $arguments = substr($arguments, 0, 30);

  my $argtype = undef;

  if($owner ne '.*') {
    $argtype = "owned by $owner";
  }

  if($refby ne '.*') {
    if(not defined $argtype) {
      $argtype = "last referenced by $refby";
    } else {
      $argtype .= " and last referenced by $refby";
    }
  }

  if($editby ne '.*') {
    if(not defined $argtype) {
      $argtype = "last edited by $editby";
    } else {
      $argtype .= " and last edited by $editby";
    }
  }

  if($arguments ne "") {
    my $unquoted_args = $arguments;
    $unquoted_args =~ s/(?:\\(?!\\))//g;
    $unquoted_args =~ s/(?:\\\\)/\\/g;
    if(not defined $argtype) {
      $argtype = "with text containing '$unquoted_args'";
    } else {
      $argtype .= " and with text containing '$unquoted_args'";
    }
  }

  if(not defined $argtype) {
    return "Usage: factfind [-channel regex] [-owner regex] [-refby regex] [-editby regex] [text]";
  }

  my ($text, $last_trigger, $last_chan, $i);
  $last_chan = "";
  $i = 0;
  eval {
    use re::engine::RE2 -strict => 1;
    my $regex = ($arguments =~ m/^\w/) ? '\b' : '\B';
    $regex .= quotemeta $arguments;
    $regex .= ($arguments =~ m/\w$/) ? '\b' : '\B';

    foreach my $chan (sort keys %{ $factoids }) {
      next if defined $channel and $chan !~ /$channel/i;
      foreach my $trigger (sort keys %{ $factoids->{$chan} }) {
        if($factoids->{$chan}->{$trigger}->{type} eq 'text' or $factoids->{$chan}->{$trigger}->{type} eq 'regex') {
          if($factoids->{$chan}->{$trigger}->{owner} =~ /$owner/i 
            && $factoids->{$chan}->{$trigger}->{ref_user} =~ /$refby/i
            && (exists $factoids->{$chan}->{$trigger}->{edited_by} ? $factoids->{$chan}->{$trigger}->{edited_by} =~ /$editby/i : 1)) {
            next if($arguments ne "" && $factoids->{$chan}->{$trigger}->{action} !~ /$regex/i && $trigger !~ /$regex/i);

            $i++;
            
            if($chan ne $last_chan) {
              $text .= $chan eq '.*' ? "[global channel] " : "[$chan] ";
              $last_chan = $chan;
            }
            $text .= "$trigger ";
            $last_trigger = $trigger;
          }
        }
      }
    }
  };

  return "/msg $nick $arguments: $@" if $@;

  if($i == 1) {
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
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my ($channel, $trigger, $keyword, $delim, $tochange, $changeto, $modifier);

  $arguments = validate_string($arguments);

  my $needs_disambig;

  if (defined $arguments) {
    if ($arguments =~ /^([^\s]+) ([^\s]+)\s+s(.)/) {
      $channel = $1;
      $keyword = $2; 
      $delim = $3;
      $needs_disambig = 0;
    } elsif ($arguments =~ /^([^\s]+)\s+s(.)/) {
      $keyword = $1;
      $delim = $2;
      $channel = $from;
      $needs_disambig = 1;
    }

    $delim = quotemeta $delim;

    if ($arguments =~ /\Q$keyword\E s$delim(.*?)$delim(.*)$delim(.*)$/) {
      $tochange = $1; 
      $changeto = $2;
      $modifier  = $3;
    }
  }

  if (not defined $channel or not defined $changeto) {
    return "Usage: factchange [channel] <keyword> s/<pattern>/<replacement>/";
  }

  my ($from_trigger, $from_chan) = ($keyword, $channel);
  my @factoids = $self->{pbot}->{factoids}->find_factoid($from_chan, $keyword, undef, 0, 1);

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

  my $ret = eval {
    use re::engine::RE2 -strict => 1;
    my $action = $factoids->{$channel}->{$trigger}->{action};
    my $changed;

    if ($modifier eq 'gi' or $modifier eq 'ig') {
      $changed = $action =~ s|$tochange|$changeto|gi;
    } elsif ($modifier eq 'g') {
      $changed = $action =~ s|$tochange|$changeto|g;
    } elsif ($modifier eq 'i') {
      $changed = $action =~ s|$tochange|$changeto|i;
    } else {
      $changed = $action =~ s|$tochange|$changeto|;
    }

    if (not $changed) {
      $self->{pbot}->{logger}->log("($from) $nick!$user\@$host: failed to change '$trigger' 's$delim$tochange$delim$changeto$delim\n");
      return "Change $trigger failed.";
    } else {
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
  };
  return "/msg $nick Change $trigger: $@" if $@;
  return $ret;
}

sub load_module {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my ($keyword, $module) = $arguments =~ /^(.*?)\s+(.*)$/ if defined $arguments;

  if(not defined $module) {
    return "Usage: load <keyword> <module>";
  }

  if(not exists($factoids->{'.*'}->{$keyword})) {
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

  if(not defined $arguments) {
    return "Usage: unload <keyword>";
  } elsif(not exists $factoids->{'.*'}->{$arguments}) {
    return "/say $arguments not found.";
  } elsif($factoids->{'.*'}->{$arguments}{type} ne 'module') {
    return "/say $arguments is not a module.";
  } else {
    delete $factoids->{'.*'}->{$arguments};
    $self->{pbot}->{factoids}->save_factoids();
    $self->{pbot}->{logger}->log("$nick!$user\@$host unloaded module $arguments\n");
    return "/say $arguments unloaded.";
  } 
}

1;
