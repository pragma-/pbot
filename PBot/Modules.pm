# File: Modules.pm
# Author: pragma_

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::Modules;

use parent 'PBot::Class';

use warnings; use strict;
use feature 'unicode_strings';

use IPC::Run qw/run timeout/;
use Encode;

sub initialize {
    my ($self, %conf) = @_;
    $self->{pbot}->{commands}->register(sub { $self->load_cmd(@_) },   "load",   1);
    $self->{pbot}->{commands}->register(sub { $self->unload_cmd(@_) }, "unload", 1);
}

sub load_cmd {
    my ($self, $from, $nick, $user, $host, $arguments, $context) = @_;
    my $factoids = $self->{pbot}->{factoids}->{factoids};
    my ($keyword, $module) = $self->{pbot}->{interpreter}->split_args($context->{arglist}, 2);
    return "Usage: load <keyword> <module>" if not defined $module;

    if ($factoids->exists('.*', $keyword)) { return 'There is already a keyword named ' . $factoids->get_data('.*', $keyword, '_name') . '.'; }

    $self->{pbot}->{factoids}->add_factoid('module', '.*', "$nick!$user\@$host", $keyword, $module, 1);
    $factoids->set('.*', $keyword, 'add_nick', 1, 1);
    $factoids->set('.*', $keyword, 'nooverride', 1);
    $self->{pbot}->{logger}->log("$nick!$user\@$host loaded module $keyword => $module\n");
    return "Loaded module $keyword => $module";
}

sub unload_cmd {
    my ($self, $from, $nick, $user, $host, $arguments, $context) = @_;
    my $module = $self->{pbot}->{interpreter}->shift_arg($context->{arglist});
    return "Usage: unload <keyword>" if not defined $module;
    my $factoids = $self->{pbot}->{factoids}->{factoids};
    return "/say $module not found." if not $factoids->exists('.*', $module);

    if ($factoids->get_data('.*', $module, 'type') ne 'module') { return "/say " . $factoids->get_data('.*', $module, '_name') . ' is not a module.'; }

    my $name = $factoids->get_data('.*', $module, '_name');
    $factoids->remove('.*', $module);
    $self->{pbot}->{logger}->log("$nick!$user\@$host unloaded module $module\n");
    return "/say $name unloaded.";
}

sub execute_module {
    my ($self, $context) = @_;
    my $text;

    if ($self->{pbot}->{registry}->get_value('general', 'debugcontext')) {
        use Data::Dumper;
        $Data::Dumper::Sortkeys = 1;
        $self->{pbot}->{logger}->log("execute_module\n");
        $self->{pbot}->{logger}->log(Dumper $context);
    }

    $self->{pbot}->{process_manager}->execute_process($context, sub { $self->launch_module(@_) });
}

sub launch_module {
    my ($self, $context) = @_;
    $context->{arguments} = "" if not defined $context->{arguments};
    my @factoids = $self->{pbot}->{factoids}->find_factoid($context->{from}, $context->{keyword}, exact_channel => 2, exact_trigger => 2);
    if (not @factoids or not $factoids[0]) {
        $context->{checkflood} = 1;
        $self->{pbot}->{interpreter}->handle_result($context, "/msg $context->{nick} Failed to find module for '$context->{keyword}' in channel $context->{from}\n");
        return;
    }

    my ($channel, $trigger) = ($factoids[0]->[0], $factoids[0]->[1]);
    $context->{channel} = $channel;
    $context->{keyword} = $trigger;
    $context->{trigger} = $trigger;

    my $module = $self->{pbot}->{factoids}->{factoids}->get_data($channel, $trigger, 'action');
    $self->{pbot}->{logger}->log("("
          . (defined $context->{from} ? $context->{from} : "(undef)")
          . "): $context->{nick}!$context->{user}\@$context->{host}: Executing module [$context->{command}] $module $context->{arguments}\n");
    $context->{arguments} = $self->{pbot}->{factoids}->expand_special_vars($context->{from}, $context->{nick}, $context->{root_keyword}, $context->{arguments});

    my $module_dir = $self->{pbot}->{registry}->get_value('general', 'module_dir');
    if (not chdir $module_dir) {
        $self->{pbot}->{logger}->log("Could not chdir to '$module_dir': $!\n");
        Carp::croak("Could not chdir to '$module_dir': $!");
    }

    if ($self->{pbot}->{factoids}->{factoids}->exists($channel, $trigger, 'workdir')) {
        chdir $self->{pbot}->{factoids}->{factoids}->get_data($channel, $trigger, 'workdir');
    }

    # FIXME -- add check to ensure $module exists
    my ($exitval, $stdout, $stderr) = eval {
        my $args = $context->{arguments};
        if (not $context->{args_utf8}) { $args = encode('UTF-8', $args); }
        my @cmdline = ("./$module", $self->{pbot}->{interpreter}->split_line($args));
        my $timeout = $self->{pbot}->{registry}->get_value('general', 'module_timeout') // 30;
        my ($stdin, $stdout, $stderr);
        run \@cmdline, \$stdin, \$stdout, \$stderr, timeout($timeout);
        my $exitval = $? >> 8;
        utf8::decode($stdout);
        utf8::decode($stderr);
        return ($exitval, $stdout, $stderr);
    };

    if ($@) {
        my $error = $@;
        if   ($error =~ m/timeout on timer/) { ($exitval, $stdout, $stderr) = (-1, "$context->{trigger}: timed-out", ''); }
        else                                 { ($exitval, $stdout, $stderr) = (-1, '',                             $error); }
    }

    if (length $stderr) {
        if (open(my $fh, '>>', "$module-stderr")) {
            print $fh $stderr;
            close $fh;
        } else {
            $self->{pbot}->{logger}->log("Failed to open $module-stderr: $!\n");
        }
    }

    $context->{result} = $stdout;
    chomp $context->{result};
}

1;
