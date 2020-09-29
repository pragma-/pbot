# File: PBot.pm
# Author: pragma_
#
# Purpose: IRC Bot (3rd generation)

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::PBot;

use strict; use warnings;
use feature 'unicode_strings';

# unbuffer stdout
STDOUT->autoflush(1);

use Carp ();
use PBot::Logger;
use PBot::VERSION;
use PBot::HashObject;
use PBot::DualIndexHashObject;
use PBot::DualIndexSQLiteObject;
use PBot::Registry;
use PBot::Capabilities;
use PBot::SelectHandler;
use PBot::StdinReader;
use PBot::IRC;
use PBot::EventDispatcher;
use PBot::IRCHandlers;
use PBot::Channels;
use PBot::BanList;
use PBot::NickList;
use PBot::LagChecker;
use PBot::MessageHistory;
use PBot::AntiFlood;
use PBot::AntiSpam;
use PBot::Interpreter;
use PBot::Commands;
use PBot::ChanOps;
use PBot::Factoids;
use PBot::Users;
use PBot::IgnoreList;
use PBot::BlackList;
use PBot::Timer;
use PBot::Refresher;
use PBot::WebPaste;
use PBot::Utils::ParseDate;
use PBot::Plugins;
use PBot::Functions;
use PBot::Modules;
use PBot::ProcessManager;
use PBot::Updater;

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;
    $self->{startup_timestamp} = time;

    my $data_dir   = $conf{data_dir};
    my $module_dir = $conf{module_dir};
    my $plugin_dir = $conf{plugin_dir};
    my $update_dir = $conf{update_dir};

    # process command-line arguments
    foreach my $arg (@ARGV) {
        if ($arg =~ m/^-?(?:general\.)?((?:data|module|plugin|update)_dir)=(.*)$/) {
            # check command-line arguments for directory overrides
            my $override = $1;
            my $value    = $2;
            $value =~ s/[\\\/]$//; # strip trailing directory separator
            $data_dir    = $value if $override eq 'data_dir';
            $module_dir  = $value if $override eq 'module_dir';
            $plugin_dir  = $value if $override eq 'plugin_dir';
            $update_dir  = $value if $override eq 'update_dir';
        } else {
            # check command-line arguments for registry overrides
            my ($item, $value) = split /=/, $arg, 2;

            if (not defined $item or not defined $value) {
                print STDERR "Fatal error: unknown argument `$arg`; arguments must be in the form of `section.key=value` (e.g.: irc.botnick=newnick)\n";
                exit;
            }

            my ($section, $key) = split /\./, $item, 2;
            if (not defined $section or not defined $key) {
                print STDERR "Fatal error: bad argument `$arg`; registry entries must be in the form of section.key (e.g.: irc.botnick)\n";
                exit;
            }

            $section =~ s/^-//;    # remove a leading - to allow arguments like -irc.botnick due to habitual use of -args
            $self->{overrides}->{"$section.$key"} = $value;
        }
    }

    # make sure the data directory exists
    if (not -d $data_dir) {
        print STDERR "Data directory ($data_dir) does not exist; aborting...\n";
        exit;
    }

    # let modules register signal handlers
    $self->{atexit} = PBot::Registerable->new(%conf, pbot => $self);
    $self->register_signal_handlers;

    # create logger
    $self->{logger} = PBot::Logger->new(pbot => $self, filename => "$data_dir/log/log", %conf);

    # make sure the rest of the environment is sane
    if (not -d $module_dir) {
        $self->{logger}->log("Modules directory ($module_dir) does not exist; aborting...\n");
        exit;
    }

    if (not -d $plugin_dir) {
        $self->{logger}->log("Plugins directory ($plugin_dir) does not exist; aborting...\n");
        exit;
    }

    if (not -d $update_dir) {
        $self->{logger}->log("Updates directory ($update_dir) does not exist; aborting...\n");
        exit;
    }

    $self->{updater} = PBot::Updater->new(pbot => $self, data_dir => $data_dir, update_dir => $update_dir);

    # update any data files to new locations/formats
    if ($self->{updater}->update) {
        $self->{logger}->log("Update failed.\n");
        exit 0;
    }

    # create capabilities so commands can add new capabilities
    $self->{capabilities} = PBot::Capabilities->new(pbot => $self, filename => "$data_dir/capabilities", %conf);

    # create commands so the modules can register new commands
    $self->{commands} = PBot::Commands->new(pbot => $self, filename => "$data_dir/commands", %conf);

    # add some commands
    $self->{commands}->register(sub { $self->cmd_list(@_) },   "list");
    $self->{commands}->register(sub { $self->cmd_die(@_) },    "die", 1);
    $self->{commands}->register(sub { $self->cmd_export(@_) }, "export", 1);
    $self->{commands}->register(sub { $self->cmd_reload(@_) }, "reload", 1);
    $self->{commands}->register(sub { $self->cmd_eval(@_) },   "eval", 1);
    $self->{commands}->register(sub { $self->cmd_sl(@_) },     "sl", 1);

    # add 'cap' capability command
    $self->{commands}->register(sub { $self->{capabilities}->cmd_cap(@_) }, "cap");

    # prepare the version
    $self->{version} = PBot::VERSION->new(pbot => $self, %conf);
    $self->{logger}->log($self->{version}->version . "\n");
    $self->{logger}->log("Args: @ARGV\n") if @ARGV;

    $self->{logger}->log("module_dir: $module_dir\n");
    $self->{logger}->log("plugin_dir: $plugin_dir\n");
    $self->{logger}->log("data_dir: $data_dir\n");
    $self->{logger}->log("update_dir: $update_dir\n");


    $self->{timer}     = PBot::Timer->new(pbot => $self, timeout => 10, name => 'PBot Timer', %conf);
    $self->{modules}   = PBot::Modules->new(pbot => $self, %conf);
    $self->{functions} = PBot::Functions->new(pbot => $self, %conf);
    $self->{refresher} = PBot::Refresher->new(pbot => $self);

    # create registry and set some defaults
    $self->{registry} = PBot::Registry->new(pbot => $self, filename => "$data_dir/registry", %conf);

    $self->{registry}->add_default('text', 'general', 'data_dir',   $data_dir);
    $self->{registry}->add_default('text', 'general', 'module_dir', $module_dir);
    $self->{registry}->add_default('text', 'general', 'plugin_dir', $plugin_dir);
    $self->{registry}->add_default('text', 'general', 'update_dir', $update_dir);
    $self->{registry}->add_default('text', 'general', 'trigger',       $conf{trigger} // '!');

    $self->{registry}->add_default('text', 'irc', 'debug',             $conf{irc_debug}         // 0);
    $self->{registry}->add_default('text', 'irc', 'show_motd',         $conf{show_motd}         // 1);
    $self->{registry}->add_default('text', 'irc', 'max_msg_len',       $conf{max_msg_len}       // 425);
    $self->{registry}->add_default('text', 'irc', 'server',            $conf{server}            // "irc.freenode.net");
    $self->{registry}->add_default('text', 'irc', 'port',              $conf{port}              // 6667);
    $self->{registry}->add_default('text', 'irc', 'SSL',               $conf{SSL}               // 0);
    $self->{registry}->add_default('text', 'irc', 'SSL_ca_file',       $conf{SSL_ca_file}       // 'none');
    $self->{registry}->add_default('text', 'irc', 'SSL_ca_path',       $conf{SSL_ca_path}       // 'none');
    $self->{registry}->add_default('text', 'irc', 'botnick',           $conf{botnick}           // "");
    $self->{registry}->add_default('text', 'irc', 'username',          $conf{username}          // "pbot3");
    $self->{registry}->add_default('text', 'irc', 'realname',          $conf{realname}          // "https://github.com/pragma-/pbot");
    $self->{registry}->add_default('text', 'irc', 'identify_password', $conf{identify_password} // '');
    $self->{registry}->add_default('text', 'irc', 'log_default_handler', 1);

    $self->{registry}->set_default('irc', 'SSL_ca_file',       'private', 1);
    $self->{registry}->set_default('irc', 'SSL_ca_path',       'private', 1);
    $self->{registry}->set_default('irc', 'identify_password', 'private', 1);

    # load existing registry entries from file (if exists) to overwrite defaults
    if (-e $self->{registry}->{registry}->{filename}) { $self->{registry}->load; }

    # update important paths
    $self->{registry}->set('general', 'data_dir',   'value', $data_dir,      0, 1);
    $self->{registry}->set('general', 'module_dir', 'value', $module_dir,    0, 1);
    $self->{registry}->set('general', 'plugin_dir', 'value', $plugin_dir,    0, 1);
    $self->{registry}->set('general', 'update_dir', 'value', $update_dir, 0, 1);

    # override registry entries with command-line arguments, if any
    foreach my $override (keys %{$self->{overrides}}) {
        my ($section, $key) = split /\./, $override;
        my $value = $self->{overrides}->{$override};
        $self->{logger}->log("Overriding $section.$key to $value\n");
        $self->{registry}->set($section, $key, 'value', $value, 0, 1);
    }

    # registry triggers fire when value changes
    $self->{registry}->add_trigger('irc', 'botnick', sub { $self->change_botnick_trigger(@_) });
    $self->{registry}->add_trigger('irc', 'debug',   sub { $self->irc_debug_trigger(@_) });

    # ensure user has attempted to configure the bot
    if (not length $self->{registry}->get_value('irc', 'botnick')) {
        $self->{logger}->log("Fatal error: IRC nickname not defined; please set registry key irc.botnick in $data_dir/registry to continue.\n");
        exit;
    }

    $self->{event_dispatcher} = PBot::EventDispatcher->new(pbot => $self, %conf);
    $self->{process_manager}  = PBot::ProcessManager->new(pbot => $self, %conf);
    $self->{irchandlers}      = PBot::IRCHandlers->new(pbot => $self, %conf);
    $self->{select_handler}   = PBot::SelectHandler->new(pbot => $self, %conf);
    $self->{users}            = PBot::Users->new(pbot => $self, filename => "$data_dir/users", %conf);
    $self->{stdin_reader}     = PBot::StdinReader->new(pbot => $self, %conf);
    $self->{lagchecker}       = PBot::LagChecker->new(pbot => $self, %conf);
    $self->{messagehistory}   = PBot::MessageHistory->new(pbot => $self, filename => "$data_dir/message_history.sqlite3", %conf);
    $self->{antiflood}        = PBot::AntiFlood->new(pbot => $self, %conf);
    $self->{antispam}         = PBot::AntiSpam->new(pbot => $self, %conf);
    $self->{ignorelist}       = PBot::IgnoreList->new(pbot => $self, filename => "$data_dir/ignorelist", %conf);
    $self->{blacklist}        = PBot::BlackList->new(pbot => $self, filename => "$data_dir/blacklist", %conf);
    $self->{irc}              = PBot::IRC->new();
    $self->{channels}         = PBot::Channels->new(pbot => $self, filename => "$data_dir/channels", %conf);
    $self->{chanops}          = PBot::ChanOps->new(pbot => $self, %conf);
    $self->{banlist}          = PBot::BanList->new(pbot => $self, %conf);
    $self->{nicklist}         = PBot::NickList->new(pbot => $self, %conf);
    $self->{webpaste}         = PBot::WebPaste->new(pbot => $self, %conf);
    $self->{parsedate}        = PBot::Utils::ParseDate->new(pbot => $self, %conf);

    $self->{interpreter} = PBot::Interpreter->new(pbot => $self, %conf);
    $self->{interpreter}->register(sub { $self->{commands}->interpreter(@_) });
    $self->{interpreter}->register(sub { $self->{factoids}->interpreter(@_) });

    $self->{factoids} = PBot::Factoids->new(pbot => $self, filename => "$data_dir/factoids.sqlite3", %conf);

    $self->{plugins} = PBot::Plugins->new(pbot => $self, %conf);

    # load available plugins
    $self->{plugins}->autoload(%conf);

    # give botowner all capabilities
    $self->{capabilities}->rebuild_botowner_capabilities();

    # flush all pending save events to disk at exit
    $self->{atexit}->register(sub {
            $self->{timer}->execute_and_dequeue_event('save *');
            return;
        }
    );
}

sub random_nick {
    my ($self, $length) = @_;
    $length //= 9;
    my @chars = ("A" .. "Z", "a" .. "z", "0" .. "9");
    my $nick  = $chars[rand @chars - 10];               # nicks cannot start with a digit
    $nick .= $chars[rand @chars] for 1 .. $length;
    return $nick;
}

# TODO: add disconnect subroutine
sub connect {
    my ($self, $server) = @_;
    return if $ENV{PBOT_LOCAL};

    if ($self->{connected}) {
        # TODO: disconnect, clean-up, etc
    }

    $server = $self->{registry}->get_value('irc', 'server') if not defined $server;

    $self->{logger}->log("Connecting to $server ...\n");

    while (
        not $self->{conn} = $self->{irc}->newconn(
            Nick     => $self->{registry}->get_value('irc', 'randomize_nick') ? $self->random_nick : $self->{registry}->get_value('irc', 'botnick'),
            Username => $self->{registry}->get_value('irc', 'username'),
            Ircname  => $self->{registry}->get_value('irc', 'realname'),
            Server      => $server,
            Pacing      => 1,
            UTF8        => 1,
            SSL         => $self->{registry}->get_value('irc', 'SSL'),
            SSL_ca_file => $self->{registry}->get_value('irc', 'SSL_ca_file'),
            SSL_ca_path => $self->{registry}->get_value('irc', 'SSL_ca_path'),
            Port        => $self->{registry}->get_value('irc', 'port')
        )
      )
    {
        $self->{logger}->log("$0: Can't connect to $server:" . $self->{registry}->get_value('irc', 'port') . ". Retrying in 15 seconds...\n");
        sleep 15;
    }

    $self->{connected} = 1;

    # start timer once connected
    $self->{timer}->start;

    # set up handlers for the IRC engine
    $self->{conn}->add_default_handler(sub { $self->{irchandlers}->default_handler(@_) }, 1);
    $self->{conn}->add_handler([251, 252, 253, 254, 255, 302], sub { $self->{irchandlers}->on_init(@_) });

    # ignore these events
    $self->{conn}->add_handler(
        [
            'whoisserver',
            'whoiscountry',
            'whoischannels',
            'whoisidle',
            'motdstart',
            'endofmotd',
            'away',
        ],
        sub { }
    );
}

#main loop
sub do_one_loop {
    my $self = shift;
    $self->{irc}->do_one_loop() if $self->{connected};
    $self->{select_handler}->do_select;
}

sub start {
    my $self = shift;
    while (1) {
        $self->connect if not $self->{connected};
        $self->do_one_loop;
    }
}

sub register_signal_handlers {
    my $self = shift;
    $SIG{INT} = sub { $self->atexit; exit 0; };
}

sub atexit {
    my $self = shift;
    $self->{atexit}->execute_all;
    alarm 0;
}

sub irc_debug_trigger {
    my ($self, $section, $item, $newvalue) = @_;
    $self->{irc}->debug($newvalue);
    $self->{conn}->debug($newvalue) if $self->{connected};
}

sub change_botnick_trigger {
    my ($self, $section, $item, $newvalue) = @_;
    $self->{conn}->nick($newvalue) if $self->{connected};
}

sub cmd_list {
    my ($self, $context) = @_;
    my $text;

    my $usage = "Usage: list <modules|commands>";

    return $usage if not length $context->{arguments};

    if ($context->{arguments} =~ /^modules$/i) {
        $text = "Loaded modules: ";
        foreach my $channel (sort $self->{factoids}->{factoids}->get_keys) {
            foreach my $command (sort $self->{factoids}->{factoids}->get_keys($channel)) {
                next if $command eq '_name';
                if ($self->{factoids}->{factoids}->get_data($channel, $command, 'type') eq 'module') {
                    $text .= $self->{factoids}->{factoids}->get_data($channel, $command, '_name') . ' ';
                }
            }
        }

        return $text;
    }

    if ($context->{arguments} =~ /^commands$/i) {
        $text = "Registered commands: ";
        foreach my $command (sort { $a->{name} cmp $b->{name} } @{$self->{commands}->{handlers}}) {
            if   ($command->{requires_cap}) { $text .= "+$command->{name} "; }
            else                            { $text .= "$command->{name} "; }
        }
        return $text;
    }
    return $usage;
}

sub cmd_sl {
    my ($self, $context) = @_;
    return "Usage: sl <ircd command>" if not length $context->{arguments};
    $self->{conn}->sl($context->{arguments});
    return "/msg $context->{nick} sl: command sent. See log for result.";
}

sub cmd_die {
    my ($self, $context) = @_;
    $self->{logger}->log("$context->{hostmask} made me exit.\n");
    $self->{conn}->privmsg($context->{from}, "Good-bye.") if $context->{from} ne 'stdin@pbot';
    $self->{conn}->quit("Departure requested.") if defined $self->{conn};
    $self->atexit();
    exit 0;
}

sub cmd_export {
    my ($self, $context) = @_;
    return "Usage: export <factoids>" if not length $context->{arguments};
    if ($context->{arguments} =~ /^factoids$/i) { return $self->{factoids}->export_factoids; }
}

sub cmd_eval {
    my ($self, $context) = @_;

    $self->{logger}->log("eval: $context->{from} $context->{hostmask} evaluating `$context->{arguments}`\n");

    my $ret    = '';
    my $result = eval $context->{arguments};
    if ($@) {
        if   (length $result) { $ret .= "[Error: $@] "; }
        else                  { $ret .= "Error: $@"; }
        $ret =~ s/ at \(eval \d+\) line 1.//;
    }
    $result = 'Undefined.' if not defined $result;
    $result = 'No output.' if not length $result;
    return "/say $ret $result";
}

sub cmd_reload {
    my ($self, $context) = @_;

    my %reloadables = (
        'capabilities' => sub {
            $self->{capabilities}->{caps}->load;
            return "Capabilities reloaded.";
        },

        'commands' => sub {
            $self->{commands}->{metadata}->load;
            return "Commands metadata reloaded.";
        },

        'blacklist' => sub {
            $self->{blacklist}->clear_blacklist;
            $self->{blacklist}->load_blacklist;
            return "Blacklist reloaded.";
        },

        'ban-exemptions' => sub {
            $self->{antiflood}->{'ban-exemptions'}->load;
            return "Ban exemptions reloaded.";
        },

        'ignores' => sub {
            $self->{ignorelist}->{ignorelist}->load;
            return "Ignore list reloaded.";
        },

        'users' => sub {
            $self->{users}->load;
            return "Users reloaded.";
        },

        'channels' => sub {
            $self->{channels}->{channels}->load;
            return "Channels reloaded.";
        },

        'banlist' => sub {
            $self->{timer}->dequeue_event('unban #.*');
            $self->{timer}->dequeue_event('unmute #.*');
            $self->{banlist}->{banlist}->load;
            $self->{banlist}->{quietlist}->load;
            $self->{banlist}->enqueue_timeouts($self->{banlist}->{banlist},   'b');
            $self->{banlist}->enqueue_timeouts($self->{banlist}->{quietlist}, 'q');
            return "Ban list reloaded.";
        },

        'registry' => sub {
            $self->{registry}->load;
            return "Registry reloaded.";
        },

        'factoids' => sub {
            $self->{factoids}->load_factoids;
            return "Factoids reloaded.";
        }
    );

    if (not length $context->{arguments} or not exists $reloadables{$context->{arguments}}) {
        my $usage = 'Usage: reload <';
        $usage .= join '|', sort keys %reloadables;
        $usage .= '>';
        return $usage;
    }

    return $reloadables{$context->{arguments}}();
}

1;
