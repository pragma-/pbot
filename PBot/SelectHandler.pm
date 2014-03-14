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

sub do_select {
  my ($self) = @_;
  my @ready = $self->{select}->can_read(.5);
  foreach my $fh (@ready) {
    my $ret = sysread($fh, my $buf, 4096);

    if(not defined $ret) {
      $self->{pbot}->logger->log("Error with $fh: $!\n");
      $self->{select}->remove($fh);
      delete $self->{readers}->{$fh};
      next;
    }

    if($ret == 0) {
      $self->{pbot}->logger->log("done with $fh\n");
      $self->{select}->remove($fh);
      delete $self->{readers}->{$fh};
      next;
    }

    chomp $buf;
    $self->{pbot}->logger->log("read from $fh: [$buf]\n");

    if(not exists $self->{readers}->{$fh}) {
      $self->{pbot}->logger->log("Error: no reader for $fh\n");
    } else {
      $self->{readers}->{$fh}->($buf);
    }
  }
}

1;
