# Security notes

This plugin runs unsandboxed inside the Omarchy shell, like any other
Quickshell plugin. Two hardening measures worth documenting explicitly:

## 1. Trusted absolute commands, minimal environment

`BarWidget.qml` shells out to `omarchy-shell` twice (to cycle to a new ayah,
and to toggle drag-repositioning). Both `Process` blocks:

- Invoke `/usr/bin/omarchy-shell` by absolute path rather than the bare
  command name, so a shadow executable earlier in an inherited `PATH`
  (a mutable, user-writable entry such as a tool-version-manager shim
  directory) can never be run instead of the real binary.
- Set `clearEnvironment: true` and pass an explicit, minimal `environment`
  containing only the variables `omarchy-shell` actually needs to locate
  the running shell and its IPC socket (`PATH` pinned to `/usr/bin`,
  `HOME`, `OMARCHY_PATH`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`) — nothing
  else from the parent process's environment is inherited.

The same trusted-absolute-command + minimal-environment treatment is used
for the Python helper described below.

## 2. Descriptor-relative, no-follow settings I/O

Both `Service.qml` (the desktop overlay) and `BarWidget.qml` (the control
panel) need to read and write a small JSON settings file at a predictable,
`$HOME`-derived path (`~/.local/state/omarchy/quran-motivation-settings.json`).
Neither touches that path directly — both shell out to
[`helpers/safe-settings-io.py`](helpers/safe-settings-io.py) (via
`/usr/bin/python3`, absolute path, `clearEnvironment: true`, environment
limited to `HOME`), which does the actual I/O using `os.open`/`os.mkdir`/
`os.rename` with Linux's `dir_fd`-relative syscalls (`openat`/`mkdirat`/
`renameat`):

- **Traversal**: starting from `$HOME` itself, every intermediate path
  component (`.local`, `state`, `omarchy`) is opened with
  `O_DIRECTORY | O_NOFOLLOW` *relative to its parent's already-open file
  descriptor* — never by re-resolving a string path — and each is checked
  to be a directory owned by the current user with no group/world write
  bit before descending further. A component swapped for a symlink after
  being checked is never silently followed later: the next `openat()` on
  it simply fails closed (`ELOOP`).
- **Read**: the final file is opened `O_NOFOLLOW` relative to the retained
  parent descriptor, then `fstat()`'d on the open descriptor (not the
  path) to confirm it's a regular file, owned by the current user, within
  a 64 KiB cap, before reading up to that cap.
- **Write**: content is published by creating a randomized, exclusive,
  `0600` temp file (`O_CREAT | O_EXCL`) through the *same* retained
  directory descriptor, then `rename()`-ing it into place via
  `src_dir_fd`/`dst_dir_fd` on that same descriptor — a `renameat()`, not a
  fresh path lookup, so it can't be redirected by a component swapped in
  between steps, and it replaces the target's directory entry (symlink or
  not) atomically rather than ever writing through one.
- Anything absent, wrong type, wrong owner, or oversized makes the helper
  exit non-zero (see the exit codes documented at the top of the script);
  the QML side treats every non-zero exit as "use defaults," never as
  partial/untrusted content.

This closes the gap the earlier `stat`-then-`FileView.reload()` approach
had: that was a `stat` on a path string followed by a *separate* open of
the same path string, so a swap in between could still change what the
second open resolved to. Here there is no second path-string resolution —
every step after the initial `$HOME` open operates on an already-open
descriptor.

I verified this against real attacks locally, not just by reasoning about
it: pointing the settings path at a symlink to `/etc/passwd` made the read
fail closed with `ELOOP` (never printed the symlink's target), and writing
through that same symlinked path replaced the symlink itself with a real
regular file (verifying `/etc/passwd` was untouched afterward) rather than
writing through it — exactly the self-healing `rename()` semantics this
relies on. An oversized planted file was also correctly rejected before
any content was read into memory.

## Reporting

No network calls, no bundled third-party code, no privileged operations. If
you find a concrete issue beyond what's described above, please open an
issue on this repo.
