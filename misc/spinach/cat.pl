#!/usr/bin/perl

use strict;
use warnings;

use Lingua::Stem;

my %docs;
my @uncat;

my $minimum_category_size = 6;

open my $handle, '<dedup_questions' or die $!;
chomp(my @lines = <$handle>); close $handle;

my @uncategorized_rules = (
  { regex => qr/(?:james bond| 007)/i, category => 'JAMES BOND' },
  { regex => qr/192\d.?s/i, category => "THE 1920'S" },
  { regex => qr/193\d.?s/i, category => "THE 1930'S" },
  { regex => qr/194\d.?s/i, category => "THE 1940'S" },
  { regex => qr/195\d.?s/i, category => "THE 1950'S" },
  { regex => qr/196\d.?s/i, category => "THE 1960'S" },
  { regex => qr/197\d.?s/i, category => "THE 1970'S" },
  { regex => qr/198\d.?s/i, category => "THE 1980'S" },
  { regex => qr/199\d.?s/i, category => "THE 1990'S" },
  { regex => qr/^(?:in (?:the year )?)?192\d\p{PosixPunct}?/i, category => "THE 1920'S" },
  { regex => qr/^(?:in (?:the year )?)?193\d\p{PosixPunct}?/i, category => "THE 1930'S" },
  { regex => qr/^(?:in (?:the year )?)?194\d\p{PosixPunct}?/i, category => "THE 1940'S" },
  { regex => qr/^(?:in (?:the year )?)?195\d\p{PosixPunct}?/i, category => "THE 1950'S" },
  { regex => qr/^(?:in (?:the year )?)?196\d\p{PosixPunct}?/i, category => "THE 1960'S" },
  { regex => qr/^(?:in (?:the year )?)?197\d\p{PosixPunct}?/i, category => "THE 1970'S" },
  { regex => qr/^(?:in (?:the year )?)?198\d\p{PosixPunct}?/i, category => "THE 1980'S" },
  { regex => qr/^(?:in (?:the year )?)?199\d\p{PosixPunct}?/i, category => "THE 1990'S" },
  { regex => qr/^(?:in (?:the year )?)?20\d\d\p{PosixPunct}?/i, category => "THE 2000'S" },
  { regex => qr/(?:Name The Year|In what year)/i, category => 'NAME THE YEAR' },
  { regex => qr/baby names/i, category => 'BABY NAMES' },
  { regex => qr/southpark/i, category => "SOUTHPARK" },
  { regex => qr/what word mean/i, category => 'DEFINITIONS' },
  { regex => qr/gone with the wind/i, category => "GONE WITH THE WIND" },
  { regex => qr/harry potter/i, category => "HARRY POTTER" },
  { regex => qr/What word links/i, category => 'WHAT WORD LINKS THESE WORDS' },
  { regex => qr/What one word/i, category => 'GUESS THE WORD' },
  { regex => qr/^(If [Yy]ou [Ww]ere [Bb]orn|Astrology)/i, category => 'Astrology' },
  { regex => qr/[Oo]lympics/i, category => 'Olympics' },
  { regex => qr/^How many/i, category => 'HOW MANY' },
  { regex => qr/(?:^What is a group|Group Nouns)/i, category => 'animal groups' },
  { regex => qr/(?:[Ww]hat is the fear|phobia is (?:a|the) fear|Phobias)/i, category => 'Phobias' },
  { regex => qr/who won the oscar/i, category => 'Oscars' },
  { regex => qr/(?:area code|country code)/i, category => 'Phone COUNTRY Codes' },
  { regex => qr/17th.century/i, category => "17TH CENTURY" },
  { regex => qr/18th.century/i, category => "18TH CENTURY" },
  { regex => qr/19th.century/i, category => "19TH CENTURY" },
  { regex => qr/shakespear/i, category => "SHAKESPEARE" },
  { regex => qr/world.cup/i, category => "WORLD CUP" },
  { regex => qr/card game/i, category => "CARD GAMES" },
  { regex => qr/board game/i, category => "BOARD GAMES" },
  { regex => qr/computer science/i, category => "COMPUTER SCIENCE" },
  { regex => qr/computer game/i, category => "COMPUTER GAMES" },
  { regex => qr/computer/i, category => "COMPUTERS" },
  { regex => qr/science fict/i, category => "SCI-FI" },
  { regex => qr/science/i, category => "SCIENCE" },
  { regex => qr/technolog/i, category => "TECHNOLOGY" },
  { regex => qr/^games /i, category => "GAMES" },
  { regex => qr/x.?men/i, category => "X-MEN" },
  { regex => qr/beatles/i, category => "BEATLES" },
  { regex => qr/^chiefly british/i, category => "BRITISH SLANG" },
  { regex => qr/^SLANG /i, category => "SLANG" },
  { regex => qr/^US SLANG$/i, category => "SLANG" },
  { regex => qr/\bchess\b/i, category => "CHESS" },
  { regex => qr/sherlock holmes/i, category => "SHERLOCK HOLMES" },
  { regex => qr/stephen king/i, category => "STEPHEN KING" },
  { regex => qr/wizard of oz/i, category => "WIZARD OF OZ" },
  { regex => qr/philosoph/i, category => "PHILOSOPHY" },
  { regex => qr/.*: '.*\.'/i, category => "GUESS THE WORD" },
  { regex => qr/monty python/i, category => "MONTY PYTHON" },
  { regex => qr/^the name/i, category => "NAME THAT THING" },
  { regex => qr/hit single/i, category => "HIT SINGLES" },
  { regex => qr/^a group of/i, category => "A GROUP OF IS CALLED" },
  { regex => qr/^music/i, category => "MUSIC" },
  { regex => qr/(?:canada|canadian)/i, category => "CANADA" },
  { regex => qr/who (is|was) the author/i, category => "NAME THE AUTHOR" },
  { regex => qr/dinosaur/i, category => "DINOSAURS" },
  { regex => qr/who.?s the author/i, category => "NAME THE AUTHOR" },
  { regex => qr/which.*author wrote/i, category => "NAME THE AUTHOR" },
  { regex => qr/\bmusic\b/i, category => "MUSIC" },
  { regex => qr/\bauthor\b/i, category => "AUTHORS" },
  { regex => qr/greek alphabet/i, category => "GREEK ALPHABET" },
  { regex => qr/bitish slang/i, category => "BRITISH SLANG" },
  { regex => qr/australian slang/i, category => "AUSSIE SLANG" },
  { regex => qr/constellation/i, category => "CONSTELLATIONS" },
  { regex => qr/aussie slang/i, category => "AUSSIE SLANG" },
  { regex => qr/slang term/i, category => "SLANG" },
  { regex => qr/\bslang\b/i, category => "SLANG" },
  { regex => qr/theme songi/i, category => "THEME SONGS" },
  { regex => qr/christian name/i, category => "FIRST NAMES" },
  { regex => qr/^who directed /i, category => "NAME THE DIRECTOR" },
  { regex => qr/mathemat/i, category => "MATHEMATICS" },
  { regex => qr/autobiograp/i, category => "AUTOBIOGRAPHIES" },
  { regex => qr/biograph/i, category => "BIOGRAPHIES" },
  { regex => qr/^who recorded/i, category => "NAME THE ARTIST" },
  { regex => qr/^who painted/i, category => "NAME THE PAINTER" },
  { regex => qr/^who play(?:s|ed) for/i, category => "NAME THE PLAYER" },
  { regex => qr/^who play/i, category => "NAME THE ACTOR" },
  { regex => qr/patron saint/i, category => "PATRON SAINTS" },
  { regex => qr/^who founded/i, category => "NAME THE FOUNDER" },
  { regex => qr/^who discovered/i, category => "DISCOVERIES" },
  { regex => qr/^who created/i, category => "NAME THE CREATOR" },
  { regex => qr/^who composed/i, category => "NAME THE COMPOSER" },
  { regex => qr/(?:which|what) planet/i, category => "PLANETS" },
  { regex => qr/opera/i, category => "OPERA" },
  { regex => qr/who wrote the book/i, category => "NAME THE AUTHOR" },
  { regex => qr/(?:chemistry|chemical)/i, category => "CHEMISTRY" },
  { regex => qr/(?:darth vader|chewbacca|luke skywalker|han solo|jabba the hut)/i, category => "STAR WARS" },
  { regex => qr/(?:US|U S) president/i, category => "US PRESIDENTS" },
  { regex => qr/united states president/i, category => "US PRESIDENTS" },
  { regex => qr/(?:US| U S) (?:state|city|capiti?al)/i, category => "UNITED STATES" },
  { regex => qr/authority/i, category => "AUTHORITY" },
  { regex => qr/musical instrum/, category => "MUSICAL INSTRUMENTS" },
  { regex => qr/musical term/, category => "MUSICAL TERMS" },
  { regex => qr/musical/i, category => "MUSICALS" },
);

