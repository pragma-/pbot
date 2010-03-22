package PBot::Logger;

use warnings;
use strict;

use vars qw($VERSION);
$VERSION = '1.0.0';

use Carp ();

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Logger should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $log_file = delete $conf{log_file};

  if(defined $log_file) {
    open PLOG_FILE, ">>$log_file" or Carp::croak "Couldn't open log file: $!\n" if defined $log_file;
    PLOG_FILE->autoflush(1);
  }

  my $self = {
    log_file => $log_file,
  };

  bless $self, $class;

  return $self;
}

sub log {
  my ($self, $text) = @_;
  my $time = localtime;

  if(defined $self->{log_file}) {
    print PLOG_FILE "$time :: $text";
  } 

  print "$time :: $text";
}

1;
