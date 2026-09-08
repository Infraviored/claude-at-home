# Changelog

## 1.3.1

Fixes from a review of everything since 1.0.0. None of them were visible on
a healthy system; all of them would have bitten eventually.

- The usage sensors could stop updating entirely if the API left a reset
  time out of its answer, and the 7-day percentage could end up holding a
  timestamp instead of a number.
- A token refresh that succeeded could still be reported as a failure.
- The sign-in notification is re-posted periodically, so it is not lost for
  good if Home Assistant restarts while the prompt is up.
- The sign-in link can no longer pick up stray characters from the terminal.
- Skills you installed yourself are left alone even when they are symlinks,
  and links to skills a previous version shipped are cleaned up.
- The seconds-until-reset attribute is gone from the usage sensors; it
  changed every poll, which defeated the write deduplication. The
  `sensor.claude_5h_resets_at` / `sensor.claude_7d_resets_at` entities carry
  the same information.

## 1.3.0

- When Claude asks you to sign in again, the sign-in link is posted as a
  Home Assistant notification, where it is tappable. The Home Assistant app
  does not let you select text in the terminal, so the link was previously
  readable but impossible to open from a phone. Turn off with the new
  `login_notification` option.

## 1.2.0

- Publish Claude's account usage as six Home Assistant sensors: usage in the
  5-hour, 7-day and extra windows, a timestamp for when each window resets,
  and a last-updated diagnostic. Put them on a dashboard, or automate on
  them. Off unless you turn the new `usage_sensors` option on.
- Sensors are only written when their value changes, so a value that holds
  still does not fill the recorder with identical states. Reset times are
  rounded to the minute for the same reason.

## 1.1.0

- Ship the [Home Assistant agent skills][ha-skills], so Claude knows Home
  Assistant's own conventions - native constructs over templates, helper
  selection, automation modes, Zigbee button patterns, dashboard
  configuration, safe refactoring - instead of guessing them. They are
  updated along with the app, and your own skills are never touched.

[ha-skills]: https://github.com/homeassistant-ai/skills

## 1.0.3

- Create an SSH key on first boot and print the public key in the log, so
  pushing to Git only takes pasting it into your Git host. Previously you
  had to ask Claude to generate one.

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
