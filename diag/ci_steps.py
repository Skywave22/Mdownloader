#!/usr/bin/env python3
"""TEMPORARY: run the `run:` steps of a ci.yml job exactly as written there.

Reading the steps out of ci.yml, rather than copying them, means this cannot
drift from the real gate. Unlike CI it keeps going after a failure, so one run
reports every failing step instead of only the first.
"""
import os, pathlib, re, subprocess, sys, tempfile, time
import yaml

job = sys.argv[1]
only = set(sys.argv[2:])            # optional: step names to run
ws = pathlib.Path(os.environ.get('GITHUB_WORKSPACE', '.')).resolve()
out = ws / 'diag' / 'results' / f'ci_{job}'
out.mkdir(parents=True, exist_ok=True)

wf = yaml.safe_load((ws / '.github' / 'workflows' / 'ci.yml').read_text())
steps = wf['jobs'][job]['steps']
envfile = pathlib.Path(tempfile.mkdtemp()) / 'github_env'
envfile.write_text('')
base_env = dict(os.environ, GITHUB_ENV=str(envfile), CI='true')
global_env = {k: str(v) for k, v in (wf.get('env') or {}).items()}

rows = []
for i, s in enumerate(steps, 1):
    name = s.get('name') or s.get('uses') or f'step{i}'
    if 'run' not in s or (only and name not in only):
        continue
    env = dict(base_env, **global_env)
    for k, v in (s.get('env') or {}).items():
        env[k] = str(v)
    # GITHUB_ENV writes from earlier steps (e.g. LIBQUICKJSC_TEST_PATH) carry over.
    for line in envfile.read_text().splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            env[k] = v
    script = out / f'.step{i}.sh'
    script.write_text(s['run'])
    t0 = time.time()
    r = subprocess.run(['bash', '-e', str(script)], cwd=ws, env=env, text=True,
                       capture_output=True)
    dt = time.time() - t0
    script.unlink()
    log = (r.stdout or '') + (r.stderr or '')
    slug = re.sub(r'[^A-Za-z0-9]+', '_', name).strip('_')[:50]
    lines = log.splitlines()
    keep = lines if len(lines) <= 700 else lines[:150] + ['... [%d lines elided] ...' % (len(lines) - 550)] + lines[-400:]
    (out / f'{i:02d}_{slug}.txt').write_text(f'rc={r.returncode} seconds={dt:.0f}\n' + '\n'.join(keep) + '\n')
    # The slice above drops the middle of a long log; failures are what matter, so
    # keep every failing group's heading and the start of its body, and every ::error::.
    fails = []
    for n, l in enumerate(lines):
        if l.startswith('::group::\u274c') or l.startswith('::error::'):
            fails.append('\n'.join(x[:400] for x in lines[n:n + 9]))
    if fails:
        (out / f'{i:02d}_{slug}_FAILURES.txt').write_text('\n--------\n'.join(fails) + '\n')
    rows.append((i, name, r.returncode, dt))
    print(f'[{i:02d}] rc={r.returncode:<3} {dt:6.0f}s  {name}', flush=True)

summary = '\n'.join(f'{i:02d}  rc={rc:<3}  {dt:5.0f}s  {n}' for i, n, rc, dt in rows)
(out / 'SUMMARY.txt').write_text(summary + '\n')
print('\n' + summary)
sys.exit(0)
