#!/usr/bin/python3
"""Protocol test fixture: emits small fake files; never accesses the network."""
import json
from pathlib import Path
import sys
import time
import uuid

request = json.load(sys.stdin)
mode = request['inputLocators'][0]
if mode == 'slow':
    time.sleep(20)
if mode == 'crash':
    print('fixture failure', file=sys.stderr)
    sys.exit(2)
if mode == 'malformed':
    print('not json')
    sys.exit(0)
if mode == 'oversized':
    print('x' * (8 * 1024 * 1024 + 1))
    sys.exit(0)
root = Path(request['outputDirectory'])
asset = root / 'video.mp4'
asset.write_bytes(b'fixture')
if mode == 'escape':
    outside = root.parent / 'outside.mp4'
    outside.write_bytes(b'keep me')
    asset.unlink()
    asset.symlink_to(outside)
if mode == 'empty-file':
    asset.write_bytes(b'')
candidate = {
    'metadata': {'title': '' if mode == 'empty-title' else 'Fixture video', 'origin': 'plugin',
                 'uploader': 'Fixture creator', 'publishedDate': '20260906', 'durationSeconds': 2},
    'sources': [{'id': str(uuid.uuid4()), 'kind': 'plugin', 'locator': 'fixture', 'addedAt': '2026-09-06T00:00:00Z'}],
    'assets': [{'id': str(uuid.uuid4()), 'role': 'master', 'path': str(asset), 'createdAt': '2026-09-06T00:00:00Z'}]
}
print(json.dumps({'protocolVersion': 1,
                  'requestID': str(uuid.uuid4()) if mode == 'wrong-id' else request['requestID'],
                  'succeeded': mode != 'failure', 'errorMessage': 'fixture rejected input',
                  'candidates': [candidate, candidate] if mode == 'multiple' else [candidate], 'messages': []}))
