# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package Diff;

use strict;
use HTML::Entities qw(encode_entities);
use vars qw($VERSION @ISA);

$VERSION = '0.08';
@ISA = qw(Text::WordDiff::Base);

sub new {
  my ($class, %conf) = @_;
  return bless \%conf, $class;
}

sub file_header {
  my $header = shift->SUPER::file_header(@_);
  return '' unless $header;
  return $header;
}

sub hunk_header { return '' }
sub hunk_footer { return '' }
sub file_footer { return '' }

sub same_items {
  shift;
  return join '', @_;
}

sub delete_items {
  shift;
  return '<del>' . (join'', @_ ) . '</del>';
}

sub insert_items {
  shift;
  return '<ins>' . ( join'', @_ ) . '</ins>';
}

1;
