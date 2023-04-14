# File: FuncPlural.pm
#
# Purpose: Registers the plural Function.

# SPDX-FileCopyrightText: 2020-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::FuncPlural;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

sub initialize($self, %conf) {
    $self->{pbot}->{functions}->register(
        'plural',
        {
            desc   => 'pluralizes a word or phrase',
            usage  => 'plural <word>',
            subref => sub { $self->func_plural(@_) }
        }
    );
}

sub unload($self) {
    $self->{pbot}->{functions}->unregister('plural');
}

sub pluralize_word($word) {
  my @ignore = qw/trout fish tobacco music snow armor police dice caribou moose people sheep/;

  my %endings = (
    'man' => 'men',
    'ch' => 'ches',
    'sh' => 'shes',
    'eer' => 'eer',
    'mouse' => 'mice',
    'goose' => 'geese',
    'hoof' => 'hooves',
    'wolf' => 'wolves',
    'foot' => 'feet',
    'ss' => 'sses',
    'is' => 'ises',
    'ife' => 'ives',
    'us' => 'uses',
    'x' => 'xes',
    'ium' => 'ia',
    'um' => 'a',
    'stomach' => 'stomachs',
    'cactus' => 'cacti',
    'cactus' => 'cacti',
    'knoif' => 'knoives',
    'sheaf' => 'sheaves',
    'dwarf' => 'dwarves',
    'loaf' => 'loaves',
    'louse' => 'lice',
    'die' => 'dice',
    'calf' => 'calves',
    'self' => 'selves',
    'tooth' => 'teeth',
    'alumnus' => 'alumni',
    'leaf' => 'leaves',
    'ay' => 'ays',
    'ey' => 'eys',
    'child' => 'children',
    'o' => 'oes',
  );

  $word =~ s/^an? //;
  $word =~ s/\bthat\b/those/g; $word =~ s/\bthis\b/these/g;

  return $word if grep { /^\Q$word\E$/i } @ignore;

  foreach my $ending (sort { length $b <=> length $a } keys %endings) {
    return $word if $word =~ s/$ending$/$endings{$ending}/;
  }

  $word =~ s/s$/s/ || $word =~ s/y$/ies/ || $word =~ s/$/s/;

  return $word;
}

sub pluralize($string) {
  if ($string =~ m/(.*?) (containing|packed with|with what appears to be) (.*)/) {
    my $word = pluralize_word $1;
    return "$word $2 $3";
  } elsif ($string =~ m/(.*?) of (.*)/) {
    my $word = pluralize_word $1;
    return "$word of $2";
  } else {
    return pluralize_word $string;
  }
}

sub func_plural($self, @text) {
    return pluralize("@text");
}

1;
