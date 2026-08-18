# Changelog

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
