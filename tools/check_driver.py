#!/usr/bin/env python3
"""Exercise conflict rejection and owned-session cleanup using real tmux."""
import os,pathlib,subprocess,tempfile,time,sys
root=pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='gama-driver-controls-') as d:
    env=dict(os.environ,GAMA_RUN_STATE=d+'/state',GAMA_RUN_SESSION='gama-control-'+str(os.getpid()),GAMA_RUN_BINARY=sys.argv[1])
    driver=str(root/'.agents/skills/run-gama/driver.sh'); name=env['GAMA_RUN_SESSION']
    created=subprocess.check_output(['tmux','new-session','-d','-P','-F','#{session_id}','-s',name,'sleep','30'],text=True).strip()
    try:
        r=subprocess.run([driver,'launch'],env=env,capture_output=True)
        assert r.returncode!=0 and b'refusing takeover' in r.stderr,r.stderr
        assert subprocess.check_output(['tmux','display-message','-p','-t',created,'#{session_id}'],text=True).strip()==created
    finally:subprocess.run(['tmux','kill-session','-t',created],check=True)
    subprocess.run([driver,'launch'],env=env,check=True)
    receipt=pathlib.Path(env['GAMA_RUN_STATE'])/name
    ident,token=receipt.read_text().splitlines()
    # A mismatched ownership token makes quit fail without killing the session.
    subprocess.run(['tmux','set-option','-t',ident,'@gama-owner','foreign'],check=True)
    r=subprocess.run([driver,'quit'],env=env,capture_output=True);assert r.returncode!=0
    assert subprocess.run(['tmux','has-session','-t',ident]).returncode==0
    subprocess.run(['tmux','set-option','-t',ident,'@gama-owner',token],check=True)
    subprocess.run([driver,'quit'],env=env,check=True)
    assert not receipt.exists()
    assert subprocess.run(['tmux','has-session','-t',ident],capture_output=True).returncode!=0
    fixture=pathlib.Path(d)/'idle.sh';fixture.write_text('#!/bin/sh\nsleep 30\n');fixture.chmod(0o700)
    env['GAMA_RUN_ARTIFACTS']=d+'/artifacts'
    proc=subprocess.Popen([driver,'smoke',str(fixture)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    ids=[]
    try:
        for _ in range(100):
            ids=list(pathlib.Path(env['GAMA_RUN_STATE']).glob('*-smoke-*'))
            if ids:break
            if proc.poll() is not None:raise AssertionError(proc.communicate())
            time.sleep(.05)
        assert ids, 'smoke never acquired owned session'
        owned_id=ids[0].read_text().splitlines()[0]
        proc.terminate();proc.communicate(timeout=5)
        assert proc.returncode==143,proc.returncode
        assert subprocess.run(['tmux','has-session','-t',owned_id],capture_output=True).returncode!=0
    finally:
        if proc.poll() is None:proc.kill();proc.wait()
        for receipt in ids:
            ident=receipt.read_text().splitlines()[0]
            subprocess.run(['tmux','kill-session','-t',ident],capture_output=True)
print('Driver controls: existing-name conflict, token mismatch, owned cleanup and TERM cleanup passed')
