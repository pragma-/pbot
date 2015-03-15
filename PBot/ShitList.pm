# File: ShitList.pm
# Author: pragma_
#
# Purpose: Manages list of hostmasks that are not allowed to join a channel.

package PBot::ShitList;

use warnings;
use strict;

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

  $self->{shitlist} = {};

  $self->{pbot}->{commands}->register(sub { return $self->shitlist_user(@_)    },    "shitlist",    10);
  $self->{pbot}->{commands}->register(sub { return $self->unshitlist_user(@_)  },    "unshitlist",  10);

  $self->load_shitlist;
}

sub add {
  my ($self, $channel, $hostmask) = @_;

  $self->{shitlist}->{lc $channel}->{lc $hostmask} = 1;
  $self->save_shitlist();
}

sub remove {
  my $self = shift;
  my ($channel, $hostmask) = @_;

  $channel = lc $channel;
  $hostmask = lc $hostmask;

  if (exists $self->{shitlist}->{$channel}) { 
    delete $$self->{shitlist}->{$channel}->{$hostmask};
  }

  if (keys $self->{shitlist}->{$channel} == 0) {
    delete $self->{shitlist}->{$channel};
  }

  $self->save_shitlist();
}

sub load_shitlist {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->{filename}; }

  if(not defined $filename) {
    Carp::carp "No shitlist path specified -- skipping loading of shitlist";
    return;
  }

  $self->{pbot}->{logger}->log("Loading shitlist from $filename ...\n");
  
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
    
    if(exists $self->{shitlist}->{$channel}->{$hostmask}) {
      Carp::croak "Duplicate shitlist entry [$hostmask][$channel] found in $filename around line $i\n";
    }

    $self->{shitlist}->{$channel}->{$hostmask} = 1;
  }

  $self->{pbot}->{logger}->log("  $i entries in shitlist\n");
  $self->{pbot}->{logger}->log("Done.\n");
}

sub save_shitlist {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->{filename}; }

  if(not defined $filename) {
    Carp::carp "No shitlist path specified -- skipping saving of shitlist\n";
    return;
  }

  open(FILE, "> $filename") or die "Couldn't open $filename: $!\n";

  foreach my $channel (keys %{ $self->{shitlist} }) {
    foreach my $hostmask (keys %{ $self->{shitlist}->{$channel} }) {
      print FILE "$channel $hostmask\n";
    }
  }

  close(FILE);
}

sub check_shitlist {
  my $self = shift;
  my ($hostmask, $channel) = @_;

  return 0 if not defined $channel;

  foreach my $shit_channel (keys %{ $self->{shitlist} }) {
    foreach my $shit_hostmask (keys %{ $self->{shitlist}->{$shit_channel} }) {
      my $shit_channel_escaped = quotemeta $shit_channel;
      my $shit_hostmask_escaped = quotemeta $shit_hostmask;

      $shit_channel_escaped  =~ s/\\(\.|\*)/$1/g;
      $shit_hostmask_escaped =~ s/\\(\.|\*)/$1/g;

      if(($channel =~ /$shit_channel_escaped/i) && ($hostmask =~ /$shit_hostmask_escaped/i)) {
        $self->{pbot}->{logger}->log("$hostmask shitlisted in channel $channel (matches [$shit_hostmask] host and [$shit_channel] channel)\n");
        return 1;
      }
    }
  }
  return 0;
}

sub shitlist_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;

  return "Usage: shitlist <hostmask regex> [channel]" if not $arguments;

  my ($target, $channel) = split /\s+/, $arguments;

  if($target =~ /^list$/i) {
    my $text = "Shitlisted: ";

    my $sep = "";
    foreach my $channel (keys %{ $self->{shitlist} }) {
      $text .= "$channel: ";
      foreach my $hostmask (keys %{ $self->{shitlist}->{$channel} }) {
        $text .= $sep . $hostmask;
        $sep = ";\n";
      }
    }
    return $text;
  }

  if(not defined $channel) {
    $channel = ".*"; # all channels
  }
  
  $self->{pbot}->{logger}->log("$nick!$user\@$host added [$target] to shitlist for channel [$channel]\n");
  $self->add($channel, $target);
  return "$target added to shitlist for channel $channel";
}

sub unshitlist_user {
  my $self = shift;
  my ($from, $nick, $user, $host, $arguments) = @_;
  my ($channel, $target) = split /\s+/, $arguments if $arguments;

  if(not defined $target) {
    return "Usage: unshitlist <hostmask regex> [channel]";
  }

  if(not defined $channel) {
    $channel = ".*";
  }
  
  if(not exists $self->{shitlist}->{$channel} and not exists $self->{shitlist}->{$channel}->{$target}) {
    $self->{pbot}->{logger}->log("$nick attempt to remove nonexistent [$target][$channel] from shitlist\n");
    return "$target not found in shitlist for channel $channel (use `shitlist list` to display shitlist)";
  }
  
  $self->remove($channel, $target);
  $self->{pbot}->{logger}->log("$nick!$user\@$host removed [$target] from shitlist for channel [$channel]\n");
  return "$target removed from shitlist for channel $channel";
}

1;
