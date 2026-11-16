#!/usr/bin/env python3
"""Benign TCP lab fixture. Never executes commands received via the network."""
import argparse
import datetime as dt
import json
import socket
import socketserver
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--name', required=True, choices=['user','web','database','admin'])
parser.add_argument('--ip', required=True)
parser.add_argument('--port', type=int, default=8080)
parser.add_argument('--database-ip', default='')
parser.add_argument('--marker-log', required=True)
args = parser.parse_args()

class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(2)
        received = bytearray()
        try:
            while len(received) < 1024:
                part = self.request.recv(1024)
                if not part:
                    break
                received.extend(part)
                if b'\n' in part:
                    break
            message = received.decode('utf-8', errors='replace').strip()
            if message == 'PING':
                response = 'OK:' + args.name
            elif message.startswith('MARKER ') and args.name == 'database':
                marker = message[7:][:80]
                event = {'time_utc': dt.datetime.now(dt.timezone.utc).isoformat(), 'host': 'database', 'marker': marker, 'from': self.client_address[0]}
                with open(args.marker_log, 'a', encoding='utf-8') as file:
                    file.write(json.dumps(event) + '\n')
                response = 'MARKER_RECEIVED:' + marker
            elif message.startswith('TRIGGER ') and args.name == 'web' and args.database_ip:
                marker = message[8:][:80]
                try:
                    with socket.create_connection((args.database_ip, args.port), timeout=1.0) as upstream:
                        upstream.settimeout(1.0)
                        upstream.sendall(('MARKER '+marker+'\n').encode())
                        data = upstream.recv(256).decode('utf-8', errors='replace').strip()
                    response = 'WEB_FORWARDED:' + data
                except OSError as exc:
                    response = 'WEB_CANNOT_REACH_DATABASE:' + type(exc).__name__
            else:
                response = 'INVALID_REQUEST'
            self.request.sendall((response+'\n').encode())
        except (OSError, UnicodeError):
            pass

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server((args.ip, args.port), Handler) as server:
    server.serve_forever(poll_interval=0.2)
