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
  print "Language '$language' is not supported.\n";

  my @languages = glob 'languages/*.pm';
  my $comma = '';
  print "Supported languages are: ";
  print join(", ", grep { $_ = basename $_; $_ =~ s/.pm$//; $_ !~ m/^_/ } sort @languages);
  print "\n";

  exit;
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
