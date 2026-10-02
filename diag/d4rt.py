#!/usr/bin/env python3
"""TEMPORARY: validate the analyzer-14 port of d4rt.

1. analyze + run the upstream test suite on packages/d4rt (analyzer 14.4)
2. run the same suite on pristine upstream v0.1.7 (analyzer 7.4) as a baseline
3. report tests that fail only on the port (regressions) and only on baseline
"""
import json, os, pathlib, subprocess, sys, tempfile

WS = pathlib.Path(os.environ.get('GITHUB_WORKSPACE', '.')).resolve()
RES = WS / 'diag' / 'results'
RES.mkdir(parents=True, exist_ok=True)


def sh(cmd, cwd, timeout=1500):
    return subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str), text=True,
                          capture_output=True, timeout=timeout)


def run_suite(pkg_dir, label):
    pre = sh(['dart', 'pub', 'get'], pkg_dir)
    (RES / f'd4rt_{label}_pubget.txt').write_text(pre.stdout + pre.stderr)
    if pre.returncode != 0:
        print(f'[{label}] pub get FAILED')
        return None
    ana = sh(['dart', 'analyze'], pkg_dir)
    (RES / f'd4rt_{label}_analyze.txt').write_text(ana.stdout + ana.stderr)
    n_err = sum(1 for l in ana.stdout.splitlines() if ' error - ' in l)
    print(f'[{label}] dart analyze: rc={ana.returncode}, {n_err} errors')
    t = sh(['dart', 'test', '--reporter=json', '-j', '1'], pkg_dir)
    names, failed, passed, skipped = {}, {}, 0, 0
    errors = {}
    for line in t.stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if e.get('type') == 'testStart':
            names[e['test']['id']] = e['test']['name']
        elif e.get('type') == 'error':
            errors.setdefault(e['testID'], []).append((e.get('error') or '')[:300])
        elif e.get('type') == 'testDone' and not e.get('hidden'):
            if e.get('skipped'):
                skipped += 1
            elif e.get('result') == 'success':
                passed += 1
            else:
                failed[names.get(e['testID'], str(e['testID']))] = errors.get(e['testID'], [''])[:1]
    print(f'[{label}] tests: {passed} passed, {len(failed)} failed, {skipped} skipped (rc={t.returncode})')
    (RES / f'd4rt_{label}_test_stderr.txt').write_text(t.stderr[-6000:])
    (RES / f'd4rt_{label}_failures.json').write_text(json.dumps(failed, indent=1))
    return failed


port = run_suite(WS / 'packages' / 'd4rt', 'port')

tmp = pathlib.Path(tempfile.mkdtemp())
sh(['git', 'clone', '--quiet', 'https://github.com/kodjodevf/d4rt.git', 'base'], tmp)
sh(['git', 'checkout', '--quiet', '6867b56'], tmp / 'base')
base = run_suite(tmp / 'base', 'baseline')

if port is not None and base is not None:
    reg = sorted(set(port) - set(base))
    fixed = sorted(set(base) - set(port))
    out = [f'REGRESSIONS on the port (fail there, pass on baseline): {len(reg)}']
    for n in reg:
        out.append(f'  - {n}: {port[n]}')
    out.append(f'FAIL ON BOTH (pre-existing): {len(set(port) & set(base))}')
    out.append(f'FAIL ONLY ON BASELINE: {len(fixed)}')
    (RES / 'd4rt_comparison.txt').write_text('\n'.join(out) + '\n')
    print('\n'.join(out[:40]))