my @remaining_uncat_rules = (
  { regex => qr/^who wrote/i, category => "WHO WROTE" },
  { regex => qr/^who won/i, category => "WHO WON" },
  { regex => qr/^who was/i, category => "WHO WAS" },
);

my @rename_rules = (
  { old => qr/MUSIC TERM/, new => "MUSIC TERMS" },
  { old => qr/^007$/,  new => "JAMES BOND" },
  { old => qr/^191\d/, new => "THE 1910'S" },
  { old => qr/^192\d/, new => "THE 1920'S" },
  { old => qr/^ARCHAIC$/, new => "ARCHAIC DEFINITIONS" },
  { old => qr/^INFORMAL$/, new => "INFORMAL DEFINITIONS" },
  { old => qr/^193\d/, new => "THE 1930'S" },
  { old => qr/^194\d/, new => "THE 1940'S" },
  { old => qr/^195\d/, new => "THE 1950'S" },
  { old => qr/^196\d/, new => "THE 1960'S" },
  { old => qr/^197\d/, new => "THE 1970'S" },
  { old => qr/^198\d/, new => "THE 1980'S" },
  { old => qr/^199\d/, new => "THE 1990'S" },
  { old => qr/^200\d/, new => "THE 2000'S" },
  { old => qr/NEWS 2002/, new => "THE 2000'S" },
  { old => qr/19TH CENT ART/, new => "19TH CENTURY" },
  { old => qr/^20'S$/, new => "THE 1920'S" },
  { old => qr/^30'S$/, new => "THE 1930'S" },
  { old => qr/^40'S$/, new => "THE 1940'S" },
  { old => qr/^50'S$/, new => "THE 1950'S" },
  { old => qr/^60'S$/, new => "THE 1960'S" },
  { old => qr/^70'S$/, new => "THE 1970'S" },
  { old => qr/^80'S$/, new => "THE 1980'S" },
  { old => qr/^THE 50'S$/, new => "THE 1950'S" },
  { old => qr/^THE 60'S$/, new => "THE 1960'S" },
  { old => qr/^THE 70'S$/, new => "THE 1970'S" },
  { old => qr/^THE 80'S$/, new => "THE 1980'S" },
  { old => qr/^80'S TRIVIA$/, new => "THE 1980'S" },
  { old => qr/^90'S$/, new => "THE 1990'S" },
  { old => qr/(?:MOVIES|FILM) \/ TV/, new => "TV / MOVIES"},
  { old => qr/TV-MOVIES/, new => "TV / MOVIES"},
  { old => qr/MOVIE TRIVIA/, new => "MOVIES" },
  { old => qr/AT THE MOVIES/, new => "MOVIES" },
  { old => qr/AUTHORS OF 1992/, new => "AUTHORS" },
  { old => qr/^\d+ MOVIES/, new => "MOVIES" },
  { old => qr/^1993 THE YEAR/, new => "THE 1990'S" },
  { old => qr/TV \/ MOVIE/, new => "TV / MOVIES" },
  { old => qr/^TV (?:SITCOM|TRIVIA|SHOWS|HOSTS)/, new => "TV" },
  { old => qr/^TV:/, new => "TV" },
  { old => qr/TVS STTNG/, new => "STAR TREK" },
  { old => qr/ACRONYM/, new => "ACRONYM SOUP" },
  { old => qr/ANIMAL TRIVIA/, new => "ANIMAL KINGDOM" },
  { old => qr/^ANIA?MALS$/, new => "ANIMAL KINGDOM" },
  { old => qr/^ADS$/, new => "ADVERTISING" },
  { old => qr/^AD JINGLES$/, new => "ADVERTISING" },
  { old => qr/^AD SLOGANS$/, new => "ADVERTISING" },
  { old => qr/SLOGAN/, new => "ADVERTISING" },
  { old => qr/^TELEVISION$/, new => "TV" },
  { old => qr/^QUICK QUICK$/, new => "QUICK! QUICK!" },
  { old => qr/^QUOTES$/, new => "QUOTATIONS" },
  { old => qr/^SHAKESPEAREAN CHARACTER$/, new => "SHAKESPEARE" },
  { old => qr/^USELESS INFO$/, new => "USELESS FACTS" },
  { old => qr/^WORLD CUP 2002$/, new => "WORLD CUP" },
  { old => qr/^AUTHOR$/, new => "AUTHORS" },
  { old => qr/^ART$/, new => "ARTS" },
  { old => qr/^BOOZE/, new => "BOOZE" },
  { old => qr/CHIEFLY BRITISH/, new => "BRITISH SLANG" },
  { old => qr/^SCIFI/, new => "SCI-FI" },
  { old => qr/^HITCHHIKER/, new => "HITCHHIKER'S GUIDE" },
  { old => qr/^SCIENCE FANTASY/, new => "SCI-FI" },
  { old => qr/^ANATOMY$/, new => "ANATOMY & MEDICAL" },
  { old => qr/^SECRETIONS$/, new => "ANATOMY & MEDICAL" },
  { old => qr/^PHYSIOLOGY$/, new => "ANATOMY & MEDICAL" },
  { old => qr/^THE BODY$/, new => "ANATOMY & MEDICAL" },
  { old => qr/^MUSIC LEGENDS$/, new => "MUSIC ARTISTS" },
  { old => qr/^WORLD$/, new => "THE WORLD" },
  { old => qr/^TOYS GAMES$/, new => "TOYS & GAMES" },
  { old => qr/^PEANUTS COMICS$/, new => "COMICS" },
  { old => qr/^THESE LETTERS DEFINE WHAT/, new => "ACRONYMS" },
#  { old => qr/^COMPUTER GAMES$/, new => "VIDEO GAMES" },
  { old => qr/^ARTIST$/, new => "ARTISTS" },
  { old => qr/^THIS IS POPRB$/, new => "POPRB" },
  { old => qr/^US CAPTIALS$/, new => "US CAPITALS" },
  { old => qr/^MOVIE THAT FEATURES/, new => "MOVIE THAT FEATURES..." },
  { old => qr/^ABBR$/, new => "ABBREVIATIONS" },
  { old => qr/^BABY NAMES BEG/, new => "BABY NAMES" },
  { old => qr/^CURRENCY & FLAGS$/, new => "CURRENCIES & FLAGS" },
  { old => qr/^CURRENCIES$/, new => "CURRENCIES & FLAGS" },
  { old => qr/^FUN$/, new => "FUN & GAMES" }, 
  { old => qr/^GAMES$/, new => "FUN & GAMES" }, 
  { old => qr/^HOBBIES & LEISURE$/, new => "FUN & GAMES" },
  { old => qr/^MISC GAMES$/, new => "FUN & GAMES" },
  { old => qr/^SIMPSONS$/, new => "THE SIMPSONS" },
  { old => qr/^SMURFS$/, new => "THE SMURFS" },
  { old => qr/^MLB$/, new => "BASEBALL" },
  { old => qr/ENTERTAINMENT/, new => "ENTERTAINMENT" },
  { old => qr/CONFUSCIOUS SAY/, new => "CONFUCIUS SAY" },
  { old => qr/NOVELTY SONGS/, new => "NOVELTY SONGS" },
  { old => qr/NAME THE MOVIE WITH THE SONG/, new => "NAME THE MOVIE FROM THE SONG" },
  { old => qr/SCI.?FI AUTHORS/, new => "SCI-FI" },
  { old => qr/SCI.?FI/, new => "SCI-FI" },
  { old => qr/ON THIS DAY IN JANUARY/, new => "ON THIS DAY IN JANUARY" },
  { old => qr/MYTHOLOGY/, new => "MYTHOLOGY" },
  { old => qr/X-MEN/, new => "X-MEN" },
  { old => qr/US CAPITIALS/, new => "US CAPITALS" },
  { old => qr/^SCI$/, new => "SCI-FI" },
  { old => qr/SCIENCE.?FICTION/, new => "SCI-FI" },
  { old => qr/WHO RULED ROME/, new => "ROMAN RULERS" },
  { old => qr/^WHO DIRECTED/, new => "NAME THE DIRECTOR" },
  { old => qr/PHILOSOPHER/, new => "PHILOSOPHY" },
  { old => qr/^SIMILI?ES?/, new => "SIMILES" },
  { old => qr/^SCIENCE /, new => "SCIENCE" },
  { old => qr/^ROMEO & JULIET/, new => "SHAKESPEARE" },
  { old => qr/^SAYINGS & SMILES$/, new => "SAYINGS & SIMILES" },
  { old => qr/^SAYING$/, new => "SAYINGS & SIMILES" },
  { old => qr/^EPL$/, new => "SOCCER" },
  { old => qr/^NZ$/, new => "NEW ZEALAND" },
  { old => qr/^NZ /, new => "NEW ZEALAND" },
  { old => qr/[NB]URSERY RHYME/, new => "FAIRYTALES & NURSERY RHYMES" }, 
  { old => qr/NURESRY RHYME/, new => "FAIRYTALES & NURSERY RHYMES" }, 
  { old => qr/^GEOGRAPH/, new => "GEOGRAPHY" },
  { old => qr/TREKKIE/, new => "STAR TREK" },
  { old => qr/^STAR TREK/, new => "STAR TREK" },
  { old => qr/^SPORT(?!S)/, new => "SPORTS" },
  { old => qr/WORDS CONTAINING/, new => "GUESS THE WORD" },
  { old => qr/MONTY PYTHON/, new => "MONTY PYTHON" },
  { old => qr/BARBIE/, new => "BARBIE DOLL" },
  { old => qr/(?:AMERICAN|INTL) BEER/, new => "BEER" },
  { old => qr/80'S TUNE/, new => "80'S SONGS" },
  { old => qr/^UK FOOTY$/, new => "UK FOOTBALL CLUBS" },
  { old => qr/^MISCELLANEOUS$/, new => "MISC" },
  { old => qr/CRAP JOKES/, new => "CRAPPY JOKES" },
  { old => qr/IF YOU WERE BORN ON/, new => "BIRTHS" },
  { old => qr/^ACADAMY AWARDS$/, new => "ACADEMY AWARDS" },
);

my @skip_rules = (
  qr/true or false/i,
  qr/^Definitions: What word means:/,
  qr/Word Scramble/,
  qr/Unscramble this word/,
);

my @not_a_category = (
  qr/CHIEFLY BRITISH/,
  qr/^SLANG \w+/,
  qr/^IN 1987 18/,
  qr/^WHO CO$/,
);

my %refilter_rules = (
  "SPORTS" => [
    { regex => qr/baseball/i, category => "BASEBALL" },
    { regex => qr/world series/i, category => "BASEBALL" },
    { regex => qr/super.?bowl/i, category => "FOOTBALL" },
    { regex => qr/\bN\.?B\.?A\.?\b/i, category => "BASKETBALL" },
    { regex => qr/\bN\.?F\.?L\.?\b/i, category => "FOOTBALL" },
    { regex => qr/\bN\.?H\.?L\.?\b/i, category => "HOCKEY" },
    { regex => qr/basketball/i, category => "BASKETBALL" },
    { regex => qr/cricket/i, category => "CRICKET" },
    { regex => qr/golf/i, category => "GOLF" },
    { regex => qr/hockey/i, category => "HOCKEY" },
    { regex => qr/association football/, category => "SOCCER" },
    { regex => qr/soccer/, category => "SOCCER" },
    { regex => qr/football/i, category => "FOOTBALL" },
    { regex => qr/bowling/i, category => "BOWLING" },
    { regex => qr/olympics/i, category => "OLYMPICS" },
    { regex => qr/tennis/i, category => "TENNIS" },
    { regex => qr/box(?:ing|er)/i, category => "BOXING" },
    { regex => qr/swim/i, category => "SWIMMING" },
    { regex => qr/wimbledon/i, category => "TENNIS" },
    { regex => qr/rugby/i, category => "RUGBY" },
    { regex => qr/location of the summer olympic/, category => "OLYMPICS LOCATIONS" },
    { regex => qr/olympics/, category => "OLYMPICS" },
    { regex => qr/card game/i, category => "CARD GAMES" },
    { regex => qr/board game/i, category => "BOARD GAMES" },
  ],
  "ART & LITERATURE" => [
    { regex => qr/Lotr:/, category => "LORD OF THE RINGS" },
    { regex => qr/shakespear/i, category => "SHAKESPEARE" },
    { regex => qr/sherlock holmes/i, category => "SHERLOCK HOLMES" },
    { regex => qr/stephen king/i, category => "STEPHEN KING" },
    { regex => qr/hitchhiker.?s? guide/i, category => "HITCHHIKER'S GUIDE" },
  ],
  "CARTOON TRIVIA" => [
    { regex => qr/disney/i, category => "DISNEY" },
    { regex => qr/x-men/i, category => "X-MEN" },
    { regex => qr/dc comics/i, category => "DC COMICS" },
    { regex => qr/wonder woman/i, category => "WONDER WOMAN" },
    { regex => qr/popeye/i, category => "POPEYE THE SAILOR" },
  ],
  "SONGS" => [
    { regex => qr/theme song/i, category => "THEME SONGS" },
  ],
  "MUSIC" => [
    { regex => qr/theme song/i, category => "THEME SONGS" },
    { regex => qr/80's tune performed by/i, category => "80'S TUNE PERFORMED BY" }, 
    { regex => qr/90's tune performed by/i, category => "90'S TUNE PERFORMED BY" }, 
    { regex => qr/50's chart toppers/i, category => "1950'S CHART TOPPERS" },
    { regex => qr/60's chart toppers/i, category => "1960'S CHART TOPPERS" },
    { regex => qr/70's chart toppers/i, category => "1970'S CHART TOPPERS" },
    { regex => qr/80's chart toppers/i, category => "1980'S CHART TOPPERS" },
    { regex => qr/90's chart toppers/i, category => "1990'S CHART TOPPERS" },
    { regex => qr/\b191\d/i, category => "1910'S MUSIC" },
    { regex => qr/\b192\d/i, category => "1920'S MUSIC" },
    { regex => qr/\b193\d/i, category => "1930'S MUSIC" },
    { regex => qr/\b194\d/i, category => "1940'S MUSIC" },
    { regex => qr/\b195\d/i, category => "1950'S MUSIC" },
    { regex => qr/\b196\d/i, category => "1960'S MUSIC" },
    { regex => qr/\b197\d/i, category => "1970'S MUSIC" },
    { regex => qr/\b198\d/i, category => "1980'S MUSIC" },
    { regex => qr/\b199\d/i, category => "1990'S MUSIC" },
    { regex => qr/\b200\d/i, category => "2000'S MUSIC" },
    { regex => qr/\b201\d/i, category => "2010'S MUSIC" },
    { regex => qr/fifties/i, category => "1950'S MUSIC" },
    { regex => qr/sixties/i, category => "1960'S MUSIC" },
    { regex => qr/seventies/i, category => "1970'S MUSIC" },
    { regex => qr/eighties/i, category => "1958'S MUSIC" },
    { regex => qr/nineties/i, category => "1990'S MUSIC" },
    { regex => qr/who sang/i, category => "WHO SANG THIS SONG" },
    { regex => qr/beatles/i, category => "BEATLES" },
    { regex => qr/20s tune/i, category => "1920'S MUSIC" },
    { regex => qr/30s tune/i, category => "1930'S MUSIC" },
    { regex => qr/40s tune/i, category => "1940'S MUSIC" },
    { regex => qr/50s tune/i, category => "1950'S MUSIC" },
    { regex => qr/60s tune/i, category => "1960'S MUSIC" },
    { regex => qr/70s tune/i, category => "1970'S MUSIC" },
    { regex => qr/80s tune/i, category => "1980'S MUSIC" },
    { regex => qr/90s tune/i, category => "1990'S MUSIC" },
    { regex => qr/musicals/i, category => "MUSICALS" },
    { regex => qr/80's tune: performed by/i, category => "80'S TUNE PERFORMED BY" },
    { regex => qr/bob dylan/i, category => "BOB DYLAN" },
    { regex => qr/grease:/i, category => "GREASE" },
    { regex => qr/terms:/i, category => "MUSIC TERMS" },
    { regex => qr/animaniacs/i, category => "ANIMANIACS" },
    { regex => qr/alternative/i, category => "ALTERNATIVE MUSIC" },
    { regex => qr/aerosmith/i, category => "AEROSMITH" },
    { regex => qr/alan parsons project/i, category => "ALAN PARSONS PROJECT" },
    { regex => qr/biggest hits/i, category => "BIGGEST HITS" },
    { regex => qr/blues brothers/i, category => "BLUES BROTHERS" },
    { regex => qr/christmas songs/i, category => "CHRISTMAS SONGS" },
    { regex => qr/country music/i, category => "COUNTRY MUSIC" },
    { regex => qr/covers:/i, category => "MUSIC COVERS" },
    { regex => qr/disney songs/i, category => "DISNEY SONGS" },
    { regex => qr/pop rock/i, category => "POP ROCK" },
    { regex => qr/frank sinatra/i, category => "FRANK SINATRA" },
    { regex => qr/finish the song line/i, category => "FINISH THE SONG LINE" },
    { regex => qr/first song on album/i, category => "FIRST SONG ON ALBUM" },
    { regex => qr/female vocalists/i, category => "FEMALE VOCALISTS" },
    { regex => qr/epic songs/i, category => "EPIC SONGS" },
    { regex => qr/FOOPY MUSIC/i, category => "FOOPY MUSIC" },
    { regex => qr/gee music/i, category => "MUSICAL LETTER G" },
    { regex => qr/:g music/i, category => "MUSICAL LETTER G" },
    { regex => qr/grunge/i, category => "GRUNGE MUSIC" },
    { regex => qr/john lennon/i, category => "JOHN LENNON" },
    { regex => qr/i get around:/i, category => "I GET AROUND MUSIC" },
    { regex => qr/keep on rocking/i, category => "KEEP ON ROCKING" },
    { regex => qr/LEAD SINGERS:/i, category => "LEAD SINGERS" },
    { regex => qr/LITERATE ROCK/i, category => "LITERATE ROCK" },
    { regex => qr/MALE VOCALISTS/i, category => "MALE VOCALISTS" },
    { regex => qr/MISHEARD LYRICS/i, category => "MISHEARD LYRICS" },
    { regex => qr/MODERN ROCK/i, category => "MODERN ROCK" },
    { regex => qr/MONTY PYTHON LYRIC/i, category => "MONTY PYTHON LYRIC" },
    { regex => qr/\bMTV\b/i, category => "MTV" },
    { regex => qr/musical food/i, category => "MUSICAL FOOD" },
    { regex => qr/MUSICAL GRAB BAG/i, category => "MUSICAL GRAB BAG" },
    { regex => qr/ONE HIT WONDERS/i, category => "ONE HIT WONDERS" },
    { regex => qr/NUMBER ONE SONGS/i, category => "NUMBER ONE SONGS" },
    { regex => qr/NUMBER 1 SONGS/i, category => "NUMBER ONE SONGS" },
    { regex => qr/RAP TRIVIA/i, category => "RAP TRIVIA" },
    { regex => qr/RUSH:/i, category => "RUSH" },
    { regex => qr/SKA MUSIC/i, category => "SKA MUSIC" },
    { regex => qr/SONG TITLES/i, category => "SONG TITLES" },
    { regex => qr/THE JACKSONS:/i, category => "MUSIC: THE JACKSONS" },
    { regex => qr/THE POLICE:/i, category => "MUSIC: THE POLICE" },
    { regex => qr/videos:/i, category => "NAME THIS MUSIC VIDEO" },
    { regex => qr/WEIRD AL/i, category => "WEIRD AL" },
    { regex => qr/WHO SANG IT/i, category => "WHO SANG IT" },
    { regex => qr/CLASSICAL/i, category => "CLASSICAL MUSIC" },
    { regex => qr/COLOURFUL SONGS/i, category => "COLOURFUL SONGS" },
    { regex => qr/COMPLETE THIS ELVIS SONG TITLE/i, category => "COMPLETE THIS ELVIS SONG TITLE" },
    { regex => qr/COPYCATS:/i, category => "MUSIC COPYCATS" },
    { regex => qr/COMPOSER:/i, category => "COMPOSERS" },
    { regex => qr/david bowie/i, category => "DAVID BOWIE" },
    { regex => qr/eagles:/i, category => "MUSIC: EAGLES" },
    { regex => qr/eagles song/i, category => "MUSIC: EAGLES" },
    { regex => qr/elton john/i, category => "ELTON JOHN" },
    { regex => qr/elvis costello/i, category => "ELVIS COSTELLO" },
    { regex => qr/elvis presley/i, category => "ELVIS PRESLEY" },
    { regex => qr/essential clapton/i, category => "ERIC CLAPTON" },
    { regex => qr/first lines of songs/i, category => "FIRST LINES OF SONGS" },
    { regex => qr/food:/i, category => "MUSIC AND FOOD" },
    { regex => qr/garth brooks/i, category => "GARTH BROOKS" },
    { regex => qr/grateful dead/i, category => "GRATEFUL DEAD" },
    { regex => qr/jazz/i, category => "JAZZ" },
    { regex => qr/JIMMY BUFFET/i, category => "JIMMY BUFFET" },
    { regex => qr/METALLICA/i, category => "METALLICA" },
    { regex => qr/MIDNIGHT OIL:/i, category => "MUSIC: MIDNIGHT OIL" },
    { regex => qr/MONTY PYTHON SONGS/i, category => "MONTY PYTHON SONGS" },
    { regex => qr/MUSICAL STYLES:/i, category => "MUSICAL STYLES" },
    { regex => qr/MUSICAL (?:LETTER )? A:/i, category => "MUSICAL LETTER A" },
    { regex => qr/MUSICAL (?:LETTER )? B:/i, category => "MUSICAL LETTER B" },
    { regex => qr/MUSICAL (?:LETTER )? C:/i, category => "MUSICAL LETTER C" },
    { regex => qr/MUSICAL (?:LETTER )? D:/i, category => "MUSICAL LETTER D" },
    { regex => qr/MUSICAL (?:LETTER )? E:/i, category => "MUSICAL LETTER E" },
    { regex => qr/MUSICAL (?:LETTER )? F:/i, category => "MUSICAL LETTER F" },
    { regex => qr/MUSICAL (?:LETTER )? G:/i, category => "MUSICAL LETTER G" },
    { regex => qr/MUSICAL (?:LETTER )? H:/i, category => "MUSICAL LETTER H" },
    { regex => qr/MUSICAL (?:LETTER )? I:/i, category => "MUSICAL LETTER I" },
    { regex => qr/MUSICAL (?:LETTER )? J:/i, category => "MUSICAL LETTER J" },
    { regex => qr/MUSICAL (?:LETTER )? K:/i, category => "MUSICAL LETTER K" },
    { regex => qr/MUSICAL (?:LETTER )? L:/i, category => "MUSICAL LETTER L" },
    { regex => qr/MUSICAL (?:LETTER )? M:/i, category => "MUSICAL LETTER M" },
    { regex => qr/MUSICAL (?:LETTER )? N:/i, category => "MUSICAL LETTER N" },
    { regex => qr/MUSICAL (?:LETTER )? O:/i, category => "MUSICAL LETTER O" },
    { regex => qr/MUSICAL (?:LETTER )? P:/i, category => "MUSICAL LETTER P" },
    { regex => qr/MUSICAL (?:LETTER )? Q:/i, category => "MUSICAL LETTER Q" },
    { regex => qr/MUSICAL (?:LETTER )? R:/i, category => "MUSICAL LETTER R" },
    { regex => qr/MUSICAL (?:LETTER )? S:/i, category => "MUSICAL LETTER S" },
    { regex => qr/MUSICAL (?:LETTER )? T:/i, category => "MUSICAL LETTER T" },
    { regex => qr/MUSICAL (?:LETTER )? U:/i, category => "MUSICAL LETTER U" },
    { regex => qr/MUSICAL (?:LETTER )? V:/i, category => "MUSICAL LETTER V" },
    { regex => qr/MUSICAL (?:LETTER )? W:/i, category => "MUSICAL LETTER W" },
    { regex => qr/MUSICAL (?:LETTER )? X:/i, category => "MUSICAL LETTER X" },
    { regex => qr/MUSICAL (?:LETTER )? Y:/i, category => "MUSICAL LETTER Y" },
    { regex => qr/MUSICAL (?:LETTER )? Z:/i, category => "MUSICAL LETTER Z" },
    { regex => qr/MICHAEL JACKSON/i, category => "MICHAEL JACKSON" },
    { regex => qr/NAMES IN SONGS/i, category => "NAMES IN SONGS" },
    { regex => qr/NAME THE ARTIST/i, category => "NAME THE BAND" },
    { regex => qr/NAME THE ALBUM/i, category => "NAME THE ALBUM" },
    { regex => qr/name the band/i, category => "NAME THE BAND" },
    { regex => qr/NAME THE SONG/i, category => "NAME THE SONG" },
    { regex => qr/NAME THE GROUP/i, category => "NAME THE BAND" },
    { regex => qr/ROLLING STONES/i, category => "ROLLING STONES" },
    { regex => qr/REGGAE:/i, category => "REGGAE" },
    { regex => qr/RECORD LABELS/i, category => "RECORD LABELS" },
    { regex => qr/RAVE CULTURE/i, category => "RAVE CULTURE" },
    { regex => qr/RAY CHARLES/i, category => "RAY CHARLES" },
    { regex => qr/SINATRA/i, category => "FRANK SINATRA" },
    { regex => qr/SONG TITLE"/i, category => "SONG TITLES" },
    { regex => qr/SPORTS IN MUSIC/i, category => "SPORTS IN MUSIC" },
    { regex => qr/STYLES:/i, category => "MUSIC STYLES" },
    { regex => qr/THE DOORS:/i, category => "MUSIC: THE DOORS" },
    { regex => qr/TOM PETTY/i, category => "TOM PETTY" },
    { regex => qr/TORI AMOS/i, category => "TORI AMOS" },
    { regex => qr/TV THEMES/i, category => "THEME SONGS" },
    { regex => qr/WHAT INSTRUMENT /i, category => "WHAT INSTRUMENT DID THEY USE" },
    { regex => qr/MADONNA/i, category => "MADONNA" },
    { regex => qr/ERIC CLAPTON/i, category => "ERIC CLAPTON" },
    { regex => qr/: WHO RECORDED/i, category => "NAME THAT BAND" },
    { regex => qr/: WHO SANG/i, category => "NAME THAT SINGER" },
    { regex => qr/pink floyd/i, category => "PINK FLOYD" },
    { regex => qr/pop singers/i, category => "POP SINGERS" },
    { regex => qr/punk rock/i, category => "PUNK ROCK" },
    { regex => qr/NINE INCH NAILS/i, category => "NINE INCH NAILS" },
    { regex => qr/NIRVANA/i, category => "NIRVANA" },
    { regex => qr/NICKNAMES:/i, category => "NICKNAMES" },
    { regex => qr/opera/i, category => "OPERA" },
  ],
  "TV / MOVIES" => [
    { regex => qr/007:/i, category => "JAMES BOND" },
    { regex => qr/charlie chaplin/i, category => "CHARLIE CHAPLIN" },
    { regex => qr/- starred in this movie:/i, category => "NAME THE MOVIE" },
    { regex => qr/starred in this movie/i, category => "NAME THE ACTOR" },
    { regex => qr/w[io]n the oscar/i, category => "WHICH FILM WON THE OSCAR FOR..." },
    { regex => qr/\b191\d/i, category => "1910'S TV / MOVIES" },
    { regex => qr/\b192\d/i, category => "1920'S TV / MOVIES" },
    { regex => qr/\b193\d/i, category => "1930'S TV / MOVIES" },
    { regex => qr/\b194\d/i, category => "1940'S TV / MOVIES" },
    { regex => qr/\b195\d/i, category => "1950'S TV / MOVIES" },
    { regex => qr/\b196\d/i, category => "1960'S TV / MOVIES" },
    { regex => qr/\b197\d/i, category => "1970'S TV / MOVIES" },
    { regex => qr/\b198\d/i, category => "1980'S TV / MOVIES" },
    { regex => qr/\b199\d/i, category => "1990'S TV / MOVIES" },
    { regex => qr/\b200\d/i, category => "2000'S TV / MOVIES" },
    { regex => qr/\b201\d/i, category => "2010'S TV / MOVIES" },
    { regex => qr/cartoons/i, category => "CARTOONS" },
    { regex => qr/: 50.?s/i, category => "1950'S TV / MOVIES" },
    { regex => qr/: 60.?s/i, category => "1960'S TV / MOVIES" },
    { regex => qr/: 70.?s/i, category => "1970'S TV / MOVIES" },
    { regex => qr/: 80.?s/i, category => "1980'S TV / MOVIES" },
    { regex => qr/: 90.?s/i, category => "1990'S TV / MOVIES" },
    { regex => qr/academy award/i, category => "ACADAMY AWARDS" },
    { regex => qr/(?:ACTORS|ACTRESSES) IN FILM/i, category => "ACTORS IN FILM" },
    { regex => qr/(?:ACTORS|ACTRESSES) IN THE ROLE/i, category => "ACTORS IN THE ROLE" },
    { regex => qr/(?:ACTORS|ACTRESSES) IN TV/i, category => "ACTORS IN TV" },
    { regex => qr/CARTOONISTS/i, category => "CARTOONISTS" },
    { regex => qr/ANIMANIACS/i, category => "ANIMANIACS" },
    { regex => qr/ANIME/i, category => "ANIME" },
    { regex => qr/BACK TO THE FUTURE/i, category => "BACK TO THE FUTURE" },
    { regex => qr/BATMAN/i, category => "BATMAN" },
    { regex => qr/BLADE RUNNER/i, category => "BLADE RUNNER" },
    { regex => qr/90210/i, category => "BEVERLY HILLS 90210" },
    { regex => qr/the goonies/i, category => "THE GOONIES" },
    { regex => qr/BLAZING SADDLES/i, category => "BLAZING SADDLES" },
    { regex => qr/BLUES BROTHERS/i, category => "BLUES BROTHERS" },
    { regex => qr/B MOVIES/i, category => "B MOVIES" },
    { regex => qr/FRIENDS:/i, category => "FRIENDS" },
    { regex => qr/evil dead/i, category => "EVIL DEAD" },
    { regex => qr/buffy/i, category => "BUFFY THE VAMPIRE SLAYER" },
    { regex => qr/80s films/, category => "80'S FILMS" },
    { regex => qr/BRADY MANIA/i, category => "BRADY MANIA" },
    { regex => qr/CARTOON SIDEKICKS/i, category => "CARTOON SIDEKICKS" },
    { regex => qr/CHEERS TRIVIA/i, category => "CHEERS TRIVIA" },
    { regex => qr/DEFINING ROLES/i, category => "DEFINING ROLES" },
    { regex => qr/DICK VAN DYKE/i, category => "DICK VAN DYKE" },
    { regex => qr/DISNEY/i, category => "DISNEY" },
    { regex => qr/DIRECTORS:/i, category => "DIRECTORS" },
    { regex => qr/DOCTOR WHO/i, category => "DOCTOR WHO" },
    { regex => qr/DR.? SEUSS/i, category => "DR SEUSS" },
    { regex => qr/DUKES OF HAZZARD/i, category => "DUKES OF HAZZARD" },
    { regex => qr/FAMILY FLICKS/i, category => "FAMILY FLICKS" },
    { regex => qr/FILM TOP COPS/i, category => "FILM TOP COPS" },
    { regex => qr/TV TOP COPS/i, category => "TV TOP COPS" },
    { regex => qr/game shows/i, category => "GAME SHOWS" },
    { regex => qr/fox tv/i, category => "FOX TV" },
    { regex => qr/: FULL HOUSE/i, category => "FULL HOUSE" },
    { regex => qr/GILLIGANS ISLAND/i, category => "GILLIGANS ISLAND" },
    { regex => qr/GREASE:/i, category => "GREASE" },
    { regex => qr/HIGHLANDER/i, category => "HIGHLANDER" },
    { regex => qr/: HOLLYWOOD/i, category => "HOLLYWOOD" },
    { regex => qr/INDEPENDENT FILMS/i, category => "INDEPENDENT FILMS" },
    { regex => qr/INDIANA JONES/i, category => "INDIANA JONES" },
    { regex => qr/JAMES BOND/i, category => "JAMES BOND" },
    { regex => qr/: LETTERMAN/i, category => "LETTERMAN" },
    { regex => qr/MARX MOVIES/i, category => "MARX MOVIES" },
    { regex => qr/MASH/i, category => "M*A*S*H" },
    { regex => qr/MONTY PYTHON/i, category => "MONTY PYTHON" },
    { regex => qr/OLDER MOVIES/i, category => "OLDER MOVIES" },
    { regex => qr/MOVIE BOMBS/i, category => "MOVIE BOMBS" },
    { regex => qr/MOVIE LINES/i, category => "MOVIE LINES" },
    { regex => qr/MOVIE MUSICALS:/i, category => "MOVIE MUSICALS" },
    { regex => qr/MOVIE QUOTES/i, category => "MOVIE QUOTES" },
    { regex => qr/MOVIE TAG LINE/i, category => "MOVIE TAG LINES" },
    { regex => qr/MOVIE THAT FEATURES/i, category => "MOVIE THAT FEATURES..." },
    { regex => qr/MOVIE TRIVIA/i, category => "MOVIE TRIVIA" },
    { regex => qr/MTV FEATURES/i, category => "MTV MOVIES" },
    { regex => qr/MUPPET MANIA/i, category => "MUPPET MANIA" },
    { regex => qr/NAME THEIR NETWORK/i, category => "NAME THEIR TV NETWORK" },
    { regex => qr/NAME THAT TV SHOW/i, category => "NAME THAT TV SHOW" },
    { regex => qr/POWER RANGERS/i, category => "POWER RANGERS" },
    { regex => qr/PULP FICTION/i, category => "PULP FICTION" },
    { regex => qr/QUALITY MOVIES/i, category => "QUALITY MOVIES" },
    { regex => qr/QUANTUM LEAP/i, category => "QUANTUM LEAP" },
    { regex => qr/ROBOTECH/i, category => "ROBOTECH" },
    { regex => qr/ROCKY HORROR/i, category => "ROCKY HORROR" },
    { regex => qr/SCI FI MOVIES/i, category => "SCI FI MOVIES" },
    { regex => qr/quotes:/i, category => "MOVIE QUOTES" },
    { regex => qr/gone with the wind/i, category => "GONE WITH THE WIND" },
    { regex => qr/harry potter/i, category => "HARRY POTTER" },
    { regex => qr/RUSH LIMBAUGH/i, category => "RUSH LIMBAUGH" },
    { regex => qr/SIDEKICK/i, category => "SIDEKICKS" },
    { regex => qr/SIMPSONS/i, category => "THE SIMPSONS" },
    { regex => qr/SITCOMS/i, category => "SITCOMS" },
    { regex => qr/SPORTS ACTORS/i, category => "SPORTS ACTORS" },
    { regex => qr/STAR TREK/i, category => "STAR TREK" },
    { regex => qr/SUPERSTARS/i, category => "SUPERSTARS" },
    { regex => qr/TARANTINO/i, category => "TARANTINO" },
    { regex => qr/THREES COMPANY/i, category => "THREES COMPANY" },
    { regex => qr/THE TICK/i, category => "THE TICK" },
    { regex => qr/TV LAST NAMES/i, category => "TV LAST NAMES" },
    { regex => qr/TV OCCUPATIONS/i, category => "TV OCCUPATIONS" },
    { regex => qr/TV PETS/i, category => "TV PETS" },
    { regex => qr/TWIN PEAKS/i, category => "TWIN PEAKS" },
    { regex => qr/UK TV/i, category => "UK TV" },
    { regex => qr/WIZARD OF OZ/i, category => "WIZARD OF OZ" },
    { regex => qr/VAMPIRES/i, category => "VAMPIRES" },
    { regex => qr/WINONA RYDER/i, category => "WINONA RYDER" },
    { regex => qr/x.files/i, category => "X FILES" },
    { regex => qr/CLIVE BARKER/i, category => "CLIVE BARKER" },
    { regex => qr/COMEDY/i, category => "COMEDIES" },
    { regex => qr/who (?:play|star|was)/i, category => "NAME THE ACTOR" },
    { regex => qr/bill ted/i, category => "BILL AND TED" },
    { regex => qr/bill (?:&|and) ted/i, category => "BILL AND TED" },
    { regex => qr/bleeding heart movies/i, category => "BLEEDING HEART MOVIES" },
    { regex => qr/theme song/i, category => "THEME SONGS" },
    { regex => qr/quotes/i, category => "MOVIE QUOTES" },
    { regex => qr/\bSNL\b/i, category => "SATURDAY NIGHT LIVE" },
    { regex => qr/southpark/i, category => "SOUTHPARK" },
    { regex => qr/star wars/i, category => "STAR WARS" },
  ],
  "SCIENCE" => [
    { regex => qr/computer/i, category => "COMPUTERS" },
    { regex => qr/science & nature/i, category => "SCIENCE & NATURE" },
    { regex => qr/science & technology/i, category => "SCIENCE & TECHNOLOGY" },
    { regex => qr/periodic table/i, category => "PERIODIC TABLE" },
    { regex => qr/chemical/i, category => "CHEMISTRY" },
  ],
  "SCIENCE & TECHNOLOGY" => [
    { regex => qr/in computing/i, category => "COMPUTER SCIENCE" },
    { regex => qr/mathemat/i, category => "MATHEMATICS" },
    { regex => qr/chemistry/i, category => "CHEMISTRY" },
    { regex => qr/what does \w+ stand for/i, category => "TECHNICAL ACRONYMS" },
    { regex => qr/vitamin/i, category => "VITAMINS" },
    { regex => qr/chemical/i, category => "CHEMISTRY" },
    { regex => qr/operating system/i, category => "COMPUTER SCIENCE" },
    { regex => qr/video.*game/i, category => "VIDEO GAMES" },
  ],
  "SCIENCE & NATURE" => [
    { regex => qr/planet/i, category => "PLANETS" },
    { regex => qr/\bplant/i, category => "PLANTS" },
    { regex => qr/chemical/i, category => "CHEMISTRY" },
    { regex => qr/fruit/i, category => "FRUITS" },
    { regex => qr/periodic table/i, category => "PERIODIC TABLE" },
    { regex => qr/the young of this animal/i, category => "BABY ANIMAL NAMES" },
    { regex => qr/: the study of/i, category => "THE STUDY OF..." },
    { regex => qr/constellation/i, category => "CONSTELLATIONS" },
    { regex => qr/atomic number/i, category => "ATOMIC NUMBER / MASS" },
    { regex => qr/atomic mass/i, category => "ATOMIC NUMBER / MASS" },
    { regex => qr/group nouns/i, category => "ANIMAL GROUP NOUNS" },
    { regex => qr/fish breeds/i, category => "FISH BREEDS" },
    { regex => qr/cat breeds/i, category => "CAT BREEDS" },
    { regex => qr/dog breeds/i, category => "DOG BREEDS" },
    { regex => qr/dinosaur/i, category => "DINOSAURS" },
    { regex => qr/cats (?:have|were)/i, category => "CATS" },
  ],
  "GAMES" => [
    { regex => qr/card game/i, category => "CARD GAMES" },
    { regex => qr/board game/i, category => "BOARD GAMES" },
  ],
  "MOVIES" => [
  ],
  "LANGUAGE & LINGUISTICS" => [
    { regex => qr/are the major languages in/i, category => "MAJOR LANGUAGES IN..." },
    { regex => qr/official language of/i, category => "OFFICIAL LANGUAGE OF..." },
    { regex => qr/greek alphabet/i, category => "GREEK ALPHABET" },
  ],
  "LANGUAGE" => [
  ],
  "ENTERTAINMENT" => [
  ],
);

push @{$refilter_rules{"GAMES"}}, @{$refilter_rules{"SPORTS"}};
push @{$refilter_rules{"MOVIES"}}, @{$refilter_rules{"TV / MOVIES"}};
push @{$refilter_rules{"FILM"}}, @{$refilter_rules{"TV / MOVIES"}};
push @{$refilter_rules{"TV"}}, @{$refilter_rules{"TV / MOVIES"}};
push @{$refilter_rules{"LANGUAGE"}}, @{$refilter_rules{"LANGUAGE & LINGUISTICS"}};
push @{$refilter_rules{"ENTERTAINMENT"}}, @{$refilter_rules{"TV / MOVIES"}};


my @disregard_rules = (
  qr/ANIMAL IN YOU/,
  qr/BOXING/,
  qr/THE WHO/,
  qr/ON THIS DAY/,
  qr/AUTHORITY/,
  qr/PHYSICS/,
  qr/CANADIANISMS/,
  qr/IN COMMON/,
  qr/ELECTRICITY/,
  qr/B MOVIES/,
);

print STDERR "Categorizing documents\n";

for my $i (0 .. $#lines) {
  # Remove/fix stupid things
  $lines[$i] =~ s/\s*(?:category|potpourri)\s*:\s*//gi;
  $lines[$i] =~ s/(\w:)(\w)/$1 $2/g;
  $lines[$i] =~ s{/}{ / }g;
  $lines[$i] =~ s{&}{ & }g;
  $lines[$i] =~ s/\s+/ /g;
  $lines[$i] =~ s/^Useless Trivia: What word means/Definitions: What word means/i;
  $lines[$i] =~ s/^useless triv \d+/Useless Trivia/i;
  $lines[$i] =~ s/^general\s*(?:knowledge)?\s*\p{PosixPunct}\s*//i;
  $lines[$i] =~ s/^(?:\(|\[)(.*?)(?:\)|\])\s*/$1: /;
  $lines[$i] =~ s/star\s?wars/Star Wars/ig;
  $lines[$i] =~ s/^sport\s*[:-]\s*(.*?)\s*[:-]/$1: /i;
  $lines[$i] =~ s/^trivia\s*[:;-]\s*//i;
  $lines[$i] =~ s/^triv\s*[:;-]\s*//i;
  $lines[$i] =~ s/^93 94\p{PosixPunct}?\s*//;

  my @l = split /`/, $lines[$i];

  if (not $l[0] =~ m/ /) {
    print STDERR "Skipping doc $i (no spaces): $l[0] ($l[1])\n";
    next; 
  }

  # skip questions that we don't want
  my $skip = 0;
  foreach my $rule (@skip_rules) {
    if ($l[0] =~ m/$rule/) {
      print STDERR "Skipping doc $i (matches $rule): $l[0] ($l[1])\n";
      $skip = 1;
      last;
    }
  }
  next if $skip;

  # If the question has an obvious category, use that
  if ($l[0] =~ m/^(.{3,30}?)\s*[:;-]/ or $l[0] =~ m/^(.{3,30}?)\s*\./) {
    my $cat = uc $1;
    my $max_spaces = 5;
    $max_spaces = 3 if $cat =~ s/\.$//;
    my $nspc = () = $cat =~ m/\s+/g;
    if ($nspc <= $max_spaces) {
      if ($cat !~ m/(general|^A |_+| u$| "c$)/i) {
        my $pass = 1;
        foreach my $regex (@not_a_category) {
          if ($cat =~ m/$regex/) {
            $pass = 0;
            last;
          }
        }

        if ($pass) {
          $cat =~ s/^\s+|\s+$//g;
          $cat = uc $cat;
          $cat =~ s/'//g;
          $cat =~ s/\.//g;
          $cat =~ s/(?:\s+$|\R|^"|"$|^-|^\[|\]$)//g;
          $cat =~ s/\s+/ /g;
          $cat =~ s/(\d+)S/$1'S/g;
          $cat =~ s/ (?:AND|N|'N) / & /;

          # rename any categories
          foreach my $rule (@rename_rules) {
            if ($cat =~ m/$rule->{old}/) {
              $cat = uc $rule->{new};
              last;
            }
          }

          print STDERR "Using obvious $cat for doc $i: $l[0] ($l[1])\n";
          push @{$docs{$cat}}, $i;
          next;
        }
      }
    }
  }

  # No obvious category to extract, use rule-based filtering
  my $found = 0;
  foreach my $rule (@uncategorized_rules) {
    if ($l[0] =~ m/$rule->{regex}/) {
      my $cat = uc $rule->{'category'};
      push @{$docs{$cat}}, $i;
      $found = 1;
      print STDERR "Using rules $cat for doc $i: $l[0] ($l[1])\n";
      last;
    }
  }

  next if $found;

  print STDERR "Uncategorized doc $i: $l[0] ($l[1])\n";

  push @uncat, $i;
}

my %approved;

# refilter questions from certain categories into better sub-categories
foreach my $key (keys %refilter_rules) {
  print STDERR "Refiltering [$key]\n";
  for (my $i = 0; $i < @{$docs{$key}}; $i++) {
    my $doc = $docs{$key}->[$i];
    my @l = split /`/, $lines[$doc];
    foreach my $rule (@{$refilter_rules{$key}}) {
      if ($l[0] =~ m/$rule->{regex}/) {
        print STDERR "Refiltering doc $doc from $key to $rule->{category} $l[0] ($l[1])\n";
        push @{$docs{$rule->{category}}}, $doc;
        splice @{$docs{$key}}, $i--, 1;
        $approved{$rule->{category}} = 1;
        last;
      }
    }
  }
}

# generate a list of categories that meet the minimum category size
print STDERR "Done phase 1\n";
print STDERR "Generated ", scalar keys %docs, " categories.\n";

my $small = 0;
my $total = 0;

foreach my $cat (sort { @{$docs{$b}} <=> @{$docs{$a}} } keys %docs) {
  print STDERR "  $cat: ", scalar @{$docs{$cat}}, "\n";

  if (@{$docs{$cat}} < $minimum_category_size) {
    $small++ 
  } else {
    $total += @{$docs{$cat}};
    $approved{$cat} = 1;
  }
}

# dump the small categories to see what weird things are being mistaken for a category
print STDERR "-" x 80, "\n";
print STDERR "Small categories: $small; total cats: ", (scalar keys %docs) - $small, " with $total questions.\n";
print STDERR "-" x 80, "\n";

foreach my $cat (sort keys %docs) {
  print STDERR "  $cat: ", scalar @{$docs{$cat}}, "\n" if @{$docs{$cat}} < $minimum_category_size;
}

print STDERR "Uncategorized: ", scalar @uncat, "\n";

# go through all uncategorized questions and compare the questions word-by-word
# against existing categories word-by-word and filter questions that contain all
# the words of a category into said category
my $stemmer = Lingua::Stem->new;
$stemmer->stem_caching({ -level => 2 });
$stemmer->add_exceptions(
  {
    'authority' => 'authority',
    'musical' => 'musical',
    'anime' => 'anime',
  }
);

my @remaining_uncat;
my $i = 0;
$total = @uncat;
foreach my $doc (sort { $lines[$a] cmp $lines[$b] } @uncat) {
  if ($i % 1000 == 0) {
    print STDERR "-" x 80, "\n";
    print STDERR "$i / $total\n"; 
    print STDERR "-" x 80, "\n";
  }
  $i++;
  my @l = split /`/, $lines[$doc];
  my @doc_words = split / /, $l[0];
  @doc_words = map { local $_ = $_; s/\p{PosixPunct}//g; lc $_ } @doc_words;
  my @doc_numbers = grep { $_ =~ m/\d/ } @doc_words;
  @doc_words = @{ $stemmer->stem_in_place(grep { length $_ > 1 and $_ !~ m/\d/ } @doc_words) };
  push @doc_words, @doc_numbers;

  my $categorized = 0;
  foreach my $cat (sort { length $b <=> length $a } keys %approved) {
    my $skip = 0;
    foreach my $rule (@disregard_rules) {
      if ($cat =~ m/$rule/) {
        $skip = 1;
        last;
      }
    }
    next if $skip;

    my @cat_words = split / /, $cat;
    @cat_words = map { local $_ = $_; s/\p{PosixPunct}//g; lc $_ } @cat_words;
    my @cat_numbers = grep { $_ =~ m/\d/ } @cat_words;
    @cat_words = @{ $stemmer->stem_in_place(grep { length $_ > 1 and $_ !~ m/\d/ } @cat_words) };
    push @cat_words, @cat_numbers;

    my %matches;
    foreach my $cat_word (@cat_words) {
      foreach my $doc_word (@doc_words) {
        if ($cat_word eq $doc_word) {
          $matches{$cat_word} = 1;
          goto MATCH if keys %matches == @cat_words;
        }
      }
    }

    MATCH:
    if (keys %matches == @cat_words) {
      print STDERR "Adding doc $doc to $cat: $l[0] ($l[1]) -- @doc_words == @cat_words\n";
      push @{$docs{$cat}}, $doc;
      $categorized = 1;
      last;
    }
  }

  if (not $categorized) {
    push @remaining_uncat, $doc;
  }
}

# filter remaining uncategorized questions by uncat rules
my %new_uncat;
foreach my $doc (@remaining_uncat) {
  my @l = split /`/, $lines[$doc];
  foreach my $rule (@remaining_uncat_rules) {
    if ($l[0] =~ m/$rule->{regex}/) {
      my $cat = uc $rule->{'category'};
      push @{$docs{$cat}}, $doc;
      if (@{$docs{$cat}} == $minimum_category_size) {
       $approved{$cat} = 1;
     } 
     print STDERR "Using uncat rules $cat for doc $i: $l[0] ($l[1])\n";
    } else {
      $new_uncat{$doc} = 1;
    }
  }
}
@remaining_uncat = keys %new_uncat;

# refilter questions in certain categories to other categories instead
foreach my $key (keys %refilter_rules) {
  for (my $i = 0; $i < @{$docs{$key}}; $i++) {
    my $doc = $docs{$key}->[$i];
    my @l = split /`/, $lines[$doc];
    foreach my $rule (@{$refilter_rules{$key}}) {
      if ($l[0] =~ m/$rule->{regex}/) {
        print STDERR "Refiltering doc $doc from $key to $rule->{category} $l[0] ($l[1])\n";
        push @{$docs{$rule->{category}}}, $doc;
        splice @{$docs{$key}}, $i--, 1;
        $approved{$rule->{category}} = 1;
        last;
      }
    }
  }
}

$total = 0;

foreach my $cat (keys %approved) {
  $total += @{$docs{$cat}};
}

# write the final questions to stdout, dump categories and counts to stderr
print STDERR "=" x 80, "\n";
print STDERR "Categories: ", scalar keys %approved, " with $total questions.\n";
print STDERR "=" x 80, "\n";

foreach my $cat (sort keys %approved) {
  print STDERR "$cat ... ";

  my $count = 0;
  foreach my $i (@{$docs{$cat}}) {
    print "$cat`$lines[$i]\n";
    $count++;
  }

  print STDERR "$count questions.\n";
}

# dump the remaining uncategorized questions to see what we've missed
print STDERR "-" x 80, "\n";
print STDERR "Remaining uncategorized: ", scalar @remaining_uncat, "\n";
foreach my $i (sort { $lines[$a] cmp $lines[$b] } @remaining_uncat) {
  print STDERR "uncategorized: $lines[$i]\n";
}

# dump the final questions sorted by category to make sure the rules are sane
print STDERR "x" x 80, "\n";
foreach my $cat (sort keys %approved) {
  foreach my $i (@{$docs{$cat}}) {
    print STDERR "$cat`$lines[$i]\n";
  }
}

