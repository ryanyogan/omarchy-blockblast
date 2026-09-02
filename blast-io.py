#!/usr/bin/env python3
# Blast's I/O helper. The QML service shells out here for the only two kinds
# of I/O the plugin does: the state file and the leaderboard API. Keeping both
# in one small child process means every open is descriptor-bound, every read
# is capped at the producer, and killing the process cleans up everything --
# it spawns no children.
#
#   read              -> state file bytes on stdout (empty if absent)
#   write             -> replaces the state file with $BLAST_STATE
#   request METHOD URL -> "<http status>\n<body>" on stdout, $BLAST_BODY sent
#
# Exit codes: 0 ok, 1 filesystem refusal, 2 no connection, 3 policy refusal
# (untrusted URL, redirect, oversized payload), 5 oversized response.

import json
import os
import stat
import sys
import urllib.error
import urllib.parse
import urllib.request

STATE_DIR_PARTS = (".local", "state", "blast")
STATE_FILE = "blast.json"
MAX_STATE_READ = 262144    # bytes of state file honored
MAX_STATE_WRITE = 120000   # bytes of state accepted for writing (fits one env var)
MAX_RESPONSE = 262144      # bytes of any HTTP response read off the socket
MAX_REQUEST = 8192         # bytes of any request body sent
HTTP_TIMEOUT = 8           # seconds per socket operation

O_DIR = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC


def die(msg, code=1):
    sys.stderr.write(msg + "\n")
    sys.exit(code)


def open_state_dir(create):
    """Walk $HOME -> .local/state/blast one component at a time with
    O_NOFOLLOW, requiring every step to be a directory owned by this user.
    Returns the held fd of the final directory (forced to 0700), or None
    when it does not exist and create is False."""
    home = os.environ.get("HOME", "")
    if not os.path.isabs(home):
        die("no HOME")
    uid = os.getuid()
    fd = os.open(home, O_DIR)
    st = os.fstat(fd)
    if st.st_uid != uid:
        die("HOME is not owned by this user")
    for part in STATE_DIR_PARTS:
        try:
            nfd = os.open(part, O_DIR, dir_fd=fd)
        except FileNotFoundError:
            if not create:
                os.close(fd)
                return None
            os.mkdir(part, 0o700, dir_fd=fd)
            nfd = os.open(part, O_DIR, dir_fd=fd)
        os.close(fd)
        fd = nfd
        st = os.fstat(fd)
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != uid:
            die("untrusted path component: " + part)
    if st.st_mode & 0o077:
        os.fchmod(fd, 0o700)
    return fd


def cmd_read():
    dfd = open_state_dir(create=False)
    if dfd is None:
        return
    try:
        ffd = os.open(STATE_FILE, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=dfd)
    except FileNotFoundError:
        return
    st = os.fstat(ffd)
    if not stat.S_ISREG(st.st_mode):
        die("state is not a regular file")
    if st.st_uid != os.getuid():
        die("state is not owned by this user")
    if st.st_size > MAX_STATE_READ:
        die("state file too large")
    data = bytearray()
    while len(data) <= MAX_STATE_READ:
        chunk = os.read(ffd, 65536)
        if not chunk:
            break
        data += chunk
    sys.stdout.buffer.write(bytes(data[:MAX_STATE_READ]))


def cmd_write():
    text = os.environ.get("BLAST_STATE")
    if text is None:
        die("no BLAST_STATE")
    raw = text.encode("utf-8")
    if len(raw) > MAX_STATE_WRITE:
        die("state too large", 3)
    try:
        json.loads(text)
    except ValueError:
        die("state is not JSON", 3)
    dfd = open_state_dir(create=True)
    # The destination must be absent, or a regular file we own; never
    # rename over a symlink or anything unexpected.
    try:
        st = os.stat(STATE_FILE, dir_fd=dfd, follow_symlinks=False)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
            die("unexpected destination, refusing to replace it")
    except FileNotFoundError:
        pass
    tmp = ".blast.%d.tmp" % os.getpid()
    try:
        os.unlink(tmp, dir_fd=dfd)
    except FileNotFoundError:
        pass
    ffd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=dfd)
    try:
        view = memoryview(raw)
        while view:
            view = view[os.write(ffd, view):]
        os.fsync(ffd)
    finally:
        os.close(ffd)
    os.rename(tmp, STATE_FILE, src_dir_fd=dfd, dst_dir_fd=dfd)
    os.fsync(dfd)


def trusted_url(url):
    """https to any host; plain http only to the local machine. No
    credentials in the URL, no other schemes."""
    try:
        p = urllib.parse.urlsplit(url)
    except ValueError:
        return False
    if p.username or p.password or not p.hostname:
        return False
    if p.scheme == "https":
        return True
    if p.scheme == "http":
        return p.hostname in ("localhost", "127.0.0.1", "::1")
    return False


class RefuseRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def cmd_request(method, url):
    if method not in ("GET", "POST", "DELETE"):
        die("method not allowed", 3)
    if not trusted_url(url):
        die("Blocked: the leaderboard URL must be https (http is allowed for localhost only)", 3)
    body = os.environ.get("BLAST_BODY") or None
    data = None
    if body is not None:
        data = body.encode("utf-8")
        if len(data) > MAX_REQUEST:
            die("request body too large", 3)
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "blast-omarchy-plugin/1.2",
    })
    opener = urllib.request.build_opener(RefuseRedirect())
    try:
        resp = opener.open(req, timeout=HTTP_TIMEOUT)
        status, out = resp.status, resp.read(MAX_RESPONSE + 1)
        resp.close()
    except urllib.error.HTTPError as e:
        if 300 <= e.code < 400:
            die("Blocked: the server tried to redirect", 3)
        status, out = e.code, e.read(MAX_RESPONSE + 1)
        e.close()
    except Exception:
        die("No connection", 2)
    if len(out) > MAX_RESPONSE:
        die("Response too large", 5)
    sys.stdout.buffer.write(("%d\n" % status).encode("ascii"))
    sys.stdout.buffer.write(out)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if cmd == "read":
            cmd_read()
        elif cmd == "write":
            cmd_write()
        elif cmd == "request" and len(sys.argv) == 4:
            cmd_request(sys.argv[2], sys.argv[3])
        else:
            die("usage: blast-io.py read | write | request METHOD URL", 3)
    except OSError as e:
        die("refused: " + str(e))


if __name__ == "__main__":
    main()
