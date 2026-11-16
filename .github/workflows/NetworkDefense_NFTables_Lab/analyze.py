#!/usr/bin/env python3
"""Read only real evidence files. No sample or synthetic results."""
import csv
import json
from collections import defaultdict
from pathlib import Path

folder = Path(__file__).parent / 'results'
files = sorted(folder.glob('tcp_*.csv')) + sorted(folder.glob('pivot_*.csv'))
if not files:
    raise SystemExit('No TCP evidence CSV files found; run the laboratory first.')
counts = defaultdict(lambda: [0,0])
for path in files:
    with path.open(newline='', encoding='utf8') as fp:
        for row in csv.DictReader(fp):
            k = row['mode'], row['source'], row['target']
            counts[k][0] += int(row['success'])
            counts[k][1] += 1
print('MODE | SOURCE -> TARGET | SUCCESS/TOTAL')
for key in sorted(counts):
    s,n = counts[key]
    print(f'{key[0]:14s} | {key[1]:8s}->{key[2]:8s} | {s}/{n}')
summary = [{ 'mode': mode, 'source': src, 'target': target, 'successes': val[0], 'attempts': val[1] }
           for (mode,src,target),val in sorted(counts.items())]
(folder/'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf8')
print('\nSummary saved to:',folder/'summary.json')
