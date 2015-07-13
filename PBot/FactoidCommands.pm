# File: FactoidCommands.pm
# Author: pragma_
#
# Purpose: Administrative command subroutines.

package PBot::FactoidCommands;

use warnings;
use strict;

use Carp ();
use Time::Duration;
use Time::HiRes qw(gettimeofday);

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to FactoidCommands should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

# TODO - move this someplace better so it can be more accessible to user-customisation
my %factoid_metadata_levels = (
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
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($chan, $keyword, $args) = split / /, $arguments, 3;

  if(not defined $chan or not defined $keyword) {
    return "Usage: fact <channel> <keyword> [arguments]";
  }

  my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($chan, $keyword, $args, 1, 1);

  if(not defined $trigger) {
    return "No such factoid '$keyword' exists for channel '$chan'";
  }

  return $self->{pbot}->{factoids}->interpreter($from, $nick, $user, $host, 1, $trigger, $args, undef, $channel);
}

sub factset {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $trigger, $key, $value) = split / /, $arguments, 4 if defined $arguments;

  if(not defined $channel or not defined $trigger) {
    return "Usage: factset <channel> <factoid> [key [value]]";
  }

  $channel = '.*' if $channel !~ /^#/;

  my ($owner_channel, $owner_trigger) = $self->{pbot}->{factoids}->find_factoid($channel, $trigger, undef, 1, 1);

  my $admininfo;

  if (defined $owner_channel) {
    $admininfo  = $self->{pbot}->{admins}->loggedin($owner_channel, "$nick!$user\@$host");
  } else {
    $admininfo  = $self->{pbot}->{admins}->loggedin($from, "$nick!$user\@$host");
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
  }

  if(defined $owner_channel) {
    my $factoid = $self->{pbot}->{factoids}->{factoids}->hash->{$owner_channel}->{$owner_trigger};

    my ($owner) = $factoid->{'owner'} =~ m/([^!]+)/;

    if(lc $nick ne lc $owner and $level == 0) {
      return "You are not the owner of $trigger.";
    }
  }

  return $self->{pbot}->{factoids}->{factoids}->set($channel, $trigger, $key, $value);
}

sub factunset {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $trigger, $key) = split / /, $arguments, 3 if defined $arguments;

  if(not defined $channel or not defined $trigger or not defined $key) {
    return "Usage: factunset <channel> <factoid> <key>"
  }

  $channel = '.*' if $channel !~ /^#/;

  my ($owner_channel, $owner_trigger) = $self->{pbot}->{factoids}->find_factoid($channel, $trigger, undef, 1, 1);

  my $admininfo;

  if (defined $owner_channel) {
    $admininfo = $self->{pbot}->{admins}->loggedin($owner_channel, "$nick!$user\@$host");
  } else {
    $admininfo = $self->{pbot}->{admins}->loggedin($from, "$nick!$user\@$host");
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

  if(defined $owner_channel) {
    my $factoid = $self->{pbot}->{factoids}->{factoids}->hash->{$owner_channel}->{$owner_trigger};

    my ($owner) = $factoid->{'owner'} =~ m/([^!]+)/;

    if(lc $nick ne lc $owner and $level == 0) {
      return "You are not the owner of $trigger.";
    }
  }

  return $self->{pbot}->{factoids}->{factoids}->unset($channel, $trigger, $key);
}

