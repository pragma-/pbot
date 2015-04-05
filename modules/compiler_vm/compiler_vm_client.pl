#!/usr/bin/env perl

use warnings;
use strict;

use File::Basename;

my $language = shift @ARGV // 'c11';
$language = lc $language;

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
    require "$module.pm";
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

my $nick    = shift @ARGV // (print "Missing nick argument.\n" and die);
my $channel = shift @ARGV // (print "Missing channel argument.\n" and die);
my $code    = join(' ', @ARGV);

if (not length $code) {
  print "$nick: Usage: cc [-paste] [-nomain] [-lang=<language>] [-info] [language options] <code> [-input=<stdin input>]\n";
  exit;
}

my $lang = $language->new(nick => $nick, channel => $channel, lang => $language, code => $code);

$lang->process_interactive_edit;
$lang->process_standard_options;
$lang->process_custom_options;
$lang->process_cmdline_options;
$lang->preprocess_code;
$lang->execute;
$lang->postprocess_output;
$lang->show_output;
