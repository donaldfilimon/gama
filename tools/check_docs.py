#!/usr/bin/env python3
"""Current documentation validation and pinned-AST API negative controls."""
import pathlib,re,subprocess,sys,tempfile
ROOT=pathlib.Path(__file__).resolve().parent.parent
REQUIRED=['AGENTS.md','CLAUDE.md','README.md','CONTRIBUTING.md','docs/Capabilities.md','docs/README.md','docs/Architecture.md','docs/StateAndIdentity.md','docs/Plugins.md','docs/Performance.md','docs/backends/TUI.md','docs/backends/CEmbed.md','docs/backends/WASM.md','examples/README.md','docs/superpowers/specs/2026-10-03-zig-only-framework-design.md']
def generated_edge(source,path):
    imports=re.findall(r'@import\("([^"\n]+)"\)',source)
    for item in imports:
        if pathlib.PurePosixPath(item).name=='tables.zig':
            if path!='src/core/unicode.zig' or item!='unicode/tables.zig' or 'const tables = @import("unicode/tables.zig");' not in source or 'pub const tables' in source: raise ValueError('private generated table reexport/edge')
def documents():
    out=[ROOT/x for x in ['AGENTS.md','CLAUDE.md','README.md','CONTRIBUTING.md','examples/README.md','tasks/todo.md','tasks/goals.md','.agents/skills/run-gama/SKILL.md','.claude/skills/run-gama/SKILL.md']]
    out += [p for p in (ROOT/'docs').rglob('*.md') if not p.is_relative_to(ROOT/'docs/history/swift') and not p.is_relative_to(ROOT/'docs/superpowers/plans')]
    out += list((ROOT/"src").rglob("*.md"))
    return sorted(set(out))
def check_text(path,text):
    refs=0
    if path.name!='Capabilities.md' and path != ROOT/'docs/migration/zig/provenance.md':
        # Collapse wrapped paragraphs before classifying execution claims.
        paragraphs=[' '.join(x.split()) for x in text.split('\n\n')]
        if any(re.search(r'(?i)(?:Evidence-ID:|Receipt-ID:|(?:passed|verified|observed) .{0,120}(?:[0-9]+ tests|exit 0|at [0-9a-f]{40}))',x) for x in paragraphs):
            raise ValueError(str(path.relative_to(ROOT))+': current execution claim belongs in Capabilities')
    if re.search(r'(?:swiftly run|scripts/check-apple|scripts/bundle-|zig build gama-apple-demo)',text) and path != ROOT/'docs/migration/zig/provenance.md':
        raise ValueError('obsolete current command/product')
    for link in re.findall(r'\]\(([^)]+)\)',text):
        link=link.split('#')[0]
        if not link or '://' in link or link.startswith('mailto:'):continue
        target=(path.parent/link).resolve()
        if not target.exists():raise ValueError(f'{path.relative_to(ROOT)}: broken link {link}')
        # A history index is allowed; an obsolete how-to cannot serve as current backend guidance.
        if '/history/swift/backends/' in str(target):raise ValueError('current link to retired backend guide')
        refs+=1
    for item in re.findall(r'`([^`\n]+)`',text):
        if re.match(r'^(?:src|tools|tests|examples|scripts|include|docs)/[A-Za-z0-9_.\-/]+$|^(?:build\.zig(?:\.zon)?|ZigToolchain\.zon|\.zig-version)$',item):
            if not (ROOT/item).exists():raise ValueError(f'{path.relative_to(ROOT)}: missing named path {item}')
            refs+=1
    return refs

def require_documents(paths):
    if not paths:raise ValueError('empty document scope')
    for p in paths:
        if not p.is_file() or not p.read_text().strip():raise ValueError('missing/empty required doc: '+str(p))

def check_references():
    require_documents([ROOT/x for x in REQUIRED])
    refs=sum(check_text(p,p.read_text()) for p in documents())
    if refs==0:raise ValueError('empty reference scope')
    for f in ['driver.sh','SKILL.md']:
        a=(ROOT/'.agents/skills/run-gama'/f).read_text();b=(ROOT/'.claude/skills/run-gama'/f).read_text().replace('.claude/skills/','.agents/skills/')
        if a!=b:raise ValueError('skill mirror drift '+f)
    return refs

def reference_controls():
    tests=['[missing](missing-file.md)','`src/not-a-real-file.zig`','`tools/missing.zig`','`build-missing.zig`',
           'Evidence-ID: made-up','Receipt-ID: fake','Verified a run with\n37 tests at '+'a'*40,
           'swiftly run swift build','scripts/check-apple.sh','[native](history/swift/backends/AppleUI.md)']
    # The unrecognized unanchored filename is deliberately outside named-path grammar.
    tests.remove('`build-missing.zig`')
    for text in tests:
        try:check_text(ROOT/'docs/Testing.md',text)
        except ValueError:continue
        raise ValueError('reference/locality negative accepted: '+text)
    check_text(ROOT/'docs/Testing.md','[current](Architecture.md) and `src/root.zig`')
    with tempfile.TemporaryDirectory(prefix='gama-doc-scope-') as d:
        p=pathlib.Path(d)/'empty.md';p.write_text('   ')
        for paths in [[],[p],[p.parent/'absent.md']]:
            try:require_documents(paths)
            except ValueError:continue
            raise ValueError('missing/empty doc scope accepted')
    return len(tests)+4

