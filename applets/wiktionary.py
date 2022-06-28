# File: wiktionary.py
#
# Purpose: Parses Wiktionary pages into JSON and dumps it to STDOUT.
#
# This was written for wiktionary.pl since Wiktionary::Parser in CPAN
# seems to be broken and abandoned.
#
# Important: This uses a custom fork of wiktionaryparser which contains
# numerous fixes. To install it use:
#
# pip install git+https://github.com/pragma-/WiktionaryParser

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

from wiktionaryparser import WiktionaryParser
import sys
import json

parser = WiktionaryParser()
entries = parser.fetch(sys.argv[1], sys.argv[2])
print(json.dumps(entries))
