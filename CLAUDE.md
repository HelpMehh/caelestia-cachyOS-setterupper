# caelestia-cachyOS-setterupper

An installer and maintenance tool that turns a fresh **CachyOS (Hyprland
edition)** install into a configured **Caelestia** desktop. Maintainer:
HelpMehh on GitHub. It's written for the maintainer and beginner friends, **on
any hardware**. CachyOS's Hyprland edition is the only requirement.

## How it fits together

- **Two-repo design.** This public repo is the *machinery*. Each user's
  personal settings live in their own **private config repo**, which *is*
  `~/.config/caelestia`. It holds `extras.json`, `machines/<hostname>.lua`,
  `setup-answers`, the lock video (`assets/lockscreen.mp4`) and wallpapers.
  Personal values are read at runtime from `extras.json`.
- **Install:** `curl -fsSL https://raw.githubusercontent.com/HelpMehh/caelestia-cachyOS-setterupper/main/install.sh | bash`,
  run as the normal user with no sudo. It installs itself to
  `/usr/local/lib/caelestia-setup` (root-owned) and adds the `caelestia-setup`
  command.
- **Modes:** install, update, check, monitors, save, backup, patch, unpatch
  (dispatched at the bottom of `install.sh`).
- **Updates:** users should always update with `caelestia-setup update`, never
  with `pacman -Syu` or `paru` on their own. It doesn't cover firmware
  (`fwupdmgr`), Flatpaks or apps that update themselves.
- The scripts are bash (`set -Eeuo pipefail`). The README is the user-facing
  documentation, so keep it in sync with behaviour changes.

## Rules

- **This repo is public.** Never commit personal details, network details
  (addresses, host names, domains, a person's own ports or set-up) or
  anything from a private config repo. That applies to code, docs, context files and plans.
  Write lessons generically ("dual-boot installs can…", not "my machine…").
- **Hard-code as little as possible.** It must work on any hardware and with
  any user name. Detect GPUs, monitors and installed apps instead of assuming
  them.
- **Packages:** install only desktop-related packages. Apps referenced by a
  user's settings are offered only when they're in the official or CachyOS
  repos.
- **Installer questions:** few, simple yes/no, each with a safe default.
- **As little bloatware as possible:** CachyOS's own Noctalia shell, and the
  apps that only came with it, are removed.
- **Editing user files:** add lines only if they're missing. Never overwrite a
  user's file wholesale.

## Workflow

- Claude Code works in a sandbox as a separate Linux user. The repo there is a
  plain clone with **no GitHub remote and no credentials, on purpose.**
- **Never commit and never push.** The maintainer commits every change
  themselves, using lazygit in LazyVim, because writing the commit message
  makes them understand the change. Leave finished work uncommitted and end
  each task with a short summary of what changed and why, per file, so they
  can review the diff and write a good message.
- The maintainer then pulls into their own clone with `git pull --ff-only`,
  pushes to GitHub, and runs `caelestia-setup update`.
- The maintainer may push into the sandbox repo
  (`receive.denyCurrentBranch updateInstead`). That only works when the
  working tree is **clean**. If a task starts with uncommitted changes, point
  that out before starting.
- **Versions** are counted per change set. **Latest released: v18.** Mention
  the version when summarising a change set, and add an entry to
  `CHANGELOG.md` for each new one.
- **One conversation per task or sub-task.** For larger changes, one
  conversation writes a plan to `.claude/plans/<topic>.md` (context plus
  numbered steps). The maintainer reviews it, then each step gets its own
  conversation.
  - The plan is committed together with the first step's changes.
  - The last step deletes the plan, after its lasting lessons have been moved
    into the context files. Git history keeps the plan.
  - At the start of a step, read the plan and check which steps the code and
    git log show as done.
- **Don't use Claude's memory for this project.** Everything project-related
  goes into this file or `.claude/context/`, so it travels with the repo. Don't
  read anything outside the project directory unless the task requires it.

## Working with the maintainer

- They're still learning Linux, so explain what commands and changes do as you
  go.
- They use the **fish** shell. Commands for them to run must work in fish:
  `set -x X y` instead of `export X=y`, no bash-only syntax such as
  `VAR=$(…)` assignments or `for …; do … done`. Wrap bash snippets in
  `bash -c '…'` if needed.
- **Push back** when a request or decision looks poor, risky or more complex
  than needed. Say why and suggest a better option. Ask when unsure.

## Recording what was learned

When asked to record learnings (usually at the end of a conversation):

1. Record only what's useful later and **not** obvious from the code or git
   history: decisions and their reasons, gotchas, findings from debugging, test
   results, open questions.
2. **Edit the relevant existing file** in place. Merge new facts into what's
   there, rewrite statements that are now wrong, and delete what's stale, so
   the files don't fill up with noise or contradictions. Don't just append.
   Create a new topic file only when nothing fits, and add it to the index
   below.
3. Facts every task needs go here in `CLAUDE.md`. Keep this file short.
4. Update `CHANGELOG.md` for released change sets and `backlog.md` /
   `testing.md` for status changes.
5. Check that nothing personal or network-specific went in, then show the
   maintainer the diff.

## Context index (`.claude/context/`)

Read a file when the task touches its subject.

| File | Read when |
|---|---|
| `design-decisions.md` | Changing shell patches, login/lock at boot, monitors, browser theming, colour scheme, Discord or special-workspace grids. Explains *why* they work the way they do. |
| `sunshine.md` | Anything to do with Sunshine, game streaming, pairing or remote connections, the virtual display, ufw rules, or idle/lock/suspend behaviour. |
| `nvidia-browsers.md` | Adding NVIDIA-specific steps, or debugging Chrome/Brave/WebKit rendering or video. |
| `gotchas.md` | Debugging, touching the `update` flow or self-update, special-workspace toggles, SSH, dual-boot, disk or boot-speed issues. |
| `testing.md` | Testing a change, planning a test run, or after a fresh install exposed bugs. |
| `backlog.md` | Choosing the next task or planning a new version. |

`CHANGELOG.md` (repo root, public) lists what each version changed.
