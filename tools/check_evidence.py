#!/usr/bin/env python3
"""Verify bounded maintained evidence, never ignored local preservation material."""
import hashlib,json,pathlib,sys,subprocess,platform
ROOT=pathlib.Path(__file__).resolve().parent.parent
EVIDENCE=ROOT/'docs/migration/zig/evidence'
ROOT_FILES=['build.zig','build.zig.zon','ZigToolchain.zon','.zig-version','.gitignore','Package.resolved','GEMINI.md','AGENTS.md','CLAUDE.md','README.md','CONTRIBUTING.md']
PREFIXES=['src','tests','examples','tools','scripts','include','.github','.codex/agents','.agents/skills/run-gama','.claude/skills/run-gama']
def scope():
    files=set(ROOT_FILES)
    for prefix in PREFIXES:
        directory=ROOT/prefix
        if not directory.is_dir():raise ValueError('missing source root '+prefix)
        for p in directory.rglob('*'):
            if p.is_symlink():raise ValueError('symlink in evidence source scope')
            if p.is_file() and p.name!='.DS_Store' and '__pycache__' not in p.parts:files.add(str(p.relative_to(ROOT)))
    for p in (ROOT/'docs').rglob('*'):
        if p.is_file() and p.suffix in {'.md','.tsv','.json'} and not p.is_relative_to(ROOT/'docs/history/swift') and not p.is_relative_to(ROOT/'docs/superpowers/plans') and not p.is_relative_to(EVIDENCE):files.add(str(p.relative_to(ROOT)))
    return sorted(files)
def digest(path):
    data=path.read_bytes()
    if len(data)>16*1024*1024:raise ValueError('evidence file exceeds bound')
    return {'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
EXPECTED_RUNS={
    'benchmark.log':('zig build bench -Doptimize=fast','native measurement'),
    'acceptance.log':('zig build qualify -j2 --summary all','native/static/cross/engine'),
    'assertions.log':('zig build qualify -j2 --summary all','native/static/cross/engine'),
    'terminal-frames.log':('zig build qualify -j2 --summary all','native tmux'),
    'artifact-inspection.log':('file zig-out/matrix/* zig-out/embedded/* zig-out/wasm/*','artifact inspection'),
}
def validate(receipt):
    if set(receipt)!={'schema','sources','commands','environment'} or receipt.get('schema')!=1 or not isinstance(receipt.get('environment'),dict) or not isinstance(receipt.get('commands'),list) or not 1<=len(receipt['commands'])<=32:raise ValueError('invalid/empty receipt')
    if len(receipt['commands'])!=len(EXPECTED_RUNS) or {r.get('log') for r in receipt['commands']}!=set(EXPECTED_RUNS):raise ValueError('missing/duplicate command evidence')
    actual={p:digest(ROOT/p) for p in scope()}
    if receipt.get('sources')!=actual:raise ValueError('source evidence stale, missing, or unexpected file')
    for run in receipt['commands']:
        if set(run)!={'command','exit','layer','log','digest'} or run['exit']!=0 or not isinstance(run['command'],str) or not 1<=len(run['command'])<=8192 or run['layer'] not in {'native tmux','native runtime','native measurement','native/static/cross/engine','documentation','artifact inspection','source consistency'}:raise ValueError('invalid command receipt')
        log=run['log']
        if (run['command'],run['layer'])!=EXPECTED_RUNS.get(log):raise ValueError('unknown/mismatched command evidence')
        if pathlib.PurePosixPath(log).name!=log:raise ValueError('log escapes maintained evidence')
        if digest(EVIDENCE/log)!=run['digest']:raise ValueError('log hash mismatch')
    if digest(ROOT/'Package.resolved')['sha256']!='62ccbf6d2a9f60961c383d9db6e45c5673fefab7643320ac180fbf59d4c234bf':raise ValueError('archival lock changed')
    if (ROOT/'GEMINI.md').stat().st_size:raise ValueError('GEMINI must remain empty')
    return len(actual)
def main():
    if len(sys.argv)!=2:raise ValueError('expected executing Zig compiler path')
    zig=sys.argv[1]
    version=subprocess.check_output([zig,'version'],text=True).strip()
    pin=json.loads((EVIDENCE/'toolchain.json').read_text())
    if version!=pin['version']:raise ValueError('executing compiler version mismatch')
    if platform.system()=='Darwin' and platform.machine()=='arm64':
        with open(zig,'rb') as f:compiler_hash=hashlib.file_digest(f,'sha256').hexdigest()
        if compiler_hash!=pin['installed_binary_sha256']:raise ValueError('executing compiler bytes differ from qualified pin')
    p=EVIDENCE/'source-receipt.json' 
    if p.stat().st_size>4*1024*1024:raise ValueError('oversized receipt')
    receipt=json.loads(p.read_text());n=validate(receipt)
    # Real negative controls mutate independent receipt claims, not the workspace.
    import copy
    mutations=[]
    for field in ['sources','commands']:
        m=copy.deepcopy(receipt);m[field]={} if field=='sources' else [];mutations.append(m)
    m=copy.deepcopy(receipt);m['sources'][next(iter(m['sources']))]['sha256']='0'*64;mutations.append(m)
    m=copy.deepcopy(receipt);m['sources']['src/unrecorded.zig']={'bytes':0,'sha256':'0'*64};mutations.append(m)
    m=copy.deepcopy(receipt);m['commands'][0]['digest']['sha256']='0'*64;mutations.append(m)
    m=copy.deepcopy(receipt);m['commands'][0]['log']='../private';mutations.append(m)
    m=copy.deepcopy(receipt);m['commands'][0]['exit']=1;mutations.append(m)
    m=copy.deepcopy(receipt);m['commands'][0]['layer']='unknown';mutations.append(m)
    m=copy.deepcopy(receipt);m['schema']=99;mutations.append(m)
    m=copy.deepcopy(receipt);m['commands'][0]['command']='invented successful command';mutations.append(m)
    m=copy.deepcopy(receipt);m['commands'].pop();mutations.append(m)
    m=copy.deepcopy(receipt);m['commands'][-1]=copy.deepcopy(m['commands'][0]);mutations.append(m)
    for m in mutations:
        try:validate(m)
        except (ValueError,FileNotFoundError):continue
        raise ValueError('evidence negative control accepted')
    print(f'Evidence consistency: {n} source files, {len(receipt["commands"])} command logs, {len(mutations)} negative controls passed')
if __name__=='__main__':main()
