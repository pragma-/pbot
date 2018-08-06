# File: AntiSpam.pm
# Author: pragma_
#
# Purpose: Checks if a message is spam

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::AntiSpam;

use warnings;
use strict;

use feature 'switch';
no if $] >= 5.018, warnings => "experimental::smartmatch";

use PBot::DualIndexHashObject;

use Carp ();
use Time::HiRes qw(gettimeofday);
use POSIX qw/strftime/;

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref($_[1]) eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;
  
  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);

  my $filename = delete $conf{spamkeywords_file} // $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/spam_keywords';
  $self->{keywords} = PBot::DualIndexHashObject->new(name => 'SpamKeywords', filename => $filename);
  $self->{keywords}->load;

  $self->{pbot}->{registry}->add_default('text', 'antispam', 'enforce',  $conf{enforce_antispam} // 1);
  $self->{pbot}->{commands}->register(sub { return $self->antispam_cmd(@_) }, "antispam", 10);
}

sub is_spam {
  my ($self, $channel, $text) = @_;

  return 0 if not $self->{pbot}->{registry}->get_value('antispam', 'enforce');
  return 0 if $self->{pbot}->{registry}->get_value($channel, 'dont_enforce_antispam');

  my $ret = eval {
    foreach my $chan (keys %{ $self->{keywords}->hash }) {
      next unless $channel =~ m/^$chan$/i;
      foreach my $keyword (keys %{ $self->{keywords}->hash->{$chan} }) {
        return 1 if $text =~ m/$keyword/i;
      }
    }
    return 0;
  };

  if ($@) {
    $self->{pbot}->{logger}->log("Error in is_spam: $@");
    return 0;
  }
  $self->{pbot}->{logger}->log("AntiSpam: spam detected!\n") if $ret;
  return $ret;
}

sub antispam_cmd {
  my ($self, $from, $nick, $user, $host, $arguments) = @_;
  $arguments = lc $arguments;

  my ($command, $args) = split /\s+/, $arguments, 2;

  return "Usage: antispam <command>, where commands are: list/show, add, remove, set, unset" if not defined $command;

  given ($command) {
    when ($_ eq "list" or $_ eq "show") {
      my $text = "Spam keywords:\n";
      my $entries = 0;
      foreach my $channel (keys %{ $self->{keywords}->hash }) {
        $text .= "  $channel:\n";
        foreach my $keyword (keys %{ $self->{keywords}->hash->{$channel} }) {
          $text .= "    $keyword,\n";
          $entries++;
        }
      }
      $text .= "none" if $entries == 0;
      return $text;
    }
    when ("set") {
      my ($channel, $keyword, $flag, $value) = split /\s+/, $args, 4;
      return "Usage: keywords set <channel> <keyword> [flag] [value]" if not defined $channel or not defined $keyword;

      if (not exists $self->{keywords}->hash->{$channel}) {
        return "There is no such channel `$channel` in the keywords.";
      }

      if (not exists $self->{keywords}->hash->{$channel}->{$keyword}) {
        return "There is no such keyword `$keyword` for channel `$channel` in the keywords.";
      }

      if (not defined $flag) {
        my $text = "Flags:\n";
        my $comma = '';
        foreach $flag (keys %{ $self->{keywords}->hash->{$channel}->{$keyword} }) {
          if ($flag eq 'created_on') {
            my $timestamp = strftime "%a %b %e %H:%M:%S %Z %Y", localtime $self->{keywords}->hash->{$channel}->{$keyword}->{$flag};
            $text .= $comma . "created_on: $timestamp";
          } else {
            $value = $self->{keywords}->hash->{$channel}->{$keyword}->{$flag};
            $text .= $comma .  "$flag: $value";
          }
          $comma = ",\n  ";
        }
        return $text;
      }

      if (not defined $value) {
        $value = $self->{keywords}->hash->{$channel}->{$keyword}->{$flag};
        if (not defined $value) {
          return "/say $flag is not set.";
        } else {
          return "/say $flag is set to $value";
        }
      }

      $self->{keywords}->hash->{$channel}->{$keyword}->{$flag} = $value;
      $self->{keywords}->save;
      return "Flag set.";
    }
    when ("unset") {
      my ($channel, $keyword, $flag) = split /\s+/, $args, 3;
      return "Usage: keywords unset <channel> <keyword> <flag>" if not defined $channel or not defined $keyword or not defined $flag;

      if (not exists $self->{keywords}->hash->{$channel}) {
        return "There is no such channel `$channel` in the keywords.";
      }

      if (not exists $self->{keywords}->hash->{$channel}->{$keyword}) {
        return "There is no such keyword `$keyword` for channel `$channel` in the keywords.";
      }

      if (not exists $self->{keywords}->hash->{$channel}->{$keyword}->{$flag}) {
        return "There is no such flag `$flag` for keyword `$keyword` for channel `$channel` in the keywords.";
      }

      delete $self->{keywords}->hash->{$channel}->{$keyword}->{$flag};
      $self->{keywords}->save;
      return "Flag unset.";
    }
    when ("add") {
      my ($channel, $keyword) = split /\s+/, $args, 2;
      return "Usage: keywords add <channel> <keyword>" if not defined $channel or not defined $keyword;
      $self->{keywords}->hash->{$channel}->{$keyword}->{owner} = "$nick!$user\@$host";
      $self->{keywords}->hash->{$channel}->{$keyword}->{created_on} = gettimeofday;
      $self->{keywords}->save;
      return "/say Added.";
    }
    when ("remove") {
      my ($channel, $keyword) = split /\s+/, $args, 2;
      return "Usage: keywords remove <channel> <keyword>" if not defined $channel or not defined $keyword;

      if(not defined $self->{keywords}->hash->{$channel}) {
        return "No entries for channel $channel";
      }

      if(not defined $self->{keywords}->hash->{$channel}->{$keyword}) {
        return "No such entry for channel $channel";
      }

      delete $self->{keywords}->hash->{$channel}->{$keyword};
      delete $self->{keywords}->hash->{$channel} if keys %{ $self->{keywords}->hash->{$channel} } == 0;
      $self->{keywords}->save;
      return "/say Removed.";
    }
    default {
      return "Unknown command '$command'; commands are: list/show, add, remove";
    }
  }
}

1;
