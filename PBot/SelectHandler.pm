package PBot::SelectHandler;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = '1.0.0';

use IO::Select;
use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to SelectHandler should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  $self->{pbot} = delete $conf{pbot} // Carp::croak("Missing pbot reference in SelectHandler");
  $self->{select} = IO::Select->new();
  $self->{readers} = {};
}

sub add_reader {
  my ($self, $handle, $sub) = @_;
  $self->{select}->add($handle);
  $self->{readers}->{$handle} = $sub;
}

sub remove_reader {
  my ($self, $handle) = @_;
  $self->{select}->remove($handle);
  delete $self->{readers}->{$handle};
}

sub do_select {
  my ($self) = @_;
  my @ready = $self->{select}->can_read(.5);
  foreach my $fh (@ready) {
    my $ret = sysread($fh, my $buf, 8192);

    if(not defined $ret) {
      $self->{pbot}->logger->log("Error with $fh: $!\n");
      $self->remove_reader($fh);
      next;
    }

    if($ret == 0) {
      $self->remove_reader($fh);
      next;
    }

    chomp $buf;

    if(not exists $self->{readers}->{$fh}) {
      $self->{pbot}->logger->log("Error: no reader for $fh\n");
    } else {
      $self->{readers}->{$fh}->($buf);
    }
  }
}

1;
