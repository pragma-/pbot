# File: Logger.pm
#
# Purpose: Logs text to file and STDOUT.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Logger;

use PBot::Imports;

use Scalar::Util qw/openhandle/;
use File::Basename;
use File::Copy;

sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    Carp::croak("Missing pbot reference to " . __FILE__) unless exists $args{pbot};
    $self->{pbot} = delete $args{pbot};
    print "Initializing " . __PACKAGE__ . "\n" unless $self->{pbot}->{overrides}->{'general.daemon'};
    $self->initialize(%args);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    # ensure logfile path was provided
    $self->{logfile} = $conf{filename} // Carp::croak "Missing logfile parameter in " . __FILE__;


    # record start time for later logfile rename in rotation
    $self->{start} = time;

    # get directories leading to logfile
    my $path = dirname $self->{logfile};

    # create log file path
    if (not -d $path) {
        print "Creating new logfile path: $path\n" unless $self->{pbot}->{overrides}->{'general.daemon'};
        mkdir $path or Carp::croak "Couldn't create logfile path: $!\n";
    }

    # open log file with utf8 encoding
    open LOGFILE, ">> :encoding(UTF-8)", $self->{logfile} or Carp::croak "Couldn't open logfile $self->{logfile}: $!\n";
    LOGFILE->autoflush(1);

    # rename logfile to start-time at exit
    $self->{pbot}->{atexit}->register(sub { $self->rotate_log; return; });
}

sub log {
    my ($self, $text) = @_;

    # get current time
    my $time = localtime;

    # replace potentially log-corrupting characters (colors, gibberish, etc)
    $text =~ s/(\P{PosixGraph})/my $ch = $1; if ($ch =~ m{[\s]}) { $ch } else { sprintf "\\x%02X", ord $ch }/ge;

    # log to file
    print LOGFILE "$time :: $text" if openhandle * LOGFILE;

    # and print to stdout unless daemonized
    print STDOUT "$time :: $text" unless $self->{pbot}->{overrides}->{'general.daemon'};
}

sub rotate_log {
    my ($self) = @_;

    # get start time
    my $time = localtime $self->{start};
    $time =~ s/\s+/_/g; # replace spaces with underscores

    $self->log("Rotating log to $self->{logfile}-$time\n");

    # rename log to start time
    move($self->{logfile}, $self->{logfile} . '-' . $time);

    # set new start time for next rotation
    $self->{start} = time;
}

1;
