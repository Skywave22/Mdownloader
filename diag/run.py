#!/usr/bin/env python3
"""TEMPORARY diagnostics for the CI dependency-resolution failure.

Not part of the fix: it exists only so a real Flutter 3.47.5 runner can tell us
what `flutter pub get` / analyze / compile actually say, because the authoring
sandbox cannot reach pub.dev or the Flutter SDK hosts.
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys

RES = pathlib.Path('diag/results')
RES.mkdir(parents=True, exist_ok=True)
PUBSPEC = pathlib.Path('pubspec.yaml')
ORIG = pathlib.Path('diag/pubspec.orig.yaml')


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=isinstance(cmd, str), text=True,
                          capture_output=True, **kw)


def parse_lock(text):
    pk, cur = {}, None
    for line in text.splitlines():
        m = re.match(r'^  ([A-Za-z0-9_]+):$', line)
        if m:
            cur = m.group(1)
            pk[cur] = {}
            continue
        m = re.match(r'^    version: "?([^"\s]+)"?$', line)
        if m and cur:
            pk[cur]['version'] = m.group(1)
        m = re.match(r'^    source: (\w+)$', line)
        if m and cur:
            pk[cur]['source'] = m.group(1)
    return pk


def write_pubspec(orig, overrides):
    block = ''.join(f'  {k}: "{v}"\n' for k, v in overrides.items())
    text = re.sub(r'^dependency_overrides:\n', 'dependency_overrides:\n' + block,
                  orig, count=1, flags=re.M)
    PUBSPEC.write_text(text)


def tail(path, n=60):
    lines = pathlib.Path(path).read_text(errors='replace').splitlines()
    print('\n'.join(lines[-n:]))


# ---------------------------------------------------------------- resolve
def phase_resolve():
    if not ORIG.exists():
        ORIG.write_text(PUBSPEC.read_text())
    orig = ORIG.read_text()
    locked = parse_lock(sh(['git', 'show', 'HEAD:pubspec.lock']).stdout)
    overrides = json.loads(pathlib.Path('diag/seeds.json').read_text())
    skip = {'flutter', 'flutter_test', 'flutter_localizations', 'skystream',
            'integration_test', 'sky_engine'}
    log, ok = [], False
    for attempt in range(1, 16):
        write_pubspec(orig, overrides)
        r = sh(['flutter', 'pub', 'get'])
        out = r.stdout + r.stderr
        log.append(f'=== attempt {attempt}  rc={r.returncode}\n'
                   f'overrides={json.dumps(overrides)}\n{out}\n')
        print(f'--- attempt {attempt}: rc={r.returncode}')
        if r.returncode == 0:
            ok = True
            break
        # Show only the solver's verdict, not the whole download chatter.
        verdict = [l for l in out.splitlines()
                   if 'Because' in l or 'So,' in l or 'version solving' in l
                   or 'depends on' in l or 'Failed' in l or 'Could not' in l
                   or 'error' in l.lower()]
        print('\n'.join(verdict[:12]))
        names = re.findall(r'depends on ([A-Za-z0-9_]+)\b', out)
        counts = {}
        for n in names:
            counts[n] = counts.get(n, 0) + 1
        cands = [n for n in names if n not in overrides and n not in skip]
        cands.sort(key=lambda n: -counts[n])
        if not cands:
            print('!! cannot auto-pick an override; stopping')
            break
        pick = cands[0]
        if pick in locked and locked[pick].get('version'):
            overrides[pick] = '^' + locked[pick]['version']
        else:
            overrides[pick] = 'any'
        print(f'++ adding override {pick}: {overrides[pick]}')
    (RES / 'resolve.txt').write_text('\n'.join(log))
    (RES / 'overrides.json').write_text(json.dumps(overrides, indent=2))
    (RES / 'resolve_ok.txt').write_text('OK\n' if ok else 'FAILED\n')
    if ok:
        shutil.copy('pubspec.lock', RES / 'pubspec.lock')
        shutil.copy('pubspec.yaml', RES / 'pubspec.resolved.yaml')
        phase_lockdiff()
    print('RESOLVED' if ok else 'NOT RESOLVED', json.dumps(overrides))
    sys.exit(0 if ok else 1)


def phase_lockdiff():
    old = parse_lock(sh(['git', 'show', 'HEAD:pubspec.lock']).stdout)
    new = parse_lock(pathlib.Path('pubspec.lock').read_text())
    lines = []
    for k in sorted(set(old) | set(new)):
        o, n = old.get(k), new.get(k)
        if o is None:
            lines.append(f'+ {k} {n.get("version")} ({n.get("source")})')
        elif n is None:
            lines.append(f'- {k} {o.get("version")}')
        elif o.get('version') != n.get('version') or o.get('source') != n.get('source'):
            lines.append(f'~ {k} {o.get("version")} -> {n.get("version")} ({n.get("source")})')
    (RES / 'lockdiff.txt').write_text('\n'.join(lines) + '\n')
    print(f'lock changes: {len(lines)}')
    print('\n'.join(lines))


# ---------------------------------------------------------------- plugins
def phase_plugins():
    man = json.loads(pathlib.Path('.flutter-plugins-dependencies').read_text())
    plugins = man['plugins']
    actual = {p: sorted(x['name'] for x in plugins.get(p, []) if x.get('native_build'))
              for p in ('android', 'ios', 'macos', 'linux', 'windows')}
    src = pathlib.Path('test/platform/native_plugin_surface_test.dart').read_text()
    expected = {}
    for plat in actual:
        m = re.search(r"'%s': \{(.*?)\n  \}," % plat, src, re.S)
        body = re.sub(r'//[^\n]*', '', m.group(1)) if m else ''
        expected[plat] = sorted(set(re.findall(r"'([a-z0-9_]+)'", body)))
    out = []
    for plat in actual:
        added = sorted(set(actual[plat]) - set(expected[plat]))
        removed = sorted(set(expected[plat]) - set(actual[plat]))
        out.append(f'[{plat}] actual={len(actual[plat])} expected={len(expected[plat])}')
        out.append(f'   GAINED: {added}')
        out.append(f'   LOST:   {removed}')
    (RES / 'plugins.txt').write_text('\n'.join(out) + '\n')
    (RES / 'plugins_actual.json').write_text(json.dumps(actual, indent=2))
    print('\n'.join(out))


# ---------------------------------------------------------------- generate
def phase_gen():
    for name, cmd in (('gen_l10n', ['flutter', 'gen-l10n']),
                      ('build_runner', ['dart', 'run', 'build_runner', 'build',
                                         '--delete-conflicting-outputs'])):
        r = sh(cmd)
        (RES / f'{name}.txt').write_text(r.stdout + r.stderr)
        print(f'{name}: rc={r.returncode}')
        if r.returncode != 0:
            tail(RES / f'{name}.txt', 40)
    st = sh('git status --porcelain').stdout
    (RES / 'git_status.txt').write_text(st)
    diff = sh('git diff -- linux macos windows lib/l10n').stdout
    (RES / 'tracked_changes.diff').write_text(diff)
    gen = RES / 'generated'
    for line in st.splitlines():
        path = line[3:].strip()
        if re.search(r'(generated_plugin|GeneratedPluginRegistrant)', path) and \
                pathlib.Path(path).is_file():
            dst = gen / path
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(path, dst)
    print(st[:3000])


# ---------------------------------------------------------------- analyze
def phase_analyze():
    r = sh(['flutter', 'analyze', '--no-pub'])
    (RES / 'analyze.txt').write_text(r.stdout + r.stderr)
    print(f'flutter analyze rc={r.returncode}')
    tail(RES / 'analyze.txt', 40)


# ---------------------------------------------------------------- compile probe
PROBE = '''import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bridge compiles', () {
    expect(AnymeXRuntimeBridge.isSupportedPlatform, isA<bool>());
  });
}
'''


def phase_probe():
    p = pathlib.Path('test/_probe_compile_test.dart')
    p.write_text(PROBE)
    try:
        r = sh(['flutter', 'test', '--no-pub', str(p)])
    finally:
        p.unlink(missing_ok=True)
    out = r.stdout + r.stderr
    (RES / 'compile_probe.txt').write_text(out)
    errs = [l for l in out.splitlines() if 'Error:' in l]
    print(f'compile probe rc={r.returncode}, {len(errs)} "Error:" lines')
    print('\n'.join(errs[:40]))


if __name__ == '__main__':
    {'resolve': phase_resolve, 'lockdiff': phase_lockdiff, 'plugins': phase_plugins,
     'gen': phase_gen, 'analyze': phase_analyze, 'probe': phase_probe}[sys.argv[1]]()
