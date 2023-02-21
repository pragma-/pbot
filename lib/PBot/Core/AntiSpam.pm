# File: AntiSpam.pm
#
# Purpose: Checks if a message is spam

# SPDX-FileCopyrightText: 2018-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

package PBot::Core::AntiSpam;
use parent 'PBot::Core::Class';

use PBot::Imports;

sub initialize {
    my ($self, %conf) = @_;

    my $filename = $self->{pbot}->{registry}->get_value('general', 'data_dir') . '/spam_keywords';

    $self->{keywords} = PBot::Core::Storage::DualIndexHashObject->new(
        pbot     => $self->{pbot},
        name     => 'SpamKeywords',
        filename => $filename,
    );

    $self->{keywords}->load;

    $self->{pbot}->{registry}->add_default('text', 'antispam', 'enforce', $conf{enforce_antispam} // 1);
}

sub is_spam {
    my ($self, $namespace, $text, $all_namespaces) = @_;
    my $lc_namespace = lc $namespace;

    return 0 if not $self->{pbot}->{registry}->get_value('antispam', 'enforce');
    return 0 if $self->{pbot}->{registry}->get_value($namespace, 'dont_enforce_antispam');

    my $ret = eval {
        foreach my $space ($self->{keywords}->get_keys) {
            if ($all_namespaces or $lc_namespace eq $space) {
                foreach my $keyword ($self->{keywords}->get_keys($space)) {
                    return 1 if $text =~ m/$keyword/i;
                }
            }
        }
        return 0;
    };

    if ($@) {
        $self->{pbot}->{logger}->log("Error in is_spam: $@");
        return 0;
    }

    $self->{pbot}->{logger}->log("AntiSpam: spam detected!\n") if $ret;
    return $ret;
}

1;
