# Changelog

## 1.0.2

- Keep `~/.ssh` on the persistent volume. OpenSSH reads it from
  `/etc/passwd`, not from `HOME`, so a key created inside the app was lost
  on the next rebuild.

## 1.0.1

- Bundle `openssh-client`, so Claude can push to Git over SSH. Generate a
  key once inside the app (`ssh-keygen`); it lives in the persistent
  storage and survives restarts, rebuilds and updates.

## 1.0.0

First release.

- Persistent Claude Code session, held in tmux and supervised by s6, so it
  is restarted automatically if it ever dies.
- Own bundled `ttyd` web terminal, reachable only through Home Assistant's
  authenticated ingress. No SSH server, no open port, no dependency on any
  other app.
- Appears in the sidebar. Nothing is ever written to your dashboard
  configuration.
- Credentials, conversation history and Claude's self-updates live in the
  app's persistent storage, so logging in is a one-time step and the
  conversation is resumed after restarts, rebuilds and reboots.
- Permission mode is configurable — auto (default), bypass permissions,
  accept edits, plan, manual, never ask.
- Remote Control can be turned off to keep the session local to this
  instance.
- Optional Docker access for maintenance work (disk usage, image cleanup,
  app state), available when you turn Protection mode off. Everything else
  works with Protection mode left on.
