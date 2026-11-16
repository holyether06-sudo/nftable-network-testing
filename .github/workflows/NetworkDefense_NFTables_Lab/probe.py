#!/usr/bin/env python3
"""Measures actual socket connect + TCP request/response, writes all trials to CSV."""
import argparse
import csv
import json
import socket
import time
from pathlib import Path

P = argparse.ArgumentParser()
P.add_argument('--mode', required=True)
P.add_argument('--cycle', type=int, required=True)
P.add_argument('--source', choices=['attacker','web'], required=True)
P.add_argument('--target-map-json', required=True)
P.add_argument('--output', required=True)
P.add_argument('--repeats', type=int, default=5)
P.add_argument('--command', default='PING')
args = P.parse_args()
addresses = json.loads(args.target_map_json)
rows = []
for name, address in addresses.items():
    for trial in range(1, args.repeats+1):
        begin = time.perf_counter()
        result, response, err = False, '', ''
        try:
            with socket.create_connection((address, 8080), timeout=1.0) as s:
                s.settimeout(1.0)
                s.sendall((args.command+'\n').encode())
                response = s.recv(1024).decode(errors='replace').strip()
                result = response.startswith('OK:') and response[3:] == name
        except OSError as exc:
            err = type(exc).__name__ + ': ' + str(exc)[:100]
        rows.append({'mode': args.mode, 'cycle': args.cycle, 'source': args.source, 'target': name,
                     'target_ip': address, 'port': 8080, 'trial': trial, 'success': int(result),
                     'response': response, 'error': err, 'duration_ms': round((time.perf_counter()-begin)*1000, 3)})
        print(f'{args.mode:13s} c{args.cycle} {args.source:8s}->{name:8s} #{trial}: {"ALLOW" if result else "DENY"}')

output = Path(args.output)
output.parent.mkdir(parents=True, exist_ok=True)
with output.open('w', newline='', encoding='utf-8') as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)
