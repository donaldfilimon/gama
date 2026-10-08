#!/usr/bin/env python3
"""Test-only Darwin PTY allocator; never touches/restores terminal settings.

The pinned Zig std lacks Darwin PTY allocation declarations and this host's
legacy /dev/pty* nodes return EAGAIN. All assertions and interaction live in Zig.
Exec preserves the pair until the Zig parent has inspected its held slave.
"""
import os
import sys

master, slave = os.openpty()
os.set_inheritable(master, True)
os.set_inheritable(slave, True)
env = os.environ.copy()
env["GAMA_TEST_PTY_MASTER"] = str(master)
env["GAMA_TEST_PTY_SLAVE"] = str(slave)
env["GAMA_TEST_PTY_NAME"] = os.ttyname(slave)
try:
    os.execvpe(sys.argv[1], sys.argv[1:], env)
finally:
    os.close(slave)
    os.close(master)
