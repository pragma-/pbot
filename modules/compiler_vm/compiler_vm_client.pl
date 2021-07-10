#!/usr/bin/env perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

use File::Basename;
use JSON;

use lib '.';

my $json = join ' ', @ARGV;
my $h = decode_json $json;

my $language = lc $h->{lang};

eval {
  use lib 'languages';
  require "$language.pm";
} or do {
  my @modules = glob 'languages/*.pm';
  my $found = 0;
  my ($languages, $comma) = ('', '');

  foreach my $module (sort @modules) {
    $module = basename $module;
    $module =~ s/.pm$//;
    next if $module =~ m/^_/;

    require "$module.pm" or die $!;
    my $mod = $module->new;


    if (exists $mod->{name} and $mod->{name} eq $language) {
      $language = $module;
      $found = 1;
      last;
    }

    $module = $mod->{name} if exists $mod->{name};
    $languages .= "$comma$module";
    $comma = ', ';
  }

  if (not $found) {
    print "Language '$language' is not supported.\nSupported languages are: $languages\n";
    exit;
  }
};

if (not length $h->{code}) {
  if (exists $h->{usage}) {
    print "$h->{usage}\n";
  } else {
    print "Usage: cc [-lang=<language>] [-info] [-paste] [-args \"command-line arguments\"] [compiler/language options] <code> [-stdin <stdin input>]\n";
  }
  exit;
}

my $lang = $language->new(%{$h});

$lang->{local} = $ENV{CC_LOCAL};

$lang->process_interactive_edit;
$lang->process_standard_options;
$lang->process_custom_options;
$lang->process_cmdline_options;
$lang->preprocess_code;
$lang->execute;
$lang->postprocess_output;
$lang->show_output;
