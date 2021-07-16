# File: cpanfile
#
# Purpose: Selects and installs PBot dependencies.
#
# Install a minimum bare-bones PBot (no Plugins or modules):
#
#   cpanm -n --installdeps .
#
# Install a fully featured PBot (without Windows compiler-vm support):
#
#   cpanm -n --installdeps . --with-all-features --without-feature compiler_vm_win32

requires 'perl' => '5.010001';

# PBot core

requires 'Cache::FileCache';
requires 'Carp';
requires 'DateTime';
requires 'DateTime::Format::Duration';
requires 'DateTime::Format::Flexible';
requires 'DBD::SQLite';
requires 'DBI';
requires 'Devel::StackTrace';
requires 'Data::Dumper';
requires 'Encode';
requires 'File::Basename';
requires 'File::Copy';
requires 'File::HomeDir';
requires 'File::Spec';
requires 'Getopt::Long';
requires 'HTML::Entities';
requires 'IO::File';
requires 'IO::Select';
requires 'IO::Socket';
requires 'IO::Socket::INET';
requires 'IO::Socket::SSL';
requires 'IPC::Run';
requires 'JSON';
requires 'LWP::Protocol::https';
requires 'LWP::UserAgent';
requires 'LWP::UserAgent::Paranoid';
requires 'MIME::Base64';
requires 'Module::Refresh';
requires 'POSIX';
requires 'Scalar::Util';
requires 'Socket';
requires 'Storable';
requires 'Symbol';
requires 'Text::CSV';
requires 'Text::Levenshtein';
requires 'Text::ParseWords';
requires 'Time::Duration';
requires 'Time::HiRes';
requires 'Unicode::Truncate';
requires 're::engine::RE2';

# Plugins

feature ActionTrigger => sub {
    requires 'DBI';
    requires 'Time::Duration';
    requires 'Time::HiRes';
};

feature Plang => sub {
    requires 'Data::Dumper';
    requires 'Text::ParseWords';
    requires 'FindBin';
};

feature AntiAway => sub {
};

feature AntiKickAutoRejoin => sub {
    requires 'Time::HiRes';
    requires 'Time::Duration';
};

feature AntiNickSpam => sub {
    requires 'Time::Duration';
    requires 'Time::HiRes';
};

feature AntiRepeat => sub {
    requires 'String::LCSS';
    requires 'Time::HiRes';
    requires 'POSIX';
};

feature AntiTwitter => sub {
    requires 'Time::HiRes';
    requires 'Time::Duration';
};

feature AutoRejoin => sub {
    requires 'Time::HiRes';
    requires 'Time::Duration';
};

feature Battleship => sub {
    requires 'Time::Duration';
    requires 'Data::Dumper';
};

feature Connect4 => sub {
    requires 'Time::Duration';
    requires 'Data::Dumper';
    requires 'List::Util';
};

feature Counter => sub {
    requires 'DBI';
    requires 'Time::Duration';
    requires 'Time::HiRes';
};

feature Date => sub {
    requires 'Getopt::Long';
};

feature Example => sub {
};

feature FuncBuiltins => sub {
    requires 'URI::Escape';
};

feature FuncGrep => sub {
};

feature FuncPlural => sub {
};

feature FuncSed => sub {
};

feature GoogleSearch => sub {
    requires 'WWW::Google::CustomSearch';
    requires 'HTML::Entities';
};

feature ParseDate => sub {
    requires 'Time::Duration';
};

feature Plang => sub {
    requires 'Getopt::Long';
};

feature Quotegrabs => sub {
    requires 'HTML::Entities';
    requires 'Time::Duration';
    requires 'Time::HiRes';
    requires 'Getopt::Long';
    requires 'POSIX';
    requires 'DBI';
    requires 'Carp';
};

feature RelayUnreg => sub {
    requires 'Time::HiRes';
};

feature RemindMe => sub {
    requires 'DBI';
    requires 'Time::Duration';
    requires 'Time::HiRes';
    requires 'Getopt::Long';
};

feature RestrictedMod => sub {
    requires 'Storable';
};

feature Spinach => sub {
    requires 'JSON';
    requires 'Lingua::EN::Fractions';
    requires 'Lingua::EN::Numbers';
    requires 'Lingua::EN::Numbers::Years';
    requires 'Lingua::Stem';
    requires 'Lingua::EN::ABC';
    requires 'Time::Duration';
    requires 'Text::Unidecode';
    requires 'Encode';
    requires 'Data::Dumper';
    requires 'DBI';
    requires 'Carp';
    requires 'FindBin';
    requires 'Math::Expression::Evaluator';
};

feature TypoSub => sub {
};

