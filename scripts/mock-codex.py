#!/usr/bin/env python3
"""Minimal mock of Logos Storage (Codex) API for demo purposes.
POST /api/codex/v1/data  → stores content, returns fake CID
GET  /api/codex/v1/data/<cid>/network/stream → returns stored content
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import hashlib, json, io, os

store = {}

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass  # quiet

    def do_POST(self):
        if self.path == '/api/codex/v1/data':
            length = int(self.headers.get('Content-Length', 0))
            data = self.rfile.read(length)
            cid = 'bafy' + hashlib.sha256(data).hexdigest()[:40]
            store[cid] = data
            self.send_response(200)
            self.send_header('Content-Type','application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'cid': cid}).encode())
        else:
            self.send_response(404); self.end_headers()

    def do_GET(self):
        if self.path.startswith('/api/codex/v1/data/'):
            cid = self.path.split('/')[5]
            if cid in store:
                self.send_response(200)
                self.send_header('Content-Type','application/octet-stream')
                self.end_headers()
                self.wfile.write(store[cid])
            else:
                self.send_response(404); self.end_headers()
        else:
            self.send_response(200)
            self.send_header('Content-Type','application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')

if __name__ == '__main__':
    s = HTTPServer(('127.0.0.1', 8080), Handler)
    print('Mock Codex running on :8080')
    s.serve_forever()
