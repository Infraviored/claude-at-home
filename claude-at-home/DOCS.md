# Home Assistant App: Claude at Home

Runs [Claude Code][claude-code] as a persistent session inside Home
Assistant, reachable as a terminal in your dashboard. Claude can read and
edit your HA configuration, so you can ask it to write automations, explain
an entity, or clean up YAML — in place, on the running system.

## How to use

1. Install and start the app.
2. Open **Claude at Home** in the sidebar. If it isn't there, turn on
   **Show in sidebar** on the app's Info page — Home Assistant resets that
   switch whenever an app is installed or updated. The **Open Web UI**
   button on that page always works too.
3. On first start you'll be dropped into Claude's login flow. It prints a
   URL — open it in a browser, sign in, and paste the code back into the
   terminal. That's the only manual step, and only once: credentials live
   in the app's persistent storage from then on.
4. Talk to Claude. The session stays alive in the background whether or not
   the browser tab is open.

## What survives what

Credentials, conversation history and Claude's own self-updates are stored
in the app's persistent volume, so they survive app restarts, rebuilds and
Home Assistant reboots. After the first login you should never have to log
in again.

If the session ever dies, it is restarted automatically and resumed with
its prior conversation.

## Configuration

```yaml
session_name: claude-at-home
permission_mode: auto
remote_control: true
usage_sensors: false
login_notification: true
```

Changing any of these takes effect when the app restarts.

### Option: `session_name`

Name of the tmux session holding Claude, and the name it registers for
Remote Control. Change only if it clashes with something else.

### Option: `permission_mode`

How Claude handles actions that would normally need your approval:

- **auto** (default) — works unattended, but screens every tool call for
  risky actions and prompt injection first. Safe ones run; risky ones are
  blocked and Claude looks for another way. Best fit for something running
  in your home unsupervised. Sessions cost slightly more.
- **bypass permissions** — acts without asking and without those checks.
  Fastest, and the largest grant of authority: Claude can change and
  delete things in your configuration with nothing in the way.
- **accept edits** — auto-accepts file edits, asks about everything else.
- **plan** — works out what it would do, without making changes.
- **manual** — asks before anything consequential.
- **never ask** — never prompts.

*auto* and *bypass permissions* are the two that keep working with nobody
watching. The others stop and wait for an answer at some point, so someone
has to be at the terminal for work to continue.

### Option: `remote_control`

Lets you drive this session from the Claude apps and claude.ai instead of
only from the terminal here. Turn it off to keep the session local to this
Home Assistant instance.

### Option: `usage_sensors`

Publishes how much of your Claude plan is used as Home Assistant sensors,
refreshed every five minutes:

| Entity | |
|---|---|
| `sensor.claude_5h_usage` | percent of the 5-hour window used |
| `sensor.claude_7d_usage` | percent of the 7-day window used |
| `sensor.claude_extra_usage` | percent of extra usage, if your plan has any |
| `sensor.claude_5h_resets_at` | when the 5-hour window turns over |
| `sensor.claude_7d_resets_at` | when the 7-day window turns over |
| `sensor.claude_usage_last_updated` | when the numbers were last refreshed — if it goes stale, the poller is down |

The reset times are rounded to the minute and only written when they
actually move — the API reports them as *now plus what is left*, so the raw
value jitters by fractions of a second on every poll and would otherwise
fill your history with meaningless changes. They are timestamp entities, so
a countdown card or a template can point straight at them, and the rounded
value is mirrored as a `resets_at` attribute on the usage sensors. Nothing
is declared in YAML —
the entities appear on their own once you have logged in. Turn the option off
and they stop updating; delete them from the entity registry to remove them.

There is deliberately no "window elapsed" sensor: it is derivable at display
time from the reset timestamp and the fixed window length (5h = 18000s,
7d = 604800s).

The numbers come from your Claude account, not from this app, so they cover
everything on the account, not just what happened here.

### Option: `login_notification`

Claude signs you out every so often, and asks you to open an OAuth link and
paste back a code. That link is printed in the terminal — where the Home
Assistant app will not let you select text, so on a phone it can be read but
not opened.

With this on, the link is also posted as a notification, where it is an
ordinary tappable link. Sign in, then paste the code back into the terminal;
pasting works fine, it is only copying out that does not. The notification
clears itself once the prompt is gone.

Anyone who can open your Home Assistant can also open that link and complete
the sign-in into your Claude account. On a normal single-household instance
that is the same person; on a shared one, turn this off.

## Access and permissions

The terminal is bound to Home Assistant's internal interface only and is
served exclusively through authenticated ingress. It opens no port, runs no
SSH server, and is not reachable from your LAN or the internet directly.

