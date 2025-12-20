#!/usr/bin/env python

import requests
import csv
import datetime
import time
import re
from bs4 import BeautifulSoup

#url = 'https://www.iso-9899.info/candide/quotegrabs.html'
#response = requests.get(url)

with open('quotegrabs.html', 'r') as file:
    soup = BeautifulSoup(file, 'html.parser')

channels = soup.find_all('h3')

with open('quotes.csv', 'w', newline='') as csvfile:
    writer = csv.writer(csvfile)

    for channel in channels:
        table = channel.find_next_sibling('table')
        rows = table.find_all('tr')

        for row in rows:
            print(row)
            tds = row.find_all('td')
            if len(tds) != 5: continue
            id, authors, text, date, grabber = [td.text for td in tds]
            first_author = authors.split(', ')[0]
            timestamp = time.mktime(datetime.datetime.strptime(date, '%Y/%m/%d %a %H:%M:%S').timetuple())

            if text[0] == '<':
                text = re.sub(r'^<[^>]+> ', '', text, count=1)
            else:
                text = re.sub(r'^\* ([^\s]+)', '/me', text, count=1)

            messages = []
            authors = []

            for i, message in enumerate(text.split('   ')):
                message = message.strip()
                author = re.match(r'^\* ([^ ]+)', message) or re.match(r'<([^>]+)>', message)
                print(author, message)
                if i > 0 and not author: continue
                author = author.group(1) if i > 0 else first_author
                authors.append(author)

            print(authors, text)
            writer.writerow([id, '+'.join(authors), channel.text, grabber, text, timestamp])