sub list {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $text;
  
  if(not defined $arguments) {
    return "Usage: list <modules|factoids|commands|admins>";
  }

  # TODO - update this to use new MessageHistory API
=cut
  if($arguments =~/^messages\s+(.*)$/) {
    my ($mask_search, $channel_search, $text_search) = split / /, $1;

    return "/msg $nick Usage: list messages <hostmask or nick regex> <channel regex> [text regex]" if not defined $channel_search;
    $text_search = '.*' if not defined $text_search;

    my @results = eval {
      my @ret;
      foreach my $history_mask (keys %{ $self->{pbot}->{antiflood}->message_history }) {
        my $nickserv = "(undef)";

        $nickserv = $self->{pbot}->{antiflood}->message_history->{$history_mask}->{nickserv_account} if exists $self->{pbot}->{antiflood}->message_history->{$history_mask}->{nickserv_account};
        
        if($history_mask =~ m/$mask_search/i) {
          my $bot_trigger = $self->{pbot}->{registry}->get_value('general', 'trigger');
          foreach my $history_channel (keys %{ $self->{pbot}->{antiflood}->message_history->{$history_mask}->{channels} }) {
            if($history_channel =~ m/$channel_search/i) {
              my @messages = @{ $self->{pbot}->{antiflood}->message_history->{$history_mask}->{channels}->{$history_channel}{messages} };
              for(my $i = 0; $i <= $#messages; $i++) {
                next if $messages[$i]->{msg} =~ /^\Q$bot_trigger\E?login/; # don't reveal login passwords

                print "$history_mask, $history_channel\n";
                print "joinwatch: ", $self->{pbot}->{antiflood}->message_history->{$history_mask}->{channels}->{$history_channel}{join_watch}, "\n";

                push @ret, { 
                  offenses => $self->{pbot}->{antiflood}->message_history->{$history_mask}->{channels}->{$history_channel}{offenses}, 
                  last_offense_timestamp => $self->{pbot}->{antiflood}->message_history->{$history_mask}->{channels}->{$history_channel}{last_offense_timestamp}, 
                  join_watch => $self->{pbot}->{antiflood}->message_history->{$history_mask}->{channels}->{$history_channel}{join_watch}, 
                  text => $messages[$i]->{msg}, 
                  timestamp => $messages[$i]->{timestamp}, 
                  mask => $history_mask, 
                  nickserv => $nickserv, 
                  channel => $history_channel 
                } if $messages[$i]->{msg} =~ m/$text_search/i;
              }
            }
          }
        }
      }
      return @ret;
    };

    if($@) {
      $self->{pbot}->{logger}->log("Error in search parameters: $@\n");
      return "Error in search parameters: $@";
    }

    my $text = "";
    my %seen_masks = ();
    my @sorted = sort { $a->{timestamp} <=> $b->{timestamp} } @results;

    foreach my $msg (@sorted) {
      if(not exists $seen_masks{$msg->{mask}}) {
        $seen_masks{$msg->{mask}} = 1;
        $text .= "--- [$msg->{mask} [$msg->{nickserv}]: join counter: $msg->{join_watch}; offenses: $msg->{offenses}; last offense/decrease: " . ($msg->{last_offense_timestamp} > 0 ? ago(gettimeofday - $msg->{last_offense_timestamp}) : "unknown") . "]\n";
      }

      $text .= "[$msg->{channel}] " . localtime($msg->{timestamp}) . " <$msg->{mask}> " . $msg->{text} . "\n";
    }

    $self->{pbot}->{logger}->log($text);
    return "Messages:\n\n$text";
  }
=cut

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
  my ($src_channel, $source, $target_channel, $target) = split / /, $arguments, 4 if $arguments;
  
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
    return "$found_source is locked; unlock before moving.";
  }

  my ($found_target_channel, $found_target) = $self->{pbot}->{factoids}->find_factoid($target_channel, $target, undef, 1, 1);

  if(defined $found_target_channel) {
    return "Target factoid $target already exists in channel $target_channel";
  }

  $target_channel = lc $target_channel;

  $factoids->{$target_channel}->{$target} = $factoids->{$found_src_channel}->{$found_source};
  delete $factoids->{$found_src_channel}->{$found_source};

  $self->{pbot}->{factoids}->save_factoids;

  $found_src_channel = 'global' if $found_src_channel eq '.*';
  $target_channel = 'global' if $target_channel eq '.*';

  if($src_channel eq $target_channel) {
    return "[$found_src_channel] $found_source renamed to $target";  
  } else {
    return "[$found_src_channel] $found_source moved to [$target_channel] $target";
  }
}

