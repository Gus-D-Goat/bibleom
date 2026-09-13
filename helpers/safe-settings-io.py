#!/usr/bin/env python3
"""Descriptor-relative, symlink-safe read/write for this plugin's settings.

Every path component from $HOME down is opened relative to its already-open
*parent directory descriptor* with O_NOFOLLOW, so a component swapped for a
symlink after being checked can never be silently followed later -- the
next openat() on it simply fails closed. The final file is read through
that same retained descriptor with a hard size cap, or replaced by
publishing a randomized, exclusive, 0600 temp file created through that
descriptor and rename()'d atomically within it (renameat(), not a fresh
path lookup that could re-resolve through something an attacker swapped in
between steps).

Usage:
  safe-settings-io.py read  <relative/path/from/HOME>
  safe-settings-io.py write <relative/path/from/HOME>   (content on stdin)

Exit codes: 0 success, 1 usage/argument error, 2 path/permission guard
failed, 3 file absent (read only -- caller should fall back to defaults).
"""
import os
import stat
import sys

MAX_BYTES = 65536
DIR_MODE = 0o700
FILE_MODE = 0o600


def fail(code, message):
    print(f"safe-settings-io: {message}", file=sys.stderr)
    sys.exit(code)


def check_owned_private_dir(fd, uid):
    st = os.fstat(fd)
    if not stat.S_ISDIR(st.st_mode):
        fail(2, "path component is not a directory")
    if st.st_uid != uid:
        fail(2, "directory is not owned by the current user")
    if st.st_mode & 0o022:
        fail(2, "directory is group- or world-writable")


def open_root(home, uid):
    try:
        fd = os.open(home, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError as e:
        fail(2, f"cannot open HOME: {e}")
    check_owned_private_dir(fd, uid)
    return fd


def descend(parent_fd, name, uid):
    try:
        os.mkdir(name, DIR_MODE, dir_fd=parent_fd)
    except FileExistsError:
        pass
    except OSError as e:
        fail(2, f"cannot create {name!r}: {e}")
    try:
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
    except OSError as e:
        fail(2, f"cannot open {name!r}: {e}")
    check_owned_private_dir(fd, uid)
    return fd


def do_read(dir_fd, filename, uid):
    try:
        fd = os.open(filename, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
    except FileNotFoundError:
        sys.exit(3)
    except OSError as e:
        fail(2, f"cannot open {filename!r}: {e}")
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            fail(2, f"{filename!r} is not a regular file")
        if st.st_uid != uid:
            fail(2, f"{filename!r} is not owned by the current user")
        if st.st_size > MAX_BYTES:
            fail(2, f"{filename!r} exceeds the {MAX_BYTES}-byte cap")
        data = os.read(fd, MAX_BYTES + 1)
    finally:
        os.close(fd)
    sys.stdout.buffer.write(data[:MAX_BYTES])


def do_write(dir_fd, filename):
    # A single line, not read-until-EOF: the caller writes one line of
    # compact (non-pretty-printed) JSON to our stdin and never closes it,
    # matching this codebase's existing Process.write() convention.
    content = sys.stdin.buffer.readline(MAX_BYTES + 1)
    if len(content) > MAX_BYTES:
        fail(1, f"content exceeds the {MAX_BYTES}-byte cap")

    tmp_name = f".{filename}.tmp-{os.urandom(9).hex()}"
    fd = os.open(tmp_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, FILE_MODE, dir_fd=dir_fd)
    try:
        written = 0
        while written < len(content):
            written += os.write(fd, content[written:])
        os.fsync(fd)
    finally:
        os.close(fd)

    try:
        os.rename(tmp_name, filename, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
    except OSError as e:
        try:
            os.unlink(tmp_name, dir_fd=dir_fd)
        except OSError:
            pass
        fail(2, f"cannot publish {filename!r}: {e}")


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("read", "write"):
        fail(1, "usage: safe-settings-io.py <read|write> <relative/path/from/HOME>")

    action, rel_path = sys.argv[1], sys.argv[2]
    parts = rel_path.split("/")
    if not parts or any(p in ("", ".", "..") for p in parts):
        fail(1, "invalid relative path")

    home = os.environ.get("HOME")
    if not home:
        fail(1, "HOME is not set")

    uid = os.getuid()
    dir_fd = open_root(home, uid)
    try:
        for component in parts[:-1]:
            next_fd = descend(dir_fd, component, uid)
            os.close(dir_fd)
            dir_fd = next_fd

        filename = parts[-1]
        if action == "read":
            do_read(dir_fd, filename, uid)
        else:
            do_write(dir_fd, filename)
    finally:
        os.close(dir_fd)


if __name__ == "__main__":
    main()
