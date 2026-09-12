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

The same pattern is used for the `stat` calls described below.

## 2. No-follow / ownership / size guard on the settings file

Both `Service.qml` (the desktop overlay) and `BarWidget.qml` (the control
panel) read and write a small JSON settings file at a predictable, `$HOME`-
derived path (`~/.local/state/omarchy/quran-motivation-settings.json`).
Before trusting that path's content, each does:

```
/usr/bin/stat -c '%F|%U|%s' <path>
```

with the same trusted-absolute-command + minimal-environment treatment as
above. GNU `stat` without `-L`/`--dereference` reports on the path *itself*,
not whatever a symlink there might point to — so a planted or swapped
symlink at that exact path is detected rather than followed. The result is
required to show:

- `%F` is exactly `regular file` (not a symlink, device, directory, etc.)
- `%U` matches the current user (`$USER`/`$LOGNAME`)
- `%s` is within a generous but bounded cap (64 KiB; real settings content
  is a few hundred bytes) — guards against a swapped-in oversized file

`FileView.blockLoading` stays `true` until that check passes, so the file is
never read unless all three hold; if the path doesn't exist yet, or fails
the check, in-memory defaults are used instead.

Writes are unaffected by this guard and always go through
`FileView.atomicWrites: true` (write-temp-then-rename), which — being a
`rename(2)` onto the target path — replaces whatever directory entry is
there (including a symlink) rather than writing through it. So the next
settings change from the panel self-heals a tampered path.

**Caveat:** the check-then-load is two separate operations (a `stat` process,
then a later file read), not a single atomic no-follow open syscall — a
pure-QML/Quickshell plugin has no access to `openat2(RESOLVE_NO_SYMLINKS)`
or similar. Exploiting the gap between them would require an attacker who
can already write inside the user's own `$HOME` at the moment of the
check, which is a substantially higher bar than the read-time guard this
closes.

## Reporting

No network calls, no bundled third-party code, no privileged operations. If
you find a concrete issue beyond what's described above, please open an
issue on this repo.
