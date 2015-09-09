# File: Quotegrabs_Hashtable.pm
# Author: pragma_
#
# Purpose: Hashtable backend for storing and retreiving quotegrabs

package PBot::Plugins::Quotegrabs::Quotegrabs_Hashtable;

use warnings;
use strict;

use HTML::Entities;
use Time::Duration;
use Time::HiRes qw(gettimeofday);
use Getopt::Long qw(GetOptionsFromString);

use POSIX qw(strftime);

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

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference in " . __FILE__);
  $self->{filename} = delete $conf{filename};
  $self->{quotegrabs} = [];
}

sub begin {
  my $self = shift;
  $self->load_quotegrabs;
}

sub end {
}

sub load_quotegrabs {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->{filename}; }
  return if not defined $filename;

  $self->{pbot}->{logger}->log("Loading quotegrabs from $filename ...\n");
  
  open(FILE, "< $filename") or die "Couldn't open $filename: $!\n";
  my @contents = <FILE>;
  close(FILE);

  my $i = 0;
  foreach my $line (@contents) {
    chomp $line;
    $i++;
    my ($nick, $channel, $timestamp, $grabbed_by, $text) = split(/\s+/, $line, 5);
    if(not defined $nick || not defined $channel || not defined $timestamp
       || not defined $grabbed_by || not defined $text) {
      die "Syntax error around line $i of $filename\n";
    }

    my $quotegrab = {};
    $quotegrab->{nick} = $nick;
    $quotegrab->{channel} = $channel;
    $quotegrab->{timestamp} = $timestamp;
    $quotegrab->{grabbed_by} = $grabbed_by;
    $quotegrab->{text} = $text;
    $quotegrab->{id} = $i + 1;
    push @{ $self->{quotegrabs} }, $quotegrab;
  }
  $self->{pbot}->{logger}->log("  $i quotegrabs loaded.\n");
  $self->{pbot}->{logger}->log("Done.\n");
}

sub save_quotegrabs {
  my $self = shift;
  my $filename;

  if(@_) { $filename = shift; } else { $filename = $self->{filename}; }
  return if not defined $filename;

  open(FILE, "> $filename") or die "Couldn't open $filename: $!\n";

  for(my $i = 0; $i <= $#{ $self->{quotegrabs} }; $i++) {
    my $quotegrab = $self->{quotegrabs}[$i];
    next if $quotegrab->{timestamp} == 0;
    print FILE "$quotegrab->{nick} $quotegrab->{channel} $quotegrab->{timestamp} $quotegrab->{grabbed_by} $quotegrab->{text}\n";
  }

  close(FILE);
}

sub add_quotegrab {
  my ($self, $quotegrab) = @_;

  push @{ $self->{quotegrabs} }, $quotegrab;
  $self->save_quotegrabs();
  return $#{ $self->{quotegrabs} } + 1;
}

sub delete_quotegrab {
  my ($self, $id) = @_;

  if($id < 1 || $id > $#{ $self->{quotegrabs} } + 1) {
    return undef;
  }

  splice @{ $self->{quotegrabs} }, $id - 1, 1;

  for(my $i = $id - 1; $i <= $#{ $self->{quotegrabs} }; $i++ ) {
    $self->{quotegrabs}[$i]->{id}--;
  }

  $self->save_quotegrabs();
}

sub get_quotegrab {
  my ($self, $id) = @_;

  if($id < 1 || $id > $#{ $self->{quotegrabs} } + 1) {
    return undef;
  }

  return $self->{quotegrabs}[$id - 1];
}

sub get_random_quotegrab {
  my ($self, $nick, $channel, $text) = @_;

  $nick = '.*' if not defined $nick;
  $channel = '.*' if not defined $channel;
  $text = '.*' if not defined $text;

  my @quotes;
  
  eval {
    for(my $i = 0; $i <= $#{ $self->{quotegrabs} }; $i++) {
      my $hash = $self->{quotegrabs}[$i];
      if($hash->{channel} =~ /$channel/i && $hash->{nick} =~ /$nick/i && $hash->{text} =~ /$text/i) {
        $hash->{id} = $i + 1;
        push @quotes, $hash;
      }
    }
  };

  if($@) {
    $self->{pbot}->{logger}->log("Error in show_random_quotegrab parameters: $@\n");
    return undef;
  }
  
  if($#quotes < 0) {
    return undef;
  }

  return $quotes[int rand($#quotes + 1)];
}

sub get_all_quotegrabs {
  my $self = shift;
  return $self->{quotegrabs};
}

1;
