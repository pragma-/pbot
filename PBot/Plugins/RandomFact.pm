# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Author: Joey Pabalinas <alyptik@protonmail.com>

package PBot::Plugins::RandomFact;

use warnings;
use strict;

use Getopt::Long qw(GetOptionsFromString);
use Carp ();

sub new {
  Carp::croak("Options to " . __FILE__ . " should be key/value pairs, not hash reference") if ref $_[1] eq 'HASH';
  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference to " . __FILE__);
  $self->{pbot}->{commands}->register(sub { $self->rand_factoid(@_) }, 'rfact', 0);
}

sub unload {
  my $self = shift;
  $self->{pbot}->{commands}->unregister('rfact');
}

sub rand_factoid
{
  my ($self, $from, $nick, $user, $host, $arguments) = @_;

  if(not defined $from) {
    $self->{pbot}->{logger}->log("Command missing ~from parameter!\n");
    return "";
  }

  my $usage = "Usage: rfact [<channel>] [-c,channel <channel>] [-t,text <text>] [-x <nick>]";

  if(not defined $arguments or not length $arguments) {
    return $usage;
  }

  $arguments = lc $arguments;

  my @factoids = split /\s\+\s/, $arguments;

  my $getopt_error;
  local $SIG{__WARN__} = sub {
    $getopt_error = shift;
    chomp $getopt_error;
  };

  my $factoid_text = "";
  Getopt::Long::Configure ("bundling");

  foreach my $factoid (@factoids) {
    my ($factoid_nick, $factoid_history, $factoid_channel, $factoid_context);

    $factoid =~ s/(?<!\\)'/\\'/g;
    my ($ret, $args) = GetOptionsFromString($factoid,
      "channel|c:s"        => \$factoid_channel,
      "text|t:s"           => \$factoid_text);

    return "/say $getopt_error -- $usage" if defined $getopt_error;

    my @channels = keys %{$self->{pbot}->{factoids}->{factoids}->hash};

    $factoid_channel = shift @$args if not defined $factoid_channel;
    $factoid_channel = '.*'if $factoid_channel =~ m/\./;

    if ($factoid_channel) {
      return $usage unless join(" ", @channels) =~ m/$factoid_channel/;
    } else {
      $factoid_channel = $channels[int rand @channels];
    }

    my @triggers = keys %{$self->{pbot}->{factoids}->{factoids}->hash->{$factoid_channel}};
    my $factoid_trigger;

    if ($factoid_text) {
      my @filtered = grep {
          $self->{pbot}->{factoids}->{factoids}->hash->{$factoid_channel}->{$_}->{action} =~ m/$factoid_text/;
      } @triggers;
      if (scalar @filtered == 0) {
        return "\"$factoid_text\" not found.";
      }
      $factoid_trigger = $filtered[int rand @filtered];
    } else {
      $factoid_trigger = $triggers[int rand @triggers];
    }

    my $factoid_owner = $self->{pbot}->{factoids}->{factoids}->hash->{$factoid_channel}->{$factoid_trigger}->{owner};
    my $factoid_action = $self->{pbot}->{factoids}->{factoids}->hash->{$factoid_channel}->{$factoid_trigger}->{action};
    return "$factoid_trigger is \"$factoid_action\" (created by $factoid_owner [$factoid_channel])";
  }
}

1;
