package PBot::Utils::LWPUserAgentCached;
use strict;

# Purpose: variant of LWP::UserAgent::WithCache. Instead of depending on
# the 'expires' or 'Last-Modified' attributes, we always cache for the
# specified duration.

use base qw/LWP::UserAgent/;
use Cache::FileCache;
use File::HomeDir;
use File::Spec;

our %default_cache_args = (
  'namespace' => 'pbot-cached',
  'cache_root' => File::Spec->catfile(File::HomeDir->my_home, '.cache'),
  'default_expires_in' => 600
);

sub new {
  my $class = shift;
  my $cache_opt;
  my %lwp_opt;
  unless (scalar @_ % 2) {
    %lwp_opt = @_;
    $cache_opt = {};
    for my $key (qw(namespace cache_root default_expires_in)) {
      $cache_opt->{$key} = delete $lwp_opt{$key} if exists $lwp_opt{$key};
    }
  } else {
    $cache_opt = shift || {};
    %lwp_opt = @_;
  }
  my $self = $class->SUPER::new(%lwp_opt);
  my %cache_args = (%default_cache_args, %$cache_opt);
  $self->{cache} = Cache::FileCache->new(\%cache_args);
  return $self
}

sub request {
  my ($self, @args) = @_;
  my $request = $args[0];

  return $self->SUPER::request(@args) if $request->method ne 'GET';

  my $uri = $request->uri->as_string;
  my $cached = $self->{cache}->get($uri);

  if (defined $cached) {
    return HTTP::Response->parse($cached);
  }

  my $res = $self->SUPER::request(@args);

  if ($res->code eq HTTP::Status::RC_OK) {
    $self->{cache}->set($uri, $res->as_string);
  }

  return $res;
}

1;