def controls(exe):
    # Each independent category is checked for absent AND whitespace-only documentation.
    cases={
      'function':'{doc}pub fn action() void {{}}',
      'reexport':'{doc}pub const module = @import("anything.zig");',
      'named-type':'{doc}pub const Options = struct {{}};',
      'field':'/// Options\npub const Options = struct {{\n{doc}size: usize }};',
      'enum':'/// Choice\npub const Choice = enum {{\n{doc}first }};',
      'union':'/// Choice\npub const Choice = union(enum) {{\n{doc}first: u32 }};',
      'anonymous-payload':'/// Choice\npub const Choice = union(enum) {{\n/// A\n first: struct {{\n{doc}size: u32 }} }};',
      'generic-field':'/// Factory\npub fn Factory(comptime T:type) type {{ return struct {{\n{doc}value:T }}; }}',
      'generic-method':'/// Factory\npub fn Factory() type {{ return struct {{\n{doc}pub fn read() void {{}} }}; }}',
      'generic-value':'/// Factory\npub fn Factory(comptime T:type) type {{ return struct {{\n{doc}pub const Value=T; }}; }}',
      'options':'/// Function\npub fn f(options:struct {{\n{doc}size:usize }}) void {{ _=options; }}',
      'owner-added-field':'/// Owner\npub const Host=struct {{\n{doc}new_field:usize }};',
      'namespace-helper':'/// Namespace\npub const n=struct {{\n{doc}pub fn helper() void {{}} }};',
      'indirect-type':'/// Function\npub fn f() Lines {{ return undefined; }} const Lines=struct {{\n{doc}items:[]u8 }};',
      'error-tag':'/// Errors\npub const E=error{{\n{doc}Failure }};',
      'inline':'{doc}pub inline fn f() void {{}}',
    }
    n=0
    with tempfile.TemporaryDirectory(prefix='gama-doc-controls-') as d:
        path=pathlib.Path(d)/'fixture.zig'
        def run(source,good,expected=None):
            nonlocal n
            path.write_text(source)
            r=subprocess.run([exe,str(path)],capture_output=True)
            if (r.returncode==0)!=good:raise ValueError('API control failed: '+source+'\n'+r.stderr.decode())
            if expected and expected not in r.stderr.decode():raise ValueError('wrong rejection reason: '+r.stderr.decode())
            n+=1
        for template in cases.values():
            for doc in ['', '///   \n','//! module only\n','// ordinary\n','//// ordinary\n']:run(template.format(doc=doc),False,'UndocumentedApi' if doc in ['', '///   \n'] else None)
            run(template.format(doc='/// Contract.\n'),True)
        run('/// sibling\npub const a=1;\npub const b=2;',False)
        run('pub const broken = struct {',False)
        run('const text="/// not a comment";',False)
        run('/// A\r\npub const A=struct {\r\n/// Value\r\nx:u32\r\n};',True)
        run('const tables=@import("tables.zig");\n/// bad\npub const leak=tables;',False,'GeneratedApiExposure')
        run('const tables=@import("tables.zig"); const alias=tables;\n/// bad\npub const Leak=alias.Range;',False,'GeneratedApiExposure')
        run('const tables=@import("tables.zig");\n/// bad\npub fn leak() tables.Range { return undefined; }',False,'GeneratedApiExposure')
        run('const tables=@import("tables.zig");\n/// bad\npub const X=struct {\n/// bad\nx:tables.Range };',False,'GeneratedApiExposure')
        run('const tables=@import("unicode/tables.zig");\n/// Factory\npub fn Leak() type { return tables.Range; }',False,'GeneratedApiExposure')
        run('const tables=@import("unicode/tables.zig"); fn hidden() type { return tables.Range; } const Hidden=hidden();\n/// Indirect\npub fn leak() Hidden { return undefined; }',False,'GeneratedApiExposure')
        run('const tables=@import("unicode/tables.zig"); fn first() type { return tables.Range; } fn second() type { return first(); } const Hidden=second();\n/// Alias\npub const Leak=Hidden;',False,'GeneratedApiExposure')
        run('const tables=@import("unicode/tables.zig");\n/// Runtime lookup\npub fn width(cp:u21) u8 { return tables.width(cp); }',True)
        run('//! GENERATED; no exemption\n/// Range\npub const Range=struct { lo:u21, };',False,'UndocumentedApi')
        run('//! GENERATED; no exemption\n/// Range\npub const Range=struct {\n/// Scalar lower bound.\nlo:u21, };',True)
        run('/// Multiline\npub\nconst\nValue\n=\n1;',True)
        run('/// Computed\npub const Value=unknown_expression(1);',True)
        run('pub const Value=unknown_expression(1);',False)

    try:generated_edge('/// table\npub const tables = @import("unicode/tables.zig");','src/core/unicode.zig')
    except ValueError:n+=1
    else:raise ValueError('generated reexport accepted')
    return n

def main():
    exe=sys.argv[1]
    refs=check_references()
    files=sorted(str(p.relative_to(ROOT)) for p in (ROOT/'src').rglob('*.zig'))
    if 'src/root.zig' not in files or not files:raise ValueError('empty/missing facade')
    for p in files:generated_edge((ROOT/p).read_text(),p)
    result=subprocess.run([exe,*files],cwd=ROOT,capture_output=True)
    if result.returncode:raise ValueError(result.stderr.decode())
    if result.stdout!=(ROOT/'docs/API.tsv').read_bytes():raise ValueError('API inventory drift; regenerate from the pinned AST and review')
    count=controls(exe)+reference_controls()
    print(f'Docs: {len(documents())} current documents, {refs} references, {len(result.stdout.splitlines())} API entries, {count} controls passed')
if __name__=='__main__': main()
