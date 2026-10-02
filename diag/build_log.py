#!/usr/bin/env python3
"""TEMPORARY: run a build command, keep a readable slice of its log, always exit 0."""
import os, pathlib, re, subprocess, sys, time
label, cmd = sys.argv[1], sys.argv[2]
ws = pathlib.Path(os.environ.get('GITHUB_WORKSPACE', '.')).resolve()
out = ws / 'diag' / 'results' / f'build_{label}'
out.mkdir(parents=True, exist_ok=True)
t0 = time.time()
r = subprocess.run(cmd, shell=True, cwd=ws, text=True, capture_output=True, executable='/bin/bash')
log = (r.stdout or '') + (r.stderr or '')
lines = log.splitlines()
pat = re.compile(r'error|FAILURE|What went wrong|Execution failed|Caused by|Could not|e: |failed|Failed|CMake Error|undefined reference|fatal', re.I)
hits = [f'{n+1}: {l}' for n, l in enumerate(lines) if pat.search(l)]
(out / 'summary.txt').write_text(f'cmd={cmd}\nrc={r.returncode}\nseconds={time.time()-t0:.0f}\nlines={len(lines)}\n')
(out / 'tail.txt').write_text('\n'.join(lines[-350:]) + '\n')
(out / 'errors.txt').write_text('\n'.join(hits[:600]) + '\n')
print(f'{label}: rc={r.returncode} in {time.time()-t0:.0f}s ({len(lines)} lines, {len(hits)} suspicious)')
sys.exit(0)
