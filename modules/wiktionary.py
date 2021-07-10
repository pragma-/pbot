# File: wiktionary.py
#
# Purpose: Parses Wiktionary pages into JSON and dumps it to STDOUT.
#
# This was written for wiktionary.pl since Wiktionary::Parser in CPAN
# seems to be broken and abandoned.

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

from wiktionaryparser import WiktionaryParser
import sys
import json

parser = WiktionaryParser()
entries = parser.fetch(sys.argv[1], sys.argv[2])
print(json.dumps(entries))