sub factalias {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($chan, $alias, $command) = split / /, $arguments, 3 if defined $arguments;
  
  if(not defined $command) {
    return "Usage: factalias <channel> <keyword> <command>";
  }

  $chan = '.*' if $chan !~ /^#/;

  my ($channel, $alias_trigger) = $self->{pbot}->{factoids}->find_factoid($chan, $alias, undef, 1, 1);
  
  if(defined $alias_trigger) {
    $self->{pbot}->{logger}->log("attempt to overwrite existing command\n");
    return "'$alias_trigger' already exists for channel $channel";
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
    return "$trigger already exists for channel $channel.";
  }

  $self->{pbot}->{factoids}->add_factoid('regex', $from, "$nick!$user\@$host", $keyword, $text);
  $self->{pbot}->{logger}->log("$nick!$user\@$host added [$keyword] => [$text]\n");
  return "$keyword added.";
}

sub factadd {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($from_chan, $keyword, $text) = $arguments =~ /^(\S+)\s+(\S+)\s+is\s+(.*)$/i if defined $arguments;

  if(not defined $from_chan or not defined $text or not defined $keyword) {
    return "Usage: factadd <channel> <keyword> is <factoid>";
  }

  $from_chan = '.*' if not $from_chan =~ m/^#/;

  my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($from_chan, $keyword, undef, 1, 1);
  if(defined $trigger) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempt to overwrite $keyword\n");
    return "$keyword already exists for " . ($from_chan eq '.*' ? 'the global channel' : $from_chan) . ".";
  }

  ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid('.*', $keyword, undef, 1, 1);
  if(defined $trigger and $self->{pbot}->{factoids}->{factoids}->hash->{'.*'}->{$trigger}->{'nooverride'}) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempt to override $keyword\n");
    return "$keyword already exists for the global channel and cannot be overridden for " . ($from_chan eq '.*' ? 'the global channel' : $from_chan) . ".";
  }

  $self->{pbot}->{factoids}->add_factoid('text', $from_chan, "$nick!$user\@$host", $keyword, $text);
  
  $self->{pbot}->{logger}->log("$nick!$user\@$host added [$from_chan] $keyword => $text\n");
  return "$keyword added to " . ($from_chan eq '.*' ? 'global channel' : $from_chan) . ".";
}

sub factrem {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my ($from_chan, $from_trigger) = split / /, $arguments;

  if(not defined $from_chan or not defined $from_trigger) {
    return "Usage: factrem <channel> <keyword>";
  }

  my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($from_chan, $from_trigger, undef, 1, 1);

  if(not defined $trigger) {
    return "$from_trigger not found in channel $from_chan.";
  }

  if($factoids->{$channel}->{$trigger}->{type} eq 'module') {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempted to remove $trigger [not factoid]\n");
    return "$trigger is not a factoid.";
  }

  my ($owner) = $factoids->{$channel}->{$trigger}->{'owner'} =~ m/([^!]+)/;

  if((lc $nick ne lc $owner) and (not $self->{pbot}->{admins}->loggedin($channel, "$nick!$user\@$host"))) {
    $self->{pbot}->{logger}->log("$nick!$user\@$host attempted to remove $trigger [not owner]\n");
    my $chan = ($channel eq '.*' ? 'the global channel' : $channel);
    return "You are not the owner of $trigger for $chan";
  }

  if($factoids->{$channel}->{$trigger}->{'locked'}) {
    return "$trigger is locked; unlock before deleting.";
  }

  $self->{pbot}->{logger}->log("$nick!$user\@$host removed [$channel][$trigger][" . $factoids->{$channel}->{$trigger}->{action} . "]\n");
  $self->{pbot}->{factoids}->remove_factoid($channel, $trigger);
  return "$trigger removed from " . ($channel eq '.*' ? 'the global channel' : $channel) . ".";
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
  return "$factoid_count factoids, top 10 submitters:\n$text";
}

sub factshow {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my ($chan, $trig) = split / /, $arguments;

  if(not defined $chan or not defined $trig) {
    return "Usage: factshow <channel> <trigger>";
  }

  my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($chan, $trig, undef, 1, 1);

  if(not defined $trigger) {
    return "$trig not found in channel $chan";
  }

  my $result = "$trigger: " . $factoids->{$channel}->{$trigger}->{action};

  if($factoids->{$channel}->{$trigger}->{type} eq 'module') {
    $result .= ' [module]';
  }

  return $result;
}