feature UrlTitles => sub {
};

feature Weather => sub {
    requires 'XML::LibXML';
    requires 'Getopt::Long';
};

feature Wolfram => sub {
    requires 'LWP::UserAgent::Paranoid';
    requires 'URI::Escape';
};

feature Wttr => sub {
    requires 'JSON';
    requires 'URI::Escape';
    requires 'Getopt::Long';
};

# modules

feature ago => sub {
    requires 'Time::Duration';
};

feature bashfaq => sub {
};

feature bashpf => sub {
};

feature c11std => sub {
};

feature c2english => sub {
    requires 'Text::Balanced';
    requires 'Parse::RecDescent';
    requires 'Getopt::Std';
    requires 'Data::Dumper';
};

feature c99std => sub {
};

feature cdecl => sub {
};

feature cjeopardy => sub {
    requires 'Exporter';
    requires 'DBI';
    requires 'Carp';
    requires 'Time::HiRes';
    requires 'Time::Duration';
    requires 'Fcntl';
    requires 'Text::Levenshtein';
    requires 'POSIX';
};

feature codepad => sub {
    requires 'LWP::UserAgent';
    requires 'URI::Escape';
    requires 'HTML::Entities';
    requires 'HTML::Parse';
    requires 'HTML::FormatText';
    requires 'IPC::Open2';
    requires 'Text::Balanced';
};

feature compiler_block => sub {
    requires 'IO::Socket::INET';
    requires 'JSON';
};

feature compiler_client => sub {
    requires 'IO::Socket';
    requires 'JSON';
};

feature compiler_vm => sub {
    requires 'HTML::Entities';
    requires 'IO::Socket';
    requires 'JSON';
    requires 'Net::hostent';
    requires 'IPC::Run';
    requires 'IPC::Open2';
    requires 'IPC::Shareable';
    requires 'Text::Balanced';
    requires 'Time::HiRes';
    requires 'File::Basename';
    requires 'English';
    requires 'LWP::UserAgent';
    requires 'Getopt::Long';
    requires 'Encode';
    requires 'Data::Dumper';
};

feature compiler_vm_win32 => sub {
    requires 'IO::Socket';
    requires 'Net::hostent';
    requires 'Win32::MMF';
    requires 'Win32::MMF::Shareable';
};

feature define => sub {
    requires 'LWP::Simple';
};

feature dice_roll => sub {
    requires 'Games::Dice';
};

feature dict => sub {
    requires 'Net::Dict';
    requires 'AppConfig::Std';
};

feature expand_macros => sub {
    requires 'IPC::Open2';
    requires 'Text::Balanced';
    requires 'IO::Socket';
    requires 'LWP::UserAgent';
};

feature fnord => sub {
};

feature funnyish_quote => sub {
    requires 'LWP::UserAgent';
};

feature gdefine => sub {
    requires 'LWP::UserAgent';
};

feature gen_cfacts => sub {
    requires 'HTML::Entities';
};

feature gencstd => sub {
    requires 'HTML::Entities';
    requires 'Data::Dumper';
};

feature get_title => sub {
    requires 'LWP::UserAgent';
    requires 'HTML::Entities';
    requires 'Text::Levenshtein';
    requires 'Time::HiRes';
};

feature getcfact => sub {
};

feature headlines => sub {
    requires 'XML::RSS';
    requires 'LWP::Simple';
};

feature insult => sub {
    requires 'LWP::Simple';
};

feature lookupbot => sub {
    requires 'LWP::Simple';
    requires 'LWP::UserAgent';
    requires 'Encode';
    requires 'CGI';
    requires 'HTML::Entities';
};

feature love_quote => sub {
    requires 'LWP::UserAgent::WithCache';
};

feature man => sub {
    requires 'LWP::Simple';
};

feature map => sub {
    requires 'LWP::Simple';
};

feature math => sub {
    requires 'Math::Units';
};

feature nickometer => sub {
    requires 'Getopt::Std';
    requires 'Math::Trig';
};

feature prototype => sub {
    requires 'LWP::Simple';
};

feature qalc => sub {
};

feature random_quote => sub {
    requires 'LWP::UserAgent::WithCache';
};

feature rpn => sub {
    requires 'List::Util';
};

feature trans => sub {
};

feature urban => sub {
    requires 'WebService::UrbanDictionary';
    requires 'Getopt::Long';
}

feature wikipedia => sub {
    requires 'WWW::Wikipedia';
    requires 'HTML::Parse';
    requires 'HTML::FormatText';
};

feature wiktionary => sub {
    requires 'Cache::FileCache';
    requires 'Encode';
    requires 'Getopt::Long';
    requires 'JSON';
};
