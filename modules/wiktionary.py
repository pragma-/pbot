# File: wiktionary.py
#
# Purpose: Parses Wiktionary pages into JSON and dumps it to STDOUT.
#
# This was written for wiktionary.pl since Wiktionary::Parser in CPAN
# seems to be broken and abandoned.

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

from wiktionaryparser import WiktionaryParser
import sys
import json

parser = WiktionaryParser()
entries = parser.fetch(sys.argv[1], sys.argv[2])
print(json.dumps(entries))