sub factinfo {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;

  my ($chan, $trig) = split / /, $arguments;

  if(not defined $chan or not defined $trig) {
    return "Usage: factinfo <channel> <trigger>";
  }

  my ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($chan, $trig, undef, 1, 1);

  if(not defined $trigger) {
    return "$trig not found in channel $chan";
  }

  my $created_ago = ago(gettimeofday - $factoids->{$channel}->{$trigger}->{created_on});
  my $ref_ago = ago(gettimeofday - $factoids->{$channel}->{$trigger}->{last_referenced_on}) if defined $factoids->{$channel}->{$trigger}->{last_referenced_on};

  $chan = ($channel eq '.*' ? 'global channel' : $channel);

  # factoid
  if($factoids->{$channel}->{$trigger}->{type} eq 'text') {
    return "$trigger: Factoid submitted by " . $factoids->{$channel}->{$trigger}->{owner} . " for $chan on " . localtime($factoids->{$channel}->{$trigger}->{created_on}) . " [$created_ago], " . (defined $factoids->{$channel}->{$trigger}->{edited_by} ? "last edited by $factoids->{$channel}->{$trigger}->{edited_by} on " . localtime($factoids->{$channel}->{$trigger}->{edited_on}) . " [" . ago(gettimeofday - $factoids->{$channel}->{$trigger}->{edited_on}) . "], " : "") . "referenced " . $factoids->{$channel}->{$trigger}->{ref_count} . " times (last by " . $factoids->{$channel}->{$trigger}->{ref_user} . (exists $factoids->{$channel}->{$trigger}->{last_referenced_on} ? " on " . localtime($factoids->{$channel}->{$trigger}->{last_referenced_on}) . " [$ref_ago]" : "") . ")"; 
  }

  # module
  if($factoids->{$channel}->{$trigger}->{type} eq 'module') {
    my $module_repo = $self->{pbot}->{registry}->get_value('general', 'module_repo');
    $module_repo .= "$factoids->{$channel}->{$trigger}->{workdir}/" if exists $factoids->{$channel}->{$trigger}->{workdir};
    return "$trigger: Module loaded by " . $factoids->{$channel}->{$trigger}->{owner} . " for $chan on " . localtime($factoids->{$channel}->{$trigger}->{created_on}) . " [$created_ago] -> $module_repo" . $factoids->{$channel}->{$trigger}->{action} . ", used " . $factoids->{$channel}->{$trigger}->{ref_count} . " times (last by " . $factoids->{$channel}->{$trigger}->{ref_user} . (exists $factoids->{$channel}->{$trigger}->{last_referenced_on} ? " on " . localtime($factoids->{$channel}->{$trigger}->{last_referenced_on}) . " [$ref_ago]" : "") . ")"; 
  }

  # regex
  if($factoids->{$channel}->{$trigger}->{type} eq 'regex') {
    return "$trigger: Regex created by " . $factoids->{$channel}->{$trigger}->{owner} . " for $chan on " . localtime($factoids->{$channel}->{$trigger}->{created_on}) . " [$created_ago], " . (defined $factoids->{$channel}->{$trigger}->{edited_by} ? "last edited by $factoids->{$channel}->{$trigger}->{edited_by} on " . localtime($factoids->{$channel}->{$trigger}->{edited_on}) . " [" . ago(gettimeofday - $factoids->{$channel}->{$trigger}->{edited_on}) . "], " : "") . " used " . $factoids->{$channel}->{$trigger}->{ref_count} . " times (last by " . $factoids->{$channel}->{$trigger}->{ref_user} . (exists $factoids->{$channel}->{$trigger}->{last_referenced_on} ? " on " . localtime($factoids->{$channel}->{$trigger}->{last_referenced_on}) . " [$ref_ago]" : "") . ")"; 
  }

  return "$trigger is not a factoid or a module";
}

