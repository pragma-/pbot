# File: Channels.pm
# Author: pragma_
#
# Purpose: Manages list of channels and auto-joins.

package PBot::Channels;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = $PBot::PBot::VERSION;

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
     Carp::croak ("Options to Commands should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $pbot = delete $conf{pbot};
  if(not defined $pbot) {
     Carp::croak ("Missing pbot reference to Channels");
  }

  my $channels_file = delete $conf{filename};

  $self->{pbot} = $pbot;
  $self->{filename} = $channels_file;
  $self->{channels} = {};
}

sub load_channels {
  my $self = shift;

  open(FILE, "< $self->{filename}") or Carp::croak "Couldn't open $self->{filename}: $!\n";
  my @contents = <FILE>;
  close(FILE);

  $self->{pbot}->logger->log("Loading channels from $self->{filename} ...\n");

  my $i = 0;
  foreach my $line (@contents) {
    $i++;
    chomp $line;
    
    my ($channel, $enabled, $is_op, $showall) = split(/\s+/, $line);
    if(not defined $channel || not defined $is_op || not defined $enabled) {
      Carp::croak "Syntax error around line $i of $self->{filename}\n";
    }

    $channel = lc $channel;

    if(defined ${ $self->channels }{$channel}) {
      Carp::croak "Duplicate channel $channel found in $self->{filename} around line $i\n";
    }
    
    ${ $self->channels }{$channel}{enabled} = $enabled;
    ${ $self->channels }{$channel}{is_op} = $is_op;
    ${ $self->channels }{$channel}{showall} = $showall;
    
    $self->{pbot}->logger->log("  Adding channel $channel (enabled: $enabled, op: $is_op, showall: $showall) ...\n");
  }
  
  $self->{pbot}->logger->log("Done.\n");
}

sub save_channels {
  my $self = shift;
  open(FILE, "> $self->{filename}") or Carp::croak "Couldn't open $self->{filename}: $!\n";
  foreach my $channel (keys %{ $self->channels }) {
    $channel = lc $channel;
    print FILE "$channel ${ $self->channels }{$channel}{enabled} ${ $self->channels }{$channel}{is_op} ${ $self->channels }{$channel}{showall}\n";
  }
  close(FILE);
}

sub PBot::Channels::channels {
  # Carp::cluck "PBot::Channels::channels";
  my $self = shift;
  return $self->{channels};
}

1;