By default Claude runs here in *auto* mode (see `permission_mode` above):
it acts on your configuration without stopping to ask, while screening
each step for risky actions. That is what makes it useful for this job,
and it is still a real grant of authority — it can change and delete
things in your Home Assistant config. Keep backups, as you would for
anything that edits your config.

### Protection mode

The app asks for your Home Assistant configuration, the Home Assistant and
Supervisor APIs, and the Docker API. It does not ask for host networking,
hardware, or kernel access.

The Docker API is the one that Protection mode gates, and it is what lets
Claude act as a maintenance assistant: see which apps are running, find
what is eating your disk, clean up unused images.

- **Protection mode on** (the default) — Docker access is blocked.
  Everything else works: Claude reads and edits your configuration, calls
  Home Assistant services, restarts things through the Supervisor API.
- **Protection mode off** — Docker access works too. Home Assistant will
  warn you that this grants full access to the system, and that warning is
  accurate. Only turn it off if you want the maintenance capabilities.

Leave it on unless you specifically want the Docker features.

## Bundled Home Assistant skills

The app ships the [Home Assistant agent skills][ha-skills] — a knowledge
pack that teaches Claude Home Assistant's own conventions rather than
letting it guess: native constructs over templates, which helper to pick,
automation modes, Zigbee button patterns, YAML-only integration management,
dashboard configuration and safe refactoring.

Nothing to install or enable. The skills are baked into the image and
linked into `~/.claude/skills` on every boot, so updating the app updates
them too. Skills you add yourself are never overwritten — if one of yours
carries the same name, yours wins and the log says so.

They are MIT licensed and vendored unmodified from
[homeassistant-ai/skills][ha-skills].

[ha-skills]: https://github.com/homeassistant-ai/skills

## Pushing to Git over SSH

Your Home Assistant configuration is probably a Git repository, and Claude
can commit to it. Pushing over SSH needs one paste from you.

The app creates its own SSH key on first boot and prints the public half in
its **Log** tab, like this:

```
[INFO] SSH public key - add this to GitHub to let Claude push:
[INFO] ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... claude-at-home
```

Copy that line into your Git host — on GitHub either as a deploy key on the
one repository (Settings, Deploy keys, *Allow write access*), or as an
account SSH key if Claude should reach several repositories. A deploy key is
the narrower choice.

That is the whole setup. The key, the `known_hosts` entries for GitHub,
GitLab and Bitbucket, and Claude's Git config all live in the app's
persistent storage, so this survives restarts, rebuilds and updates. Only an
uninstall removes them.

If you would rather not scroll the log, ask Claude in the terminal: it can
read the key, set your commit name and email, and test the connection with
`ssh -T git@github.com`.

Note that the private key sits unencrypted in that storage — anyone with
Docker access to your Home Assistant host can read it. Scope the key to what
Claude actually needs to reach.

## Troubleshooting

**The sidebar entry is missing.** Turn on *Show in sidebar* on the app's
Info page. Home Assistant resets that switch on every install and update.

**"The app is starting, this can take some time…" never goes away.** Check
the app's log. The terminal is only served once the Claude session exists;
if the session is failing to start you will see why there.

**It asks me to log in again.** Credentials live in the app's persistent
storage, so this should only ever happen once. If it recurs, something is
wiping that storage — check that you are not reinstalling the app, which
creates a fresh volume, rather than restarting or updating it.

**I want a clean slate.** Uninstalling the app removes its storage,
including the login and the whole conversation history.

**Where is my conversation?** Inside the app's own storage, alongside the
Claude CLI. Nothing is written into your Home Assistant config directory
except changes Claude makes on purpose.

## Under the hood

The Claude CLI runs inside a tmux session, which is supervised by s6: if
Claude exits for any reason, the session is rebuilt and resumed with
`--continue`. A second supervised service runs `ttyd`, which attaches to
that same tmux session and serves it over ingress. Because both are
supervised independently, either can crash and recover without the other
noticing.

A fourth service watches the terminal for a sign-in prompt. It reads the
pane with `tmux capture-pane`, glues the hard-wrapped URL back together and
posts it through the same Core API proxy.

Usage numbers are fetched by a third supervised service. It reads the OAuth
token from the app's own storage — Home Assistant Core runs in a separate
container and cannot see that file, which is why this cannot be a native
Home Assistant sensor — and pushes only the derived percentages through the
Supervisor's Core API proxy, authenticated with the app's own token. The
token itself never leaves the app.

The bundled skills live in the image at `/opt/ha-skills`, and a startup
task links them into the persistent volume. Linking rather than copying is
what keeps them current across updates while leaving your own skills
untouched.

The app's persistent volume holds the CLI, its credentials and its history,
which is what lets the session survive rebuilds and updates rather than
just restarts.

[claude-code]: https://claude.com/claude-code