sub top20 {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my $factoids = $self->{pbot}->{factoids}->{factoids}->hash;
  my %hash = ();
  my $text = "";
  my $i = 0;

  my ($channel, $args) = split / /, $arguments, 2 if defined $arguments;

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
          my $ago = ago(gettimeofday - $factoids->{$chan}->{$command}->{created_on});
          $text .= "   $command [$ago by $factoids->{$chan}->{$command}->{owner}]\n";
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

  if(not defined $arguments) {
    return "Usage:  count <nick|factoids>";
  }

  $arguments = ".*" if($arguments =~ /^factoids$/);

  eval {
    foreach my $channel (keys %{ $factoids }) {
      foreach my $command (keys %{ $factoids->{$channel} }) {
        next if $factoids->{$channel}->{$command}->{type} ne 'text';
        $total++; 
        if($factoids->{$channel}->{$command}->{owner} =~ /\Q$arguments\E/i) {
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
    return "$arguments has submitted $i factoids out of $total ($percent"."%)";
  } else {
    return "$arguments hasn't submitted any factoids";
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
    return "Usage: factfind [-channel] [-owner regex] [-refby regex] [-editby regex] [text]";
  }

  my ($text, $last_trigger, $last_chan, $i);
  $last_chan = "";
  $i = 0;
  eval {
    foreach my $chan (sort keys %{ $factoids }) {
      next if defined $channel and $chan !~ /$channel/i;
      foreach my $trigger (sort keys %{ $factoids->{$chan} }) {
        if($factoids->{$chan}->{$trigger}->{type} eq 'text' or $factoids->{$chan}->{$trigger}->{type} eq 'regex') {
          if($factoids->{$chan}->{$trigger}->{owner} =~ /$owner/i 
            && $factoids->{$chan}->{$trigger}->{ref_user} =~ /$refby/i
            && (exists $factoids->{$chan}->{$trigger}->{edited_by} ? $factoids->{$chan}->{$trigger}->{edited_by} =~ /$editby/i : 1)) {
            next if($arguments ne "" && $factoids->{$chan}->{$trigger}->{action} !~ /$arguments/i && $trigger !~ /$arguments/i);

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

  if(defined $arguments) {
    if($arguments =~ /^([^\s]+) ([^\s]+)\s+s(.)/) {
      $channel = $1;
      $keyword = $2; 
      $delim = $3;
    }
    
    if($arguments =~ /$delim(.*?)$delim(.*)$delim(.*)?$/) {
      $tochange = $1; 
      $changeto = $2;
      $modifier  = $3;
    }
  }

  if(not defined $channel or not defined $changeto) {
    return "Usage: factchange <channel> <keyword> s/<pattern>/<replacement>/";
  }

  ($channel, $trigger) = $self->{pbot}->{factoids}->find_factoid($channel, $keyword, undef, 1, 1);

  if(not defined $trigger) {
    return "$keyword not found in channel $from.";
  }

  if(not $self->{pbot}->{admins}->loggedin($from, "$nick!$user\@$host") and $factoids->{$channel}->{$trigger}->{'locked'}) {
    return "$trigger is locked and cannot be changed.";
  }

  my $ret = eval {
    use re::engine::RE2 -strict => 1;
    if(not $factoids->{$channel}->{$trigger}->{action} =~ s|$tochange|$changeto|) {
      $self->{pbot}->{logger}->log("($from) $nick!$user\@$host: failed to change '$trigger' 's$delim$tochange$delim$changeto$delim\n");
      return "Change $trigger failed.";
    } else {
      $self->{pbot}->{logger}->log("($from) $nick!$user\@$host: changed '$trigger' 's/$tochange/$changeto/\n");
      $factoids->{$channel}->{$trigger}->{edited_by} = "$nick!$user\@$host";
      $factoids->{$channel}->{$trigger}->{edited_on} = gettimeofday;
      $self->{pbot}->{factoids}->save_factoids();
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
    return "$arguments not found.";
  } elsif($factoids->{'.*'}->{$arguments}{type} ne 'module') {
    return "$arguments is not a module.";
  } else {
    delete $factoids->{'.*'}->{$arguments};
    $self->{pbot}->{factoids}->save_factoids();
    $self->{pbot}->{logger}->log("$nick!$user\@$host unloaded module $arguments\n");
    return "$arguments unloaded.";
  } 
}

1;
