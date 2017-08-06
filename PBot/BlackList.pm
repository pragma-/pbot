# File: BlackList.pm
# Author: pragma_
#
# Purpose: Manages list of hostmasks that are not allowed to join a channel.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::BlackList;

use warnings;
use strict;

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use Carp ();
use Time::HiRes qw(gettimeofday);

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{filename} = delete $conf{filename};

  $self->{blacklist} = {};

  $self->{pbot}->{commands}->register(sub { return $self->blacklist(@_)    }, "blacklist", 10);

  $self->load_blacklist;
}

sub add {
  my ($self, $channel, $hostmask) = @_;

  $self->{blacklist}->{lc $channel}->{lc $hostmask} = 1;
  $self->save_blacklist();
}

sub remove {
  my $self = shift;
  my ($channel, $hostmask) = @_;

  $channel = lc $channel;
  $hostmask = lc $hostmask;

  if (exists $self->{blacklist}->{$channel}) { 
    delete $self->{blacklist}->{$channel}->{$hostmask};

    if (keys %{ $self->{blacklist}->{$channel} } == 0) {
      delete $self->{blacklist}->{$channel};
    }
  }

  $self->save_blacklist();
}

sub clear_blacklist {
  my $self = shift;
  $self->{blacklist} = {};
}

sub load_blacklist {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->{filename}; }

  if(not defined $filename) {
    Carp::carp "No blacklist path specified -- skipping loading of blacklist";
    return;
  }

  $self->{pbot}->{logger}->log("Loading blacklist from $filename ...\n");
  
  open(FILE, "< $filename") or Carp::croak "Couldn't open $filename: $!\n";
  my @contents = <FILE>;
  close(FILE);

  my $i = 0;

  foreach my $line (@contents) {
    chomp $line;
    $i++;

    my ($channel, $hostmask) = split(/\s+/, $line);
    
    if(not defined $hostmask || not defined $channel) {
         Carp::croak "Syntax error around line $i of $filename\n";
    }
    
    if(exists $self->{blacklist}->{$channel}->{$hostmask}) {
      Carp::croak "Duplicate blacklist entry [$hostmask][$channel] found in $filename around line $i\n";
    }

    $self->{blacklist}->{$channel}->{$hostmask} = 1;
  }

  $self->{pbot}->{logger}->log("  $i entries in blacklist\n");
  $self->{pbot}->{logger}->log("Done.\n");
}

sub save_blacklist {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->{filename}; }

  if(not defined $filename) {
    Carp::carp "No blacklist path specified -- skipping saving of blacklist\n";
    return;
  }

  open(FILE, "> $filename") or die "Couldn't open $filename: $!\n";

  foreach my $channel (keys %{ $self->{blacklist} }) {
    foreach my $hostmask (keys %{ $self->{blacklist}->{$channel} }) {
      print FILE "$channel $hostmask\n";
    }
  }

  close(FILE);
}

sub check_blacklist {
  my $self = shift;
  my ($hostmask, $channel, $nickserv, $gecos) = @_;

  return 0 if not defined $channel;

  foreach my $black_channel (keys %{ $self->{blacklist} }) {
    foreach my $black_hostmask (keys %{ $self->{blacklist}->{$black_channel} }) {
      my $flag = '';
      $flag = $1 if $black_hostmask =~ s/^\$(.)://;

      my $black_channel_escaped = quotemeta $black_channel;
      my $black_hostmask_escaped = quotemeta $black_hostmask;

      $black_channel_escaped  =~ s/\\(\.|\*)/$1/g;
      $black_hostmask_escaped =~ s/\\(\.|\*)/$1/g;

      next if $channel !~ /^$black_channel_escaped$/;

      if ($flag eq 'a' && defined $nickserv && $nickserv =~ /$black_hostmask_escaped/i) {
        $self->{pbot}->{logger}->log("$hostmask nickserv $nickserv blacklisted in channel $channel (matches [\$a:$black_hostmask] host and [$black_channel] channel)\n");
        return 1;
      } elsif ($flag eq 'r' && defined $gecos && $gecos =~ /$black_hostmask_escaped/i) {
        $self->{pbot}->{logger}->log("$hostmask GECOS $gecos blacklisted in channel $channel (matches [\$r:$black_hostmask] host and [$black_channel] channel)\n");
        return 1;
      } elsif ($flag eq '' && $hostmask =~ /$black_hostmask_escaped/i) {
        $self->{pbot}->{logger}->log("$hostmask blacklisted in channel $channel (matches [$black_hostmask] host and [$black_channel] channel)\n");
        return 1;
      }
    }
  }
  return 0;
}

sub blacklist {
    my ($self, $from, $nick, $user, $host, $arguments) = @_;
    $arguments = lc $arguments;

    my ($command, $args) = split / /, $arguments, 2;

    return "Usage: blacklist <command>, where commands are: list/show, add, remove" if not defined $command;

    given($command) {
        when($_ eq "list" or $_ eq "show") {
            my $text = "Blacklist:\n";
            my $entries = 0;
            foreach my $channel (sort keys %{ $self->{blacklist} }) {
              if ($channel eq '.*') {
                $text .= "  all channels:\n";
              } else {
                $text .= "  $channel:\n";
              }
              foreach my $mask (sort keys %{ $self->{blacklist}->{$channel} }) {
                $text .= "    $mask,\n";
                $entries++;
              }
            }
            $text .= "none" if $entries == 0;
            return $text;
        }
        when("add") {
            my ($mask, $channel) = split / /, $args, 2;
            return "Usage: blacklist add <hostmask regex> [channel]" if not defined $mask;

            $channel = '.*' if not defined $channel;

            $self->{pbot}->{logger}->log("$nick!$user\@$host added [$mask] to blacklist for channel [$channel]\n");
            $self->add($channel, $mask);
            return "$mask blacklisted in channel $channel";
        }
        when("remove") {
            my ($mask, $channel) = split / /, $args, 2;
            return "Usage: blacklist remove <hostmask regex> [channel]" if not defined $mask;

            $channel = '.*' if not defined $channel;

            if(exists $self->{blacklist}->{$channel} and not exists $self->{blacklist}->{$channel}->{$mask}) {
              $self->{pbot}->{logger}->log("$nick attempt to remove nonexistent [$mask][$channel] from blacklist\n");
              return "$mask not found in blacklist for channel $channel (use `blacklist list` to display blacklist)";
            }

            $self->remove($channel, $mask);
            $self->{pbot}->{logger}->log("$nick!$user\@$host removed [$mask] from blacklist for channel [$channel]\n");
            return "$mask removed from blacklist for channel $channel";
        }
        default {
            return "Unknown command '$command'; commands are: list/show, add, remove";
        }
    }
}

1;
