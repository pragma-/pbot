# File: UrlTitles.pm
#
# Purpose: Display titles of URLs in channel messages.

# SPDX-FileCopyrightText: 2021, 2022 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Plugin::UrlTitles;
use parent 'PBot::Plugin::Base';

use PBot::Imports;

use Encode;
use Text::Levenshtein::XS qw(distance);
use LWP::UserAgent::Paranoid;
use HTML::Entities;
use JSON::XS;

use constant {
    TIMEOUT    => 30,
    USER_AGENT => 'Mozilla/5.0 (compatible)',
    MAX_SIZE   => 1024 * 200,
};

sub initialize {
    my ($self, %conf) = @_;

    # remember recent titles so we don't repeat them too often
    my $filename = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/url-title.hist';

    $self->{history} = PBot::Core::Storage::DualIndexHashObject->new(
        pbot     => $self->{pbot},
        name     => 'URL title history',
        filename => $filename,
    );

    $self->{history}->load;

    # can be overridden per-channel
    $self->{pbot}->{registry}->add_default('text', 'general', 'show_url_titles', $conf{show_url_titles} // 1);

    # handle these events
    $self->{pbot}->{event_dispatcher}->register_handler('irc.public',  sub { $self->show_url_titles(@_) });
    $self->{pbot}->{event_dispatcher}->register_handler('irc.caction', sub { $self->show_url_titles(@_) });
}

sub unload {
    my ($self) = @_;
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.public');
    $self->{pbot}->{event_dispatcher}->remove_handler('irc.caction');
}

sub is_ignored_url {
    my ($self, $url) = @_;

    return 1 if $url =~ m{https?://matrix\.to}i;
    return 1 if $url =~ m{https?://.*\.c$}i;
    return 1 if $url =~ m{https?://.*\.h$}i;
    return 1 if $url =~ m{https?://ibb.co/}i;
    return 1 if $url =~ m{https?://.*onlinegdb.com}i;
    return 1 if $url =~ m{googlesource.com/}i;
    return 1 if $url =~ m{https?://git}i and $url !~ /commit/i and $url !~ /github.com/;
    return 1 if $url =~ m{https://.*swissborg.com}i;
    return 1 if $url =~ m{https://streamable.com}i;
    return 1 if $url =~ m{https://matrix.org}i;
    return 1 if $url =~ m{https?://coliru\..*}i;
    return 1 if $url =~ m{localhost}i;
    return 1 if $url =~ m{127}i;
    return 1 if $url =~ m{192.168}i;
    return 1 if $url =~ m{file://}i;
    return 1 if $url =~ m{\.\.}i;
    return 1 if $url =~ m{https?://www.irccloud.com/pastebin}i;
    return 1 if $url =~ m{http://smuj.ca/cl}i;
    return 1 if $url =~ m{/man\d+/}i;
    return 1 if $url =~ m{godbolt.org}i;
    return 1 if $url =~ m{man\.cgi}i;
    return 1 if $url =~ m{wandbox}i;
    return 1 if $url =~ m{ebay.com/itm}i;
    return 1 if $url =~ m/prntscr.com/i;
    return 1 if $url =~ m/imgbin.org/i;
    return 1 if $url =~ m/jsfiddle.net/i;
    return 1 if $url =~ m/port70.net/i;
    return 1 if $url =~ m/notabug.org/i;
    return 1 if $url =~ m/flickr.com/i;
    return 1 if $url =~ m{www.open-std.org/jtc1/sc22/wg14/www/docs/dr}i;
    return 1 if $url =~ m/cheezburger/i;
    return 1 if $url =~ m/rafb.me/i;
    return 1 if $url =~ m/rextester.com/i;
    return 1 if $url =~ m/explosm.net/i;
    return 1 if $url =~ m/stackoverflow.com/i;
    return 1 if $url =~ m/scratch.mit.edu/i;
    return 1 if $url =~ m/c-faq.com/i;
    return 1 if $url =~ m/imgur.com/i;
    return 1 if $url =~ m/sprunge.us/i;
    return 1 if $url =~ m/pastebin.ws/i;
    return 1 if $url =~ m/hastebin.com/i;
    return 1 if $url =~ m/lmgtfy.com/i;
    return 1 if $url =~ m/gyazo/i;
    return 1 if $url =~ m/imagebin/i;
    return 1 if $url =~ m/\/wiki\//i;
    return 1 if $url =~ m!github.com/.*/tree/.*/source/.*!i;
    return 1 if $url =~ m!github.com/.*/commits/.*!i;
    return 1 if $url =~ m!/blob/!i;
    return 1 if $url =~ m/wiki.osdev.org/i;
    return 1 if $url =~ m/wikipedia.org/i;
    return 1 if $url =~ m/fukung.net/i;
    return 1 if $url =~ m/\/paste\//i;
    return 1 if $url =~ m/paste\./i;
    return 1 if $url =~ m/pastie/i;
    return 1 if $url =~ m/ideone.com/i;
    return 1 if $url =~ m/codepad.org/i;
    return 1 if $url =~ m/^http\:\/\/past(e|ing)\./i;
    return 1 if $url =~ m/past(?:e|ing).*\.(?:com|org|net|ch|ca|de|uk|info)/i;

    # not ignored
    return 0;
}

sub is_ignored_title {
    my ($self, $title) = @_;

    return 1 if $title =~ m{^Loading}i;
    return 1 if $title =~ m{streamable}i;
    return 1 if $title =~ m{^IBM Knowledge Center$}i;
    return 1 if $title =~ m{Freenode head of infrastructure}i;
    return 1 if $title =~ m/^Coliru Viewer$/i;
    return 1 if $title =~ m/^Gerrit Code Review$/i;
    return 1 if $title =~ m/^Public Git Hosting -/i;
    return 1 if $title =~ m/git\/blob/i;
    return 1 if $title =~ m/\sdiff\s/i;
    return 1 if $title =~ m/- Google Search$/;
    return 1 if $title =~ m/linux cross reference/i;
    return 1 if $title =~ m/screenshot/i;
    return 1 if $title =~ m/pastebin/i;
    return 1 if $title =~ m/past[ea]/i;
    return 1 if $title =~ m/^[0-9_-]+$/;
    return 1 if $title =~ m/^Index of \S+$/;
    return 1 if $title =~ m/(?:sign up|login)/i;

    # not ignored
    return  0;
}

sub get_title {
    my ($self, $context) = @_;

    my $url = $context->{arguments};

    my $ua = LWP::UserAgent::Paranoid->new(request_timeout => TIMEOUT);

    $ua->agent(USER_AGENT);
    $ua->max_size(MAX_SIZE);

    my $response = $ua->get($url);

    if (not $response->is_success) {
        $self->{pbot}->{logger}->log("Error getting URL [$url]\n");
        return 0;
    }

    my $title;

    if ($response->title) {
        $title = decode('UTF-8', $response->title);
    } else {
        my $text = $response->decoded_content;

        if ($text =~ m/<title>(.*?)<\/title>/msi) {
            $title = $1;
        }
    }

    if (not defined $title or not length $title) {
        $self->{pbot}->{logger}->log("No title for URL [$url]\n");
        return 0;
    }

    $title = decode_entities($title);

    # disregard one-word titles; these aren't usually interesting
    # (and are usually already present in the URL itself)
    return 0 if $title !~ /\s/;

    # truncate long title
    if (length $title > 400) {
        $title = substr($title, 0, 400);
        $title = "$title [...]";
    }

    # fuzzy compare file against title
    my ($file) = $url =~ m/.*\/(.*)$/;
    $file =~ s/[_-]+/ /g;

    my $distance = distance(lc $file, lc $title);
    my $length   = (length $file > length $title) ? length $file : length $title;

    # disregard title if 75%+ similiar to file
    return 0 if $distance / $length < 0.75;

    # disregard ignored titles
    return 0 if $self->is_ignored_title($title);

    # send result back to parent
    $context->{result} = $title;
    $context->{url}    = $url;
}

sub title_pipe_reader {
    my ($self, $pid, $buf) = @_;

    # retrieve context object from child
    my $context = decode_json $buf or do {
        $self->{pbot}->{logger}->log("Failed to decode bad json: [$buf]\n");
        return;
    };

    # context is no longer forked
    delete $context->{pid};

    my $title = delete $context->{result};

    return 0 if not defined $title or not length $title;

    # disregard recent titles (15 min)
    my $data = $self->{history}->get_data($context->{from}, $title);

    if (defined $data) {
        if (time - $data->{timestamp} < 900) {
            return 0;
        }
    }

    # update history
    $data = {
        url       => $context->{url},
        timestamp => time,
        hostmask  => $context->{hostmask},
    };

    $self->{history}->add($context->{from}, $title, $data, 0, 1);

    # set result
    $context->{result} = "Title of $context->{nick}'s link: $title";

    # send result off to bot to be handled
    $context->{checkflood} = 1;
    $self->{pbot}->{interpreter}->handle_result($context);
}

sub show_url_titles {
    my ($self, $event_type, $event) = @_;

    my ($nick, $user, $host) = (
        $event->{event}->nick,
        $event->{event}->user,
        $event->{event}->host
    );

    my ($channel, $msg) = (
        $event->{event}->{to}[0],
        $event->{event}->{args}[0]
    );

    # get show_url_titles for channel or true if not defined
    my $enabled = $self->{pbot}->{registry}->get_value($channel, 'show_url_titles') // 1;

    # disabled in channel
    return 0 if !$enabled;
    return 0 if $self->{pbot}->{registry}->get_value($channel, 'no_url_titles');

    # disabled globally (unless allowed by channel)
    return 0 if !$self->{pbot}->{registry}->get_value('general', 'show_url_titles') && !$enabled;

    # message already handled by bot command
    return 0 if $event->{interpreted};

    # no url in message
    return 0 if not $msg =~ m/https?:\/\/[^\s]/;

    # ignored user
    return 0 if $self->{pbot}->{ignorelist}->is_ignored($channel, "$nick!$user\@$host");

    # no titles for unidentified users in +z channels
    my $chanmodes = $self->{pbot}->{channels}->get_meta($channel, 'MODE');

    if (defined $chanmodes and $chanmodes =~ m/z/) {
        my $account  = $self->{pbot}->{messagehistory}->{database}->get_message_account($nick, $user, $host);
        my $nickserv = $self->{pbot}->{messagehistory}->{database}->get_current_nickserv_account($account);
        return 0 if not defined $nickserv or not length $nickserv;
    }

    my $count = 0;

    while ($msg =~ s/(https?:\/\/[^\s]+)//i && ++$count <= 3) {
        my $url = $1;

        $url =~ s/\W$//;
        $url =~ s,https://mobile.twitter.com,https://twitter.com,i;

        if ($self->{pbot}->{antispam}->is_spam('url', $url)) {
            $self->{pbot}->{logger}->log("Ignoring spam URL $url\n");
            next;
        }

        if ($self->is_ignored_url($url)) {
            $self->{pbot}->{logger}->log("Ignoring URL $url\n");
            next;
        }

        my $context = {
            from               => $channel,
            nick               => $nick,
            user               => $user,
            host               => $host,
            hostmask           => "$nick!$user\@$host",
            command            => "title $nick $url",
            root_channel       => $channel,
            root_keyword       => "title",
            keyword            => "title",
            arguments          => $url,
            suppress_no_output => 1,
        };

        $self->{pbot}->{process_manager}->execute_process(
            $context,
            sub { $self->get_title(@_) },
            30,
            sub { $self->title_pipe_reader(@_) },
        );
    }

    return 0;
}

1;
