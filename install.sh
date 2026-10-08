#!/usr/bin/env bash
#
# caelestia-setup — the Caelestia desktop on CachyOS, set up in one go.
#
# First install (CachyOS with its Hyprland desktop is the only requirement):
#   curl -fsSL https://raw.githubusercontent.com/HelpMehh/caelestia-default-config/main/install.sh | bash
# or, from a copy of this folder:
#   bash install.sh
#
# Afterwards the same script is installed as the `caelestia-setup` command:
#   caelestia-setup update      update the system, Caelestia and this set-up
#                               (use it instead of "pacman -Syu" or "paru")
#   caelestia-setup save        upload your settings to your private GitHub repo
#   caelestia-setup backup      set that private repo up (once)
#   caelestia-setup check       test that everything is in place
#   caelestia-setup monitors    save this computer's monitor layout
#   caelestia-setup install     run the installer again (safe to repeat)
#   caelestia-setup unpatch     remove the shell additions (if the lock screen
#                               or bar misbehaves); "patch" puts them back
#
# What the installer does, in order:
#   1. offers to bring back settings you saved earlier, then asks a few
#      questions (browser, Sunshine, lock at boot, extra apps)
#   2. installs Caelestia with its own installer (`caelestia install`)
#   3. adds the lock-screen video, keyring unlock and monitor fixes to the
#      shell, and a pacman hook that re-adds them after every shell update
#   4. sets up the parts you chose
#   5. replaces CachyOS's Noctalia shell and login screen
#
# Answers can be given up front, for unattended runs:
#   CS_BROWSER=chrome CS_SUNSHINE=yes CS_LOCK_AT_BOOT=no CS_COMPONENTS=nvim \
#       bash install.sh --yes
#
# Nothing personal lives in this repository. Your own settings are the files
# in ~/.config/caelestia, which this script creates if missing and otherwise
# leaves alone.

set -Eeuo pipefail

REPO_URL="${CAELESTIA_SETUP_REPO:-https://github.com/HelpMehh/caelestia-default-config.git}"
LIB=/usr/local/lib/caelestia-setup
SHELL_DIR=/etc/xdg/quickshell/caelestia
HOOK=/etc/pacman.d/hooks/caelestia-setup-patch.hook
SUDOERS=/etc/sudoers.d/caelestia-setup-browser
PATCH_STATUS=/var/lib/caelestia-setup/patch-status.json
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
CFG="$CONFIG_HOME/caelestia"
# The answers to the installer's questions are kept with your settings, so a
# restored config also restores them. (Earlier versions kept them in STATE_DIR.)
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia-setup"
ANSWERS="$CFG/setup-answers"
DOTS_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/dots-state.json"

# Caelestia's optional parts that can be chosen at install (see its manifest).
OPTIONAL_COMPONENTS=(nvim spotify vscodium vscode zed zen discord todoist)

ASSUME_YES=0
SUDO_KEEPALIVE_PID=""

# ---------------------------------------------------------------------------
# Output and prompts
# ---------------------------------------------------------------------------

log()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

on_error() {
    printf '\n\033[1;31m[fail]\033[0m Stopped at line %s. Nothing after that point was done.\n' "$1" >&2
    printf '       Fix the problem above, then run the same command again: every step is safe to repeat.\n' >&2
}

cleanup() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    [[ -n "${CAELESTIA_SETUP_TMP:-}" && -d "${CAELESTIA_SETUP_TMP:-}" ]] && rm -rf "$CAELESTIA_SETUP_TMP" || true
}

trap 'on_error $LINENO' ERR
trap cleanup EXIT

# Questions are read from the terminal, not stdin, so they also work when the
# script itself arrives through a pipe (curl ... | bash).
tty_read() {
    local reply=""
    IFS= read -r reply </dev/tty || reply=""
    printf '%s' "$reply"
}

# ask_yn "Question" default(yes|no) -> prints yes or no
ask_yn() {
    local q=$1 def=$2 hint reply
    if (( ASSUME_YES )); then printf '%s' "$def"; return; fi
    [[ "$def" == yes ]] && hint="[Y/n]" || hint="[y/N]"
    while true; do
        printf '\033[1;36m ?\033[0m %s %s ' "$q" "$hint" >/dev/tty
        reply=$(tty_read)
        case "${reply,,}" in
            "")      printf '%s' "$def"; return ;;
            y|yes)   printf 'yes'; return ;;
            n|no)    printf 'no'; return ;;
            *)       printf '   Please answer y or n.\n' >/dev/tty ;;
        esac
    done
}

confirm() { [[ "$(ask_yn "$1" "${2:-yes}")" == yes ]]; }

# Truthy values for CS_* variables.
is_yes() { case "${1,,}" in y|yes|true|1|on) return 0 ;; *) return 1 ;; esac; }

answer_get() {  # answer_get KEY -> saved answer from an earlier run, if any
    if [[ ! -f "$ANSWERS" && -f "$STATE_DIR/answers" && -d "$CFG" ]]; then
        mv "$STATE_DIR/answers" "$ANSWERS"
        rmdir "$STATE_DIR" 2>/dev/null || true
    fi
    [[ -f "$ANSWERS" ]] || return 0
    sed -n "s/^$1=//p" "$ANSWERS" | tail -n 1
}

answer_set() {  # answer_set KEY VALUE
    mkdir -p "$CFG"
    local tmp
    tmp=$(mktemp "$CFG/.answers.XXXXXX")
    { grep -v "^$1=" "$ANSWERS" 2>/dev/null || true; printf '%s=%s\n' "$1" "$2"; } > "$tmp"
    mv "$tmp" "$ANSWERS"
}

in_session() { [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && hyprctl version >/dev/null 2>&1; }
installed()  { pacman -Qq "$1" >/dev/null 2>&1; }
is_laptop()  { compgen -G '/sys/class/power_supply/BAT*' >/dev/null; }

# The name of Sunshine's user service differs between releases, so ask the
# installed package what it ships.
sunshine_unit() {
    pacman -Qlq sunshine 2>/dev/null | sed -n 's|.*/systemd/user/\(.*\.service\)$|\1|p' | head -n 1
}

pac_flags() { if (( ASSUME_YES )); then printf '%s\n' --noconfirm; fi; }
aur_flags() { if (( ASSUME_YES )); then printf '%s\n' --noconfirm --skipreview; fi; }

pac_install() {  # official packages
    local flags; mapfile -t flags < <(pac_flags)
    sudo pacman -S --needed "${flags[@]}" "$@"
}

aur_install() {  # a fixed, named list only -- never a name read from a config file
    local flags; mapfile -t flags < <(aur_flags)
    paru -S --needed "${flags[@]}" "$@"
}

json_edit() {  # json_edit FILE 'python statements working on dict d'
    python3 - "$1" "$2" <<'PY'
import json, os, sys
path, code = sys.argv[1:3]
try:
    with open(path) as f:
        d = json.load(f)
    if not isinstance(d, dict):
        raise ValueError
except FileNotFoundError:
    d = {}
except ValueError:
    sys.exit(f"{path} is not valid JSON; fix or remove it and run this again")
before = json.dumps(d, sort_keys=True)
exec(code)
if json.dumps(d, sort_keys=True) != before or not os.path.exists(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=4)
        f.write("\n")
    os.replace(tmp, path)
PY
}

lock_ipc() { qs -c caelestia ipc call lock "$@" 2>/dev/null; }

wait_for_shell() {  # up to 20 seconds
    local _
    for _ in $(seq 1 100); do
        if lock_ipc isLocked >/dev/null; then return 0; fi
        sleep 0.2
    done
    return 1
}

restart_shell() {
    in_session || return 0
    command -v caelestia >/dev/null || return 0
    caelestia shell -k >/dev/null 2>&1 || true
    sleep 1
    caelestia shell -d >/dev/null 2>&1 || warn "Could not restart the shell; log out and in again."
    ensure_sunshine
}

# Sunshine quits when it cannot create its tray icon, and the tray is part of
# the shell. So whenever the shell has been restarted, start Sunshine again if
# it is switched on but no longer running.
ensure_sunshine() {
    in_session || return 0
    local unit
    unit=$(sunshine_unit)
    [[ -n "$unit" ]] || return 0
    systemctl --user is-enabled --quiet "$unit" 2>/dev/null || return 0
    wait_for_shell || return 0
    sleep 1
    systemctl --user is-active --quiet "$unit" 2>/dev/null && return 0
    systemctl --user start --no-block "$unit" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Getting the files: from the folder this script is in, or from GitHub
# ---------------------------------------------------------------------------

SRC=""
locate_source() {
    local self="${BASH_SOURCE[0]:-}"
    if [[ -n "$self" && -f "$self" ]]; then
        local dir
        dir=$(cd "$(dirname "$(readlink -f "$self")")" && pwd)
        if [[ -f "$dir/patches/patch_shell.py" ]]; then
            SRC=$dir
            return 0
        fi
    fi
    return 1
}

bootstrap() {
    # Reached when the script was piped in (curl ... | bash): fetch the whole
    # repository and carry on from there.
    command -v pacman >/dev/null || die "caelestia-setup needs CachyOS (pacman not found)."
    command -v git >/dev/null || sudo pacman -S --needed --noconfirm git
    local tmp
    tmp=$(mktemp -d)
    log "Downloading caelestia-setup"
    GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 "$REPO_URL" "$tmp/src" || die "Could not download $REPO_URL"
    # stdin is still the pipe this script came through; give the real run the
    # terminal so nothing it starts can swallow input meant for bash.
    if [[ -r /dev/tty ]]; then
        CAELESTIA_SETUP_TMP="$tmp" exec bash "$tmp/src/install.sh" "$@" </dev/tty
    fi
    CAELESTIA_SETUP_TMP="$tmp" exec bash "$tmp/src/install.sh" "$@" </dev/null
}

source_version() {
    git -C "$SRC" rev-parse HEAD 2>/dev/null || cat "$SRC/VERSION" 2>/dev/null || echo local
}

# ---------------------------------------------------------------------------
# The password store ("keyring")
#
# Apps keep saved passwords in the GNOME keyring. It only unlocks by itself
# at login when it is the keyring named "login", locked with your login
# password. On a fresh system no keyring exists yet, and the first app that
# needs one (GitHub's sign-in, your browser) makes you invent a password for
# a differently named keyring -- which then asks for that password after
# every login. Creating the login keyring first, with the password you type
# for sudo anyway, avoids all of that. The password is checked by sudo,
# handed to the keyring service on its standard input, and not stored.
# ---------------------------------------------------------------------------

needs_login_keyring() {
    command -v gnome-keyring-daemon >/dev/null || return 1
    [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || return 1
    # Any keyring already there: leave things as they are.
    ! compgen -G "${XDG_DATA_HOME:-$HOME/.local/share}/keyrings/*.keyring" >/dev/null
}

setup_login_keyring() {
    info "Type your password. It is checked, used once to set up your password store so"
    info "that it unlocks when you log in (apps then never ask for it), and not kept."
    local pw="" ok=0 attempt
    for attempt in 1 2 3; do
        printf '\033[1;36m ?\033[0m Password for %s: ' "$USER" >/dev/tty
        IFS= read -rs pw </dev/tty || pw=""
        printf '\n' >/dev/tty
        sudo -k
        if [[ -n "$pw" ]] && printf '%s\n' "$pw" | sudo -S -p '' -v 2>/dev/null; then
            ok=1
            break
        fi
        printf '   That password was not accepted.\n' >/dev/tty
    done
    if (( ! ok )); then
        pw=""
        die "sudo failed. Your user needs to be an administrator (in the 'wheel' group)."
    fi
    # Starts the keyring service unlocked (replacing a locked one that may be
    # running), which creates the login keyring with this password.
    printf '%s' "$pw" | gnome-keyring-daemon --replace --unlock --components=secrets >/dev/null 2>&1 || true
    pw=""
    sleep 1
    if [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/keyrings/login.keyring" ]]; then
        info "password store ready"
    else
        info "could not prepare the password store; an app may ask you to create one later"
    fi
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

preflight() {
    log "Checking this computer"

    [[ $EUID -ne 0 ]] || die "Run this as your normal user, not root. It asks for your password when needed."
    command -v pacman >/dev/null || die "caelestia-setup needs CachyOS (pacman not found)."

    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        id=$(. /etc/os-release && printf '%s' "${ID:-}")
        like=$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")
    fi
    if [[ "$id" != cachyos ]]; then
        if [[ "$id" == arch || " $like " == *" arch "* ]]; then
            warn "This is '$id', not CachyOS. It may work, but only CachyOS is tested."
            confirm "Continue anyway?" no || exit 0
        else
            die "This is '$id'. caelestia-setup only supports CachyOS."
        fi
    fi

    [[ -e /dev/tty ]] || (( ASSUME_YES )) || die "No terminal to ask questions on. Use --yes with CS_* variables."

    if needs_login_keyring && ! (( ASSUME_YES )) && [[ -r /dev/tty ]]; then
        setup_login_keyring
    else
        info "Asking for your password once, so later steps don't stall..."
        sudo -v || die "sudo failed. Your user needs to be an administrator (in the 'wheel' group)."
    fi
    (
        set +eE
        trap - ERR
        while true; do
            sudo -n true 2>/dev/null
            sleep 50
            kill -0 "$$" 2>/dev/null || exit 0
        done
    ) &
    SUDO_KEEPALIVE_PID=$!

    if ! command -v paru >/dev/null; then
        info "Installing paru (the AUR helper CachyOS provides)"
        sudo pacman -S --needed --noconfirm paru
    fi

    in_session || warn "Not inside a running Hyprland session: monitor set-up and a few desktop settings will be skipped. Run this again from a terminal on the desktop to finish them."
}

# ---------------------------------------------------------------------------
# Questions
# ---------------------------------------------------------------------------

BROWSER="" SUNSHINE="" LOCK_AT_BOOT="" COMPONENTS=""

ask_questions() {
    log "A few questions"
    info "Press Enter to accept the answer in capitals or [brackets]."

    # --- browser ----------------------------------------------------------
    BROWSER="${CS_BROWSER:-}"
    local def reply
    def=$(answer_get browser); def=${def:-firefox}
    if [[ -z "$BROWSER" ]]; then
        if (( ASSUME_YES )); then
            BROWSER=$def
        else
            cat >/dev/tty <<'EOF'

 Which web browser?
   1) Firefox  - Caelestia's default; follows the desktop colours
   2) Chrome   - follows the desktop colours; new tab page shows the wallpaper
   3) Brave    - follows the desktop colours
   4) Opera    - installed and set as default only
   5) none     - leave browsers alone
EOF
            while [[ -z "$BROWSER" ]]; do
                printf '\033[1;36m ?\033[0m Choose 1-5 [%s] ' "$def" >/dev/tty
                reply=$(tty_read)
                case "${reply,,}" in
                    "")         BROWSER=$def ;;
                    1|firefox)  BROWSER=firefox ;;
                    2|chrome)   BROWSER=chrome ;;
                    3|brave)    BROWSER=brave ;;
                    4|opera)    BROWSER=opera ;;
                    5|none)     BROWSER=none ;;
                    *)          printf '   Type a number from 1 to 5.\n' >/dev/tty ;;
                esac
            done
        fi
    fi
    case "$BROWSER" in firefox|chrome|brave|opera|none) ;; *) die "CS_BROWSER must be firefox, chrome, brave, opera or none." ;; esac

    # --- Sunshine ---------------------------------------------------------
    if [[ -n "${CS_SUNSHINE:-}" ]]; then
        is_yes "$CS_SUNSHINE" && SUNSHINE=yes || SUNSHINE=no
    else
        def=$(answer_get sunshine); def=${def:-no}
        (( ASSUME_YES )) || printf '\n Sunshine streams this desktop to a phone, tablet or TV (with the Moonlight app).\n' >/dev/tty
        SUNSHINE=$(ask_yn "Set up Sunshine?" "$def")
    fi

    # --- lock at boot -----------------------------------------------------
    if [[ -n "${CS_LOCK_AT_BOOT:-}" ]]; then
        is_yes "$CS_LOCK_AT_BOOT" && LOCK_AT_BOOT=yes || LOCK_AT_BOOT=no
    else
        def=$(answer_get lock_at_boot); def=${def:-no}
        if ! (( ASSUME_YES )); then
            cat >/dev/tty <<'EOF'

 Lock at boot: the computer logs you in by itself and shows Caelestia's lock
 screen straight away, in place of a separate login prompt. You still type
 your password. Your session is already running behind the lock screen, so
 choose "no" on a laptop or any computer other people can get at.
EOF
            is_laptop && printf ' This looks like a laptop: "no" is the safer answer.\n' >/dev/tty
        fi
        LOCK_AT_BOOT=$(ask_yn "Lock at boot?" "$def")
    fi

    # --- extra Caelestia apps ---------------------------------------------
    COMPONENTS="${CS_COMPONENTS-__unset__}"
    if [[ "$COMPONENTS" == __unset__ ]]; then
        def=$(answer_get components)
        if (( ASSUME_YES )); then
            COMPONENTS=$def
        else
            cat >/dev/tty <<EOF

 Caelestia can also install and theme these apps:
   ${OPTIONAL_COMPONENTS[*]}
 (nvim = Neovim editor, discord = the Equibop client for Discord)
EOF
            printf '\033[1;36m ?\033[0m Type the ones you want, separated by spaces [%s] ' "${def:-none}" >/dev/tty
            reply=$(tty_read)
            COMPONENTS=${reply:-$def}
        fi
    fi
    COMPONENTS=$(printf '%s' "$COMPONENTS" | tr ', ' '\n\n' | { grep -v '^none$' || true; } | sed '/^$/d' | sort -u | paste -sd, -)
    local c
    for c in ${COMPONENTS//,/ }; do
        [[ " ${OPTIONAL_COMPONENTS[*]} " == *" $c "* ]] || die "Unknown app '$c'. Choose from: ${OPTIONAL_COMPONENTS[*]}"
    done

    answer_set browser "$BROWSER"
    answer_set sunshine "$SUNSHINE"
    answer_set lock_at_boot "$LOCK_AT_BOOT"
    answer_set components "$COMPONENTS"
}

show_plan() {
    log "What will happen"
    if [[ -f "$DOTS_STATE" ]]; then
        info "- Caelestia is already installed: update the system and re-apply this set-up"
    else
        info "- update the system, then install Caelestia (its shell, tools and themes)"
        info "- replace CachyOS's Hyprland settings in ~/.config/hypr (no backup is kept)"
    fi
    info "- add the lock-screen video, keyring unlock and monitor fixes to the shell"
    info "- browser: $BROWSER"
    info "- Sunshine: $SUNSHINE"
    info "- lock at boot: $LOCK_AT_BOOT"
    info "- extra Caelestia apps: ${COMPONENTS:-none}"
    if installed noctalia || installed noctalia-greeter || installed cachyos-hypr-noctalia; then
        info "- replace the Noctalia login screen with a plain one, then uninstall Noctalia"
        info "  and the apps that only came with it (the list is shown before removal)"
    fi
    echo
    confirm "Go ahead?" yes || { info "Nothing was changed."; exit 0; }
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Qt has to be one version
# ---------------------------------------------------------------------------
# Qt, the toolkit the shell is built on, is published as many packages that
# only work together when all of them are the same version. Now and then the
# package servers hold a new Qt half-published: an update taken at that moment
# moves some of the packages and not the others, and nothing built on Qt
# starts until the rest arrive. So before a system update this looks at what
# the update would change, and skips it if Qt would end up mixed.

# Qt packages whose version is allowed to differ: data only, or (webengine) a
# browser engine the desktop does not use and which is often published later.
QT_FAMILY_SKIP='^qt6-(translations|doc|examples|webengine)$'

# qt_family -> "name version" for every installed package of Qt itself
# (recognised by its home page, so add-ons from other projects don't count).
qt_family() {
    local names
    names=$(pacman -Qq 2>/dev/null | { grep '^qt6-' || true; } | { grep -Ev -- "-git\$|$QT_FAMILY_SKIP" || true; })
    [[ -n "$names" ]] || return 0
    # shellcheck disable=SC2086
    LC_ALL=C pacman -Qi $names 2>/dev/null | awk '
        { key = $0; sub(/ *:.*/, "", key); val = $0; sub(/^[^:]*: */, "", val) }
        key == "Name"    { n = val }
        key == "Version" { v = val; sub(/^[0-9]+:/, "", v); sub(/-[^-]*$/, "", v) }
        key == "URL"     { if (val ~ /qt\.io/) print n, v }'
}

qt_is_mixed() {  # reads "name version" lines
    [[ $(awk 'NF { print $2 }' | sort -u | wc -l) -gt 1 ]]
}

# qt_describe TEMPLATE-FOR-THE-ODD-ONES, reading "name version" lines.
# Prints e.g. "qt6-declarative 6.12.0, the other 9 Qt packages 6.11.2".
qt_describe() {
    awk 'NF { ver[$1] = $2; count[$2]++; total++ }
        END {
            for (v in count) if (count[v] > most || (count[v] == most && ver["qt6-base"] == v)) { most = count[v]; common = v }
            for (n in ver) if (ver[n] != common) odd = odd (odd ? ", " : "") n " " ver[n]
            printf "%s, the other %d Qt package(s) %s\n", odd, count[common], common
        }'
}

# pending_upgrades -> "name newversion" for everything a system update would
# change. Works on a private copy of the package lists, so the system's own
# lists are not touched. Fails if it cannot look.
pending_upgrades() {
    local out="" rc=0
    if command -v checkupdates >/dev/null; then
        out=$(checkupdates 2>/dev/null) || rc=$?
        (( rc == 0 || rc == 2 )) || return 1      # 2: nothing to update
    elif command -v fakeroot >/dev/null; then
        local dbpath tmp
        dbpath=$(pacman-conf DBPath 2>/dev/null || echo /var/lib/pacman)
        tmp=$(mktemp -d)
        ln -s "${dbpath%/}/local" "$tmp/local"
        mkdir -p "$tmp/sync"
        cp "${dbpath%/}"/sync/*.db "$tmp/sync/" 2>/dev/null || true
        if ! fakeroot -- pacman -Sy --disable-sandbox --dbpath "$tmp" --logfile /dev/null >/dev/null 2>&1 \
            && ! fakeroot -- pacman -Sy --dbpath "$tmp" --logfile /dev/null >/dev/null 2>&1; then
            rm -rf "$tmp"
            return 1
        fi
        out=$(pacman -Qu --color never --dbpath "$tmp" 2>/dev/null || true)
        rm -rf "$tmp"
    else
        return 1
    fi
    # "name old -> new", possibly coloured; held-back packages end in [ignored].
    sed 's/\x1b\[[0-9;]*m//g' <<<"$out" | awk '$3 == "->" && $NF !~ /\]$/ { print $1, $4 }'
}

# qt_after PENDING -> the Qt packages as they would be after that update
qt_after() {
    { sed 's/^/P /' <<<"$1"; qt_family | sed 's/^/F /'; } | awk '
        $1 == "P" && NF == 3 { v = $3; sub(/^[0-9]+:/, "", v); sub(/-[^-]*$/, "", v); new[$2] = v }
        $1 == "F" { print $2, ($2 in new ? new[$2] : $3) }'
}

# When the installed Qt packages are already mixed: the command that puts the
# odd ones back, if the right versions are still in pacman's download cache.
qt_repair_hint() {
    local family=$1 common cache name files=() f
    common=$(awk 'NF { ver[$1] = $2; count[$2]++ }
        END { for (v in count) if (count[v] > most || (count[v] == most && ver["qt6-base"] == v)) { most = count[v]; common = v }
              print common }' <<<"$family")
    cache=$(pacman-conf CacheDir 2>/dev/null | head -n 1)
    cache=${cache:-/var/cache/pacman/pkg/}
    while read -r name; do
        f=$(compgen -G "${cache%/}/$name-$common-*.pkg.tar.zst" | sort -V | tail -n 1 || true)
        [[ -n "$f" ]] || return 1
        files+=("$f")
    done < <(awk -v c="$common" 'NF && $2 != c { print $1 }' <<<"$family")
    (( ${#files[@]} )) || return 1
    printf 'sudo pacman -U %s\n' "${files[*]}"
}

# qt_update_safe -> 0 when a system update can go ahead, 1 when it must wait
# (and says why). If it cannot look ahead, it lets the update go ahead as before.
QT_HELD=0
qt_update_safe() {
    [[ -z "${CS_SKIP_QT_CHECK:-}" ]] || return 0
    local now pending after hint
    now=$(qt_family)
    [[ -n "$now" ]] || return 0
    info "Looking at what the update would change..."
    if ! pending=$(pending_upgrades); then
        info "(could not look ahead; carrying on)"
        return 0
    fi
    after=$(qt_after "$pending")
    qt_is_mixed <<<"$after" || return 0

    QT_HELD=1
    if qt_is_mixed <<<"$now"; then
        warn "Qt's packages are at mixed versions on this computer, and the update would not fix that yet:"
        warn "    $(qt_describe <<<"$now")"
        warn "Qt only works when all its packages are the same version, so the bar and lock screen"
        warn "cannot start like this. It happens when an update is taken while a new Qt is half-published."
        if hint=$(qt_repair_hint "$now"); then
            warn "To put the odd package(s) back to the matching version:"
            warn "    $hint"
        else
            warn "Try again in a few hours, once the rest of the new Qt is available."
        fi
    else
        warn "A new Qt is only half-published right now. After an update this computer would have:"
        warn "    $(qt_describe <<<"$after")"
        warn "Qt only works when all its packages are the same version, so the bar and lock screen"
        warn "would stop starting. Nothing is wrong with this computer."
    fi
    return 1
}

# Installing sets up packages built on Qt, so it cannot go ahead around a
# half-published Qt. Checked first, before any questions.
step_qt_guard() {
    qt_update_safe && return 0
    die "Stopped before changing anything. Run this again in a few hours, and don't update the system by other means until then."
}

step_system_update() {
    log "Updating the system"
    local flags; mapfile -t flags < <(pac_flags)
    sudo pacman -Syu "${flags[@]}"
}

step_packages() {
    log "Installing what the additions need"
    # qt6-multimedia-ffmpeg is named first so pacman doesn't stop to ask which
    # playback backend to use.
    pac_install git python ffmpeg libnotify xdg-utils qt6-multimedia-ffmpeg qt6-multimedia
}

# Caelestia's shell needs the real Quickshell (the quickshell-git package).
# CachyOS's Noctalia desktop ships its own fork, noctalia-qs, which tells
# pacman it is the same thing -- so pacman accepts it as already installed,
# and Caelestia's shell then refuses to start on it.
FRESH_INSTALL=0

# ---------------------------------------------------------------------------
# Quickshell and Qt
#
# Quickshell (and Caelestia's shell plugin) are built on this computer against
# the Qt that is installed at that moment, and they use parts of Qt that
# change between versions. After a system update brings a newer Qt they can
# fail to start -- no bar, and no lock screen -- until they are rebuilt.
# So: remember which Qt they were built for, and rebuild when it changes.
# ---------------------------------------------------------------------------

QT_STAMP=/var/lib/caelestia-setup/quickshell-qt

# Qt's version without the packaging suffix: 6.11.2-3.1 -> 6.11.2
qt_version() { pacman -Q qt6-base 2>/dev/null | awk '{ sub(/-.*/, "", $2); print $2 }'; }

record_qt() {
    local v
    v=$(qt_version)
    [[ -n "$v" ]] || return 0
    sudo mkdir -p "$(dirname "$QT_STAMP")"
    printf '%s\n' "$v" | sudo tee "$QT_STAMP" >/dev/null
}

# pkg_date PACKAGE BUILDDATE|INSTALLDATE -> seconds since 1970, from pacman's records
pkg_date() {
    local ver
    ver=$(pacman -Q "$1" 2>/dev/null | awk '{ print $2 }')
    [[ -n "$ver" ]] || return 1
    awk -v field="%$2%" '$0 == field { getline; print; exit }' "/var/lib/pacman/local/$1-$ver/desc" 2>/dev/null
}

step_qt_rebuild() {
    [[ "$(pacman -Qq quickshell-git 2>/dev/null)" == quickshell-git ]] || return 0
    local now built_for
    now=$(qt_version)
    [[ -n "$now" ]] || return 0
    # A rebuild cannot work while Qt's own packages disagree with each other.
    if qt_is_mixed < <(qt_family); then return 0; fi
    built_for=$(cat "$QT_STAMP" 2>/dev/null || true)
    # Recorded and unchanged: nothing to do.
    [[ "$built_for" == "$now" ]] && return 0

    # Qt changed (or nothing was recorded yet, by an earlier version of this
    # script). Rebuild each of these that was built before this Qt was
    # installed; one that paru just rebuilt by itself is left alone.
    local qt_installed built p pkgs=()
    qt_installed=$(pkg_date qt6-base INSTALLDATE || true)
    for p in quickshell-git qt6-m3shapes-git caelestia-shell; do
        [[ "$(pacman -Qq "$p" 2>/dev/null)" == "$p" ]] || continue
        built=$(pkg_date "$p" BUILDDATE || true)
        if [[ "$built" =~ ^[0-9]+$ && "$qt_installed" =~ ^[0-9]+$ ]] && (( built >= qt_installed )); then continue; fi
        pkgs+=("aur/$p")
    done
    if (( ${#pkgs[@]} == 0 )); then
        record_qt
        return 0
    fi

    log "Rebuilding Quickshell for the new Qt"
    info "Qt is now $now${built_for:+ (it was $built_for)}. Without a rebuild the bar and lock screen"
    info "may not start. This takes a few minutes."
    local flags; mapfile -t flags < <(aur_flags)
    if paru -S --rebuild "${flags[@]}" "${pkgs[@]}"; then
        record_qt
        SHELL_CHANGED=1
        info "rebuilt for Qt $now"
    else
        warn "The rebuild did not finish. If the bar or lock screen fails to start, run:"
        warn "    paru -S --rebuild ${pkgs[*]}"
    fi
}

step_quickshell() {
    log "Quickshell"
    if installed noctalia-qs; then
        info "replacing Noctalia's Quickshell fork with the real one"
        sudo pacman -Rdd --noconfirm noctalia-qs
    fi
    # Compare the name: `pacman -Q` also answers for packages that merely
    # claim to provide quickshell-git.
    if [[ "$(pacman -Qq quickshell-git 2>/dev/null)" != quickshell-git ]]; then
        (( ASSUME_YES )) || info "paru shows the package's build script first. Press q to close it, then y to continue."
        # "aur/" matters: asked for plain quickshell-git, paru prefers a package
        # from CachyOS's repositories that claims the name -- noctalia-qs again.
        aur_install aur/quickshell-git
    fi
    local owner
    owner=$(pacman -Qqo "$(command -v qs 2>/dev/null || echo /usr/bin/qs)" 2>/dev/null || true)
    [[ "$owner" == quickshell-git ]] || die "The qs command belongs to '${owner:-nothing}', not quickshell-git. Caelestia's shell won't run on it."
    info "qs is the real Quickshell"
    step_qt_rebuild
}

step_caelestia() {
    log "Installing Caelestia"

    if ! command -v caelestia >/dev/null; then
        (( ASSUME_YES )) || info "paru shows each package's build script first. Press q to close it, then y to continue."
        aur_install caelestia-cli
    fi

    if [[ -f "$DOTS_STATE" ]]; then
        info "Caelestia is already installed; skipping its installer."
        return 0
    fi
    FRESH_INSTALL=1

    # CachyOS's own Hyprland settings would clash with Caelestia's.
    local hypr="$CONFIG_HOME/hypr"
    if [[ -d "$hypr" ]]; then
        if grep -qs 'CachyOS Hyprland Configuration' "$hypr/hyprland.lua" \
            || confirm "~/.config/hypr holds settings that aren't CachyOS's defaults. Delete them (no backup)?" no; then
            rm -rf "$hypr"
            info "removed the old ~/.config/hypr"
        else
            die "Move ~/.config/hypr out of the way yourself, then run this again."
        fi
    fi

    # Noctalia's bar would otherwise sit on top of Caelestia's until the next login.
    pkill -x noctalia 2>/dev/null || true

    local args=(--aur-helper paru --enable-components "uwsm${COMPONENTS:+,$COMPONENTS}")
    [[ "$BROWSER" == firefox ]] || args+=(--disable-components firefox)

    local bak="${CONFIG_HOME%/}.bak" had_bak=0
    [[ -e "$bak" ]] && had_bak=1

    if (( ASSUME_YES )); then
        caelestia install --noconfirm "${args[@]}"
        # --noconfirm also says yes to "back up the config directory?".
        if (( ! had_bak )) && [[ -d "$bak" ]]; then rm -rf "$bak"; fi
    else
        echo
        info "Caelestia's own installer runs next. It asks:"
        info "  'Back up the config directory?'  ->  answer n (it would copy all of ~/.config)"
        info "and paru will show build scripts again: q to close each, then y."
        echo
        caelestia install "${args[@]}"
    fi

    command -v caelestia >/dev/null || die "Caelestia did not install."
    [[ -d "$SHELL_DIR" ]] || die "Caelestia's shell is not in $SHELL_DIR; the package layout has changed."
}

step_system_files() {
    log "Installing caelestia-setup's own files"

    local version
    version=$(source_version)

    if [[ "$SRC" != "$LIB" ]]; then
        # A root-owned copy: these scripts are run by root (the pacman hook,
        # the browser colour helper) and by Sunshine, so they must not be
        # writable by ordinary programs.
        local stage
        stage=$(sudo mktemp -d /usr/local/lib/.caelestia-setup.XXXXXX)
        sudo cp -a "$SRC/." "$stage/"
        sudo rm -rf "$stage/.git"
        printf '%s\n' "$version" | sudo tee "$stage/VERSION" >/dev/null
        sudo chown -R root:root "$stage"
        sudo chmod -R u=rwX,go=rX "$stage"
        sudo find "$stage/bin" "$stage/system/browser-theme" "$stage/install.sh" -type f -exec chmod 0755 {} +
        sudo rm -rf "$LIB.old"
        [[ -d "$LIB" ]] && sudo mv "$LIB" "$LIB.old"
        sudo mv "$stage" "$LIB"
        sudo rm -rf "$LIB.old"
        info "installed to $LIB"
    fi

    printf '%s\n' '#!/bin/sh' "exec bash $LIB/install.sh \"\$@\"" | sudo tee /usr/local/bin/caelestia-setup >/dev/null
    sudo chmod 0755 /usr/local/bin/caelestia-setup
    info "command: caelestia-setup"

    sudo install -D -m 0644 "$LIB/system/caelestia-setup-patch.hook" "$HOOK"
    info "update hook: $HOOK"
}

SHELL_CHANGED=0
step_patch_shell() {
    log "Adding the lock-screen and monitor additions to the shell"
    local out
    out=$(sudo python3 "$LIB/patches/patch_shell.py" "$@")
    printf '%s\n' "$out"
    # "applied" means files were (re)written, e.g. after a shell upgrade put
    # the originals back; the running shell then needs a restart to load them.
    if grep -q ': applied' <<<"$out"; then SHELL_CHANGED=1; fi
}

# The additions change the lock screen, and a lock screen that fails to load
# is the one fault that can keep you out of your own desktop. So lock once
# for real, look for errors, and unlock again from here. If anything is off,
# take the additions back out and leave lock at boot off.
step_lock_selftest() {
    in_session || { info "Lock screen not tested (no running session). Test it yourself with Super+L before relying on it."; return 0; }
    log "Testing the lock screen"

    local problem="" errs=""
    if ! wait_for_shell; then
        problem="the shell did not start"
    elif [[ "$(lock_ipc isLocked)" == true ]]; then
        info "The screen is locked right now; skipping the test."
        return 0
    else
        info "The screen locks for a few seconds, then unlocks by itself. Don't type anything."
        sleep 2
        lock_ipc lock || true
        sleep 4
        [[ "$(lock_ipc isLocked)" == true ]] || problem="the lock screen did not come up"
        errs=$(timeout 5 qs -c caelestia log 2>/dev/null | tail -n 300 \
            | grep -E 'LockExtras|LockVideo|LockSurface' \
            | grep -iE 'error|not a type|unavailable|failed|cannot' | head -n 5 || true)
        if [[ -z "$problem" && -n "$errs" ]]; then problem="the shell reported errors in the lock screen"; fi
        lock_ipc unlock || true
        sleep 3
        if [[ "$(lock_ipc isLocked)" == true ]]; then
            problem=${problem:-"the lock screen did not unlock by itself"}
            warn "The screen may still be locked: type your password to unlock it."
        fi
    fi

    if [[ -z "$problem" ]]; then
        info "lock screen works"
        return 0
    fi

    warn "Lock screen test failed: $problem."
    [[ -n "$errs" ]] && printf '%s\n' "$errs" | sed 's/^/       /' >&2
    warn "Taking the shell additions back out so the normal lock screen keeps working."
    sudo python3 "$LIB/patches/patch_shell.py" --revert || true
    restart_shell
    if [[ "$LOCK_AT_BOOT" == yes ]]; then
        LOCK_AT_BOOT=no
        answer_set lock_at_boot no
        json_edit "$CFG/extras.json" "d.setdefault('lock', {})['atLogin'] = False"
        step_login
        warn "Lock at boot was turned off again."
    fi
    SELFTEST_FAILED=1
}
SELFTEST_FAILED=0

mode_patch() {
    log "Turning the shell additions on"
    sudo python3 "$LIB/patches/patch_shell.py" --enable
    restart_shell
    info "Test the lock screen now (Super+L). If it misbehaves: caelestia-setup unpatch"
}

mode_unpatch() {
    log "Removing the shell additions"
    sudo python3 "$LIB/patches/patch_shell.py" --revert
    restart_shell
    info "The shell is back to Caelestia's own files, and updates will leave it alone."
    info "Turn the additions back on with: caelestia-setup patch"
}

step_user_config() {
    log "Your settings (~/.config/caelestia)"
    mkdir -p "$CFG"

    # hypr-user.lua: must load the shared additions.
    local user_lua="$CFG/hypr-user.lua"
    if [[ ! -s "$user_lua" ]]; then
        cp "$LIB/defaults/hypr-user.lua" "$user_lua"
        info "created hypr-user.lua"
    elif ! grep -q 'caelestia-setup/hypr/base.lua' "$user_lua"; then
        local tmp
        tmp=$(mktemp)
        {
            printf '%s\n' '-- Shared caelestia-setup additions (monitor layout, lock at login, Sunshine). Keep this first.'
            printf '%s\n\n' "dofile(\"$LIB/hypr/base.lua\")"
            cat "$user_lua"
        } > "$tmp"
        cat "$tmp" > "$user_lua"
        rm -f "$tmp"
        info "added one line to the top of your hypr-user.lua (it loads the shared additions)"
    else
        info "hypr-user.lua already loads the shared additions"
    fi

    if [[ ! -e "$CFG/extras.json" ]]; then
        cp "$LIB/defaults/extras.json" "$CFG/extras.json"
        info "created extras.json (lock video, lock transparency, wallpaper on login)"
    fi
    local at_login=False
    [[ "$LOCK_AT_BOOT" == yes ]] && at_login=True
    json_edit "$CFG/extras.json" "d.setdefault('lock', {})['atLogin'] = $at_login"

    # Services such as Sunshine start with systemd's graphical-session.target.
    # A session started through uwsm reaches it by itself; a plain Hyprland
    # session needs this target, which bin/session-start activates. Hyprland
    # ships it when built with systemd support.
    if ! systemctl --user cat hyprland-session.target >/dev/null 2>&1; then
        mkdir -p "$CONFIG_HOME/systemd/user"
        cat > "$CONFIG_HOME/systemd/user/hyprland-session.target" <<'EOF'
[Unit]
Description=Hyprland session
Documentation=man:systemd.special(7)
BindsTo=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
EOF
        systemctl --user daemon-reload 2>/dev/null || true
        info "added hyprland-session.target (lets services start with the desktop)"
    fi

    # A wallpaper folder that travels with the config -- unless there is
    # already a collection in Caelestia's usual place.
    local pictures
    pictures=$(xdg-user-dir PICTURES 2>/dev/null || true)
    pictures=${pictures:-$HOME/Pictures}
    if [[ ! -d "$CFG/wallpapers" ]] && ! compgen -G "$pictures/Wallpapers/*" >/dev/null; then
        mkdir -p "$CFG/wallpapers"
        if [[ -f "$SHELL_DIR/assets/wallpaper.webp" ]]; then
            cp "$SHELL_DIR/assets/wallpaper.webp" "$CFG/wallpapers/caelestia.webp"
        fi
        info "created a wallpapers folder with Caelestia's default wallpaper: $CFG/wallpapers"
    fi
}

# Caelestia's installer starts everyone on its fixed "caelestia" colours.
# extras.json names the scheme this set-up should start with instead
# ("dynamic" = colours taken from the wallpaper). Only on a fresh install: a
# scheme picked later in the launcher must survive re-running this script.
# The colour scheme named in extras.json ("dynamic": colours follow the
# wallpaper) is applied once per computer. After that it is yours to change
# in the launcher, and this leaves it alone. Until it has worked once, every
# install and update tries again -- so an install that was interrupted and
# run a second time still ends up with the right colours.
SCHEME_MARK="$STATE_DIR/scheme-applied"

scheme_wanted() {
    python3 -c "import json; print(json.load(open('$CFG/extras.json')).get('scheme', 'dynamic'))" 2>/dev/null || echo dynamic
}

step_scheme() {
    [[ "${1:-}" == --write-default ]] && json_edit "$CFG/extras.json" "d.setdefault('scheme', 'dynamic')"
    [[ -e "$SCHEME_MARK" ]] && return 0
    command -v caelestia >/dev/null || return 0
    local want err=""
    want=$(scheme_wanted)
    [[ "$want" =~ ^[a-z0-9-]+$ ]] || return 0

    if [[ "$(caelestia scheme get -n 2>/dev/null)" != "$want" ]]; then
        # "dynamic" takes its colours from the wallpaper, and Caelestia refuses
        # to switch to it while no wallpaper has ever been set -- which is the
        # case on a fresh install. Set one first.
        local current_wall="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/wallpaper/path.txt"
        if [[ "$want" == dynamic && ! -s "$current_wall" ]]; then
            if [[ -d "$CFG/wallpapers" ]]; then
                caelestia wallpaper -n -r "$CFG/wallpapers" >/dev/null 2>&1 || true
            else
                caelestia wallpaper -n -r >/dev/null 2>&1 || true
            fi
            if [[ ! -s "$current_wall" ]]; then
                warn "No wallpaper could be set, so the colours can't follow one yet. Pick a wallpaper"
                warn "in the launcher, then run: caelestia-setup update"
                return 0
            fi
        fi
        err=$(caelestia scheme set -n "$want" 2>&1 >/dev/null) || true
        if [[ "$(caelestia scheme get -n 2>/dev/null)" != "$want" ]]; then
            err=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$err" | tail -n 1)
            warn "Could not switch to the '$want' colour scheme${err:+ ($err)}."
            warn "'caelestia-setup update' tries again; by hand it is: caelestia scheme set -n $want"
            return 0
        fi
        info "colour scheme: $want"
    fi
    mkdir -p "$STATE_DIR"
    : > "$SCHEME_MARK"
}

step_monitors() {
    in_session || { info "Skipping monitor set-up (no running session)."; return 0; }
    local host
    host=$(cat /etc/hostname 2>/dev/null || true)
    if [[ -n "$host" && -f "$CFG/machines/$host.lua" ]]; then
        info "Monitor layout for '$host' already saved; change it with: caelestia-setup monitors"
        return 0
    fi
    mode_monitors
}

mode_monitors() {
    log "Monitor layout"
    in_session || die "Run this from a terminal on the Hyprland desktop."

    local host
    host=$(cat /etc/hostname 2>/dev/null || true)
    [[ "$host" =~ ^[A-Za-z0-9._-]+$ ]] || die "Could not read this computer's name from /etc/hostname."

    local json
    json=$(hyprctl monitors -j)
    local count
    count=$(printf '%s' "$json" | python3 -c 'import json, sys; print(len(json.load(sys.stdin)))')

    mkdir -p "$CFG/machines"
    local out="$CFG/machines/$host.lua" order="" tries=0
    if (( count > 1 )) && ! (( ASSUME_YES )); then
        printf '\n Your screens, as Hyprland has them now:\n' >/dev/tty
        printf '%s' "$json" | python3 "$LIB/bin/monitor-layout" --list >/dev/tty
        cat >/dev/tty <<'EOF'
 Type the numbers the way the screens sit on your desk, left to right
 (for example: 2 1 3).
   A screen above the others: type the top row first, with "/" between the
   rows.   3 / 2 1    puts screen 3 above 2 and 1, centred.
           - 3 / 2 1  puts it above screen 1 only ("-" is an empty place).
   A screen turned on its side: add r or l to its number (2r). If its
   picture comes out upside down, use the other letter.
 If two screens look the same in this list, guess: if they end up swapped, run
 "caelestia-setup monitors" again.
EOF
        while :; do
            printf '\033[1;36m ?\033[0m Layout [one row, as listed] ' >/dev/tty
            order=$(tty_read)
            if printf '%s' "$json" | python3 "$LIB/bin/monitor-layout" "$order" > "$out.tmp" 2>"$out.err"; then
                break
            fi
            printf '   That did not work: %s\n' "$(cat "$out.err")" >/dev/tty
            tries=$((tries + 1))
            if (( tries >= 3 )); then
                warn "Keeping the screens in one row as listed; change it later with: caelestia-setup monitors"
                order=""
                break
            fi
        done
        rm -f "$out.err"
    fi

    printf '%s' "$json" | python3 "$LIB/bin/monitor-layout" "$order" > "$out.tmp" \
        || { rm -f "$out.tmp"; die "Could not work out a monitor layout."; }
    mv "$out.tmp" "$out"
    info "saved $out"
    hyprctl reload >/dev/null 2>&1 || true
    info "Applied. Each screen runs at its highest refresh rate; edit that file to fine-tune."
}

step_browser() {
    [[ "$BROWSER" == none ]] && return 0
    log "Browser: $BROWSER"

    local desktop="" cmd=""
    case "$BROWSER" in
        firefox) desktop=firefox.desktop;        cmd=firefox ;;
        chrome)  desktop=google-chrome.desktop;  cmd=google-chrome-stable; aur_install google-chrome ;;
        brave)   desktop=brave-browser.desktop;  cmd=brave;                aur_install brave-bin ;;
        opera)   desktop=opera.desktop;          cmd=opera;                aur_install opera ;;
    esac

    if command -v xdg-settings >/dev/null && [[ -f "/usr/share/applications/$desktop" ]]; then
        xdg-settings set default-web-browser "$desktop" 2>/dev/null \
            || xdg-mime default "$desktop" x-scheme-handler/http x-scheme-handler/https text/html \
            || warn "Could not set the default browser; set it by hand."
        info "$BROWSER is the default browser"
    fi

    # Super+W opens Caelestia's "browser" variable.
    local vars="$CFG/hypr-vars.lua"
    if [[ "$BROWSER" != firefox ]]; then
        if [[ ! -s "$vars" ]] || [[ "$(tr -d '[:space:]' < "$vars")" == "return{}" ]]; then
            printf 'return {\n    browser = "%s",\n}\n' "$cmd" > "$vars"
            info "Super+W now opens $BROWSER"
        elif ! grep -q "browser" "$vars"; then
            warn "To make Super+W open $BROWSER, add this line inside $vars:   browser = \"$cmd\","
        fi
    fi

    # Colours (and for Chrome the new tab picture) follow the wallpaper.
    if [[ "$BROWSER" == chrome || "$BROWSER" == brave ]]; then
        local rule_tmp
        rule_tmp=$(mktemp)
        printf '%s\n' "%wheel ALL=(root) NOPASSWD: $LIB/system/browser-theme" > "$rule_tmp"
        if sudo visudo -cf "$rule_tmp" >/dev/null; then
            sudo install -m 0440 -o root -g root "$rule_tmp" "$SUDOERS"
            info "browser colours can follow the wallpaper (rule: $SUDOERS)"
        else
            warn "The sudo rule for browser colours failed its check; skipped."
        fi
        rm -f "$rule_tmp"

        json_edit "$CFG/cli.json" "
d.setdefault('wallpaper', {})['postHook'] = '$LIB/bin/wallpaper-hook'
d.setdefault('theme', {})['enableChromium'] = False"
        info "cli.json: wallpaper hook set, Caelestia's own browser theming turned off"
        [[ "$BROWSER" == chrome ]] && info "For the new tab picture: in Chrome choose 'Customise Chrome' and upload any image once."
    fi
    return 0
}

step_sunshine() {
    [[ "$SUNSHINE" == yes ]] || return 0
    log "Sunshine"

    # CachyOS has Sunshine in its own repositories. An earlier version of this
    # script added Sunshine's third-party package source; take that out again.
    if grep -q '^\[lizardbyte\]$' /etc/pacman.conf; then
        sudo sed -i '/^\[lizardbyte\]$/,/^Server = https:\/\/github\.com\/LizardByte\/pacman-repo/d' /etc/pacman.conf
        sudo rm -f /var/lib/pacman/sync/lizardbyte.db /var/lib/pacman/sync/lizardbyte.db.sig
        info "removed the LizardByte package source from /etc/pacman.conf (not needed on CachyOS)"
    fi
    if ! pacman -Si sunshine >/dev/null 2>&1; then
        warn "No 'sunshine' package in this system's repositories; skipping Sunshine."
        return 0
    fi
    pac_install sunshine

    # Capture straight from Hyprland (no screen picker on every start), and
    # swap to a virtual display sized to the device around every stream.
    local conf="$CONFIG_HOME/sunshine/sunshine.conf"
    mkdir -p "$(dirname "$conf")"
    touch "$conf"
    local prep="global_prep_cmd = [{\"do\":\"$LIB/bin/sunshine-vd-start\",\"undo\":\"$LIB/bin/sunshine-vd-stop\"}]"
    sed -i -e '/^capture *=/d' -e '/^global_prep_cmd *=/d' "$conf"
    printf '%s\n%s\n' 'capture = wlr' "$prep" >> "$conf"
    info "sunshine.conf: capture = wlr, virtual display around every stream"

    local unit
    unit=$(sunshine_unit)
    systemctl --user daemon-reload 2>/dev/null || true
    if [[ -n "$unit" ]] && systemctl --user enable "$unit" >/dev/null 2>&1; then
        if in_session; then systemctl --user restart "$unit" 2>/dev/null || true; fi
        info "$unit enabled (starts with the desktop)"
    else
        warn "Could not enable Sunshine's service (${unit:-not found in the package}); start Sunshine from the app launcher."
    fi

    # Let devices on the home network reach it, and nobody else.
    if systemctl is-active --quiet ufw 2>/dev/null; then
        local net
        for net in 192.168.0.0/16 10.0.0.0/8 172.16.0.0/12; do
            sudo ufw allow from "$net" to any port 47984,47989,48010 proto tcp comment 'Sunshine' >/dev/null
            sudo ufw allow from "$net" to any port 47998:48000,48002,48010 proto udp comment 'Sunshine' >/dev/null
        done
        info "firewall: Sunshine's ports opened for home-network addresses only"
    fi

    info "Finish in a browser: open https://localhost:47990 (accept the certificate warning),"
    info "create Sunshine's username and password, then pair each device with its PIN."
}

step_login() {
    log "Login screen"

    if [[ "$(systemctl is-enabled greetd.service 2>/dev/null)" != enabled ]]; then
        info "This computer doesn't use greetd for logging in; leaving its login screen alone."
        [[ "$LOCK_AT_BOOT" == yes ]] && warn "Lock at boot needs automatic login, which I only set up for greetd."
        return 0
    fi

    local session=""
    local f
    for f in /usr/share/wayland-sessions/hyprland-uwsm.desktop /usr/share/wayland-sessions/hyprland.desktop; do
        if [[ -f "$f" ]]; then
            session=$(sed -n 's/^Exec=//p' "$f" | head -n 1)
            break
        fi
    done
    if [[ -z "$session" || "$session" == *'"'* || "$session" == *'\'* ]]; then
        warn "Couldn't find how Hyprland is started; leaving the login screen alone."
        return 0
    fi

    pac_install greetd-tuigreet
    command -v tuigreet >/dev/null || { warn "tuigreet didn't install; leaving the login screen alone."; return 0; }

    local conf=/etc/greetd/config.toml vt=1
    if [[ -f "$conf" ]]; then
        vt=$(sed -n 's/^vt *= *\([0-9]\+\).*/\1/p' "$conf" | head -n 1)
        vt=${vt:-1}
        [[ -f "$conf.caelestia-setup.orig" ]] || sudo cp "$conf" "$conf.caelestia-setup.orig"
    fi

    local tmp
    tmp=$(mktemp)
    {
        printf '%s\n' '# Written by caelestia-setup. The original is next to this file as'
        printf '%s\n\n' '# config.toml.caelestia-setup.orig.'
        printf '[terminal]\nvt = %s\n\n' "$vt"
        printf '%s\n' '# Shown at boot (unless lock at boot is on) and after logging out.'
        printf '[default_session]\n'
        printf 'command = "tuigreet --time --remember --remember-session --asterisks --sessions /usr/share/wayland-sessions"\n'
        printf 'user = "greeter"\n'
        if [[ "$LOCK_AT_BOOT" == yes ]]; then
            printf '\n%s\n' '# Lock at boot: start the desktop without a login prompt. Caelestia locks'
            printf '%s\n' '# it at once (extras.json: lock.atLogin).'
            printf '[initial_session]\ncommand = "%s"\nuser = "%s"\n' "$session" "$USER"
        fi
    } > "$tmp"
    sudo install -m 0644 -o root -g root "$tmp" "$conf"
    rm -f "$tmp"

    # Typing your password at the text login should unlock your saved
    # passwords as well. Both lines are "optional": they can never stop a login.
    local pam=/etc/pam.d/greetd
    if [[ -f "$pam" && -e /usr/lib/security/pam_gnome_keyring.so ]] && ! grep -q pam_gnome_keyring "$pam"; then
        [[ -f "$pam.caelestia-setup.orig" ]] || sudo cp "$pam" "$pam.caelestia-setup.orig"
        printf '%s\n' '# Added by caelestia-setup: unlock the keyring with the login password.' \
            'auth       optional     pam_gnome_keyring.so' \
            'session    optional     pam_gnome_keyring.so auto_start' | sudo tee -a "$pam" >/dev/null
        info "the text login now unlocks the keyring (when its password is your login password)"
    fi

    if [[ "$LOCK_AT_BOOT" == yes ]]; then
        info "boot goes straight to your desktop, locked. After logging out you get a text login."
    else
        info "a plain text login screen replaces Noctalia's. Pick 'Hyprland' there if asked."
    fi
}

step_thunar() {
    installed thunar || return 0
    log "Thunar"

    xdg-mime default thunar.desktop inode/directory 2>/dev/null \
        || warn "Could not make Thunar the folder handler; set it by hand."

    # Thunar reads its colours once, when it starts. Its background process
    # would keep the old colours after a wallpaper change, so quit it whenever
    # Caelestia rewrites the colours; the next folder you open starts a fresh one.
    local unit_dir="$CONFIG_HOME/systemd/user"
    mkdir -p "$unit_dir"
    cat > "$unit_dir/thunar-theme-reload.path" <<'EOF'
[Unit]
Description=Watch GTK colours for Caelestia theme changes

[Path]
PathChanged=%h/.config/gtk-3.0/gtk.css

[Install]
WantedBy=default.target
EOF
    cat > "$unit_dir/thunar-theme-reload.service" <<'EOF'
[Unit]
Description=Restart Thunar so it picks up new GTK colours

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'pgrep -x thunar >/dev/null && thunar -q; exit 0'
EOF
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now thunar-theme-reload.path >/dev/null 2>&1 \
        || warn "Could not enable the Thunar colour watcher (no session?). Run this again from the desktop."
    info "Thunar opens folders and follows colour changes"
}

step_remove_noctalia() {
    local remove=() p
    for p in cachyos-hypr-noctalia noctalia noctalia-greeter; do
        if installed "$p"; then remove+=("$p"); fi
    done
    (( ${#remove[@]} )) || return 0
    log "Uninstalling Noctalia"

    if grep -qs noctalia /etc/greetd/config.toml; then
        warn "The login screen still uses Noctalia's greeter, so that one package stays (without it you couldn't log in)."
        local kept=()
        for p in "${remove[@]}"; do [[ "$p" == noctalia-greeter ]] || kept+=("$p"); done
        remove=("${kept[@]}")
        (( ${#remove[@]} )) || return 0
    fi

    # Removing a package also removes what only it needed. Some of those are
    # things Caelestia uses but doesn't list as its own requirements, so mark
    # them as wanted first.
    local keep=() k
    for k in hyprland uwsm greetd greetd-tuigreet xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
             gnome-keyring adw-gtk-theme brightnessctl ddcutil grim slurp wl-clipboard hyprpicker \
             curl git python noto-fonts noto-fonts-emoji; do
        if installed "$k"; then keep+=("$k"); fi
    done
    (( ${#keep[@]} )) && sudo pacman -D --asexplicit "${keep[@]}" >/dev/null

    info "pacman lists everything it will remove: Noctalia and the apps that only came with it"
    info "(its terminal kitty, the Dolphin file manager, and so on). Check that hyprland is NOT"
    info "in the list. To keep an app from the list, answer n, run"
    info "    sudo pacman -D --asexplicit <name>"
    info "and then: caelestia-setup install"
    local flags; mapfile -t flags < <(pac_flags)
    sudo pacman -Rns "${flags[@]}" "${remove[@]}" \
        || { warn "Noctalia was not removed. Remove it later with: sudo pacman -Rns ${remove[*]}"; return 0; }

    rm -rf "$CONFIG_HOME/noctalia" "${XDG_CACHE_HOME:-$HOME/.cache}/noctalia"
    info "Noctalia is gone. The terminal is now 'foot' (Super+T); a window you still have open keeps working until closed."
}

print_summary() {
    log "Done"
    cat <<EOF

 Restart the computer now, then check these. Tell whoever set this up what
 doesn't work.

   [ ] The desktop comes up with Caelestia's bar (no Noctalia).
   [ ] Super (tap) opens the launcher. Super+T opens a terminal.
   [ ] Super+L locks; your password unlocks.
   [ ] caelestia-setup check   says "All checks passed".
EOF
    [[ "$LOCK_AT_BOOT" == yes ]] && cat <<'EOF'
   [ ] After a restart you land on the lock screen without a login prompt,
       and an app that stores passwords (your browser) doesn't ask for the
       keyring password after you unlock.
EOF
    [[ "$BROWSER" == chrome || "$BROWSER" == brave ]] && cat <<'EOF'
   [ ] Change the wallpaper: the browser's colour changes with it
       (and Chrome's new tab picture, once you've uploaded any image there).
EOF
    [[ "$SUNSHINE" == yes ]] && cat <<'EOF'
   [ ] Sunshine: https://localhost:47990 opens; a paired device can stream;
       your monitors switch off during the stream and come back after it.
EOF
    cat <<EOF

 Your settings live in $CFG:
   extras.json     lock video, lock transparency, lock at login, wallpaper on login
   hypr-user.lua   your own Hyprland settings (keep its first line)
   hypr-vars.lua   Caelestia's variables: default apps, keybinds, gaps...
   machines/       this computer's monitor layout (caelestia-setup monitors)
   wallpapers/     your wallpapers

 Updating:  caelestia-setup update
   Use this instead of "pacman -Syu" or "paru". It updates the whole system
   (CachyOS's packages, the AUR ones and Caelestia), and first makes sure the
   update would not leave the desktop unable to start.
EOF
}

# ---------------------------------------------------------------------------
# Your settings as a private GitHub repository: backup, save, restore
#
# ~/.config/caelestia is the working copy of that repository. You edit the
# live files (or change things in Caelestia's settings window), and
# `caelestia-setup save` uploads the changes. On a fresh install the
# installer downloads them again before it sets anything up.
# ---------------------------------------------------------------------------

DEPLOY_KEY="$HOME/.ssh/caelestia-config_ed25519"

cfg_git()        { git -C "$CFG" "$@"; }
cfg_is_repo()    { [[ -d "$CFG/.git" ]] && cfg_git rev-parse --git-dir >/dev/null 2>&1; }
cfg_remote()     { cfg_git config --get remote.origin.url 2>/dev/null || true; }
cfg_has_remote() { cfg_is_repo && [[ -n "$(cfg_remote)" ]]; }

# owner/name from a GitHub address in either form.
cfg_slug() {
    cfg_remote | sed -E -e 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)##' -e 's#\.git$##'
}

deploy_ssh() { printf 'ssh -i %q -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new' "$DEPLOY_KEY"; }

gh_ready() { command -v gh >/dev/null && gh auth status --hostname github.com >/dev/null 2>&1; }

explain_backup() {
    cat >/dev/tty <<'EOF'

 Your settings are the files in ~/.config/caelestia (wallpapers and lock video
 included). A private GitHub repository keeps a copy that only you can see:
   - after a reinstall, or on another computer, the installer brings them back
   - "caelestia-setup save" uploads your changes whenever you like
 It needs a free GitHub account (github.com/signup).
EOF
}

# Prints: login, key or none.
choose_auth() {
    local preset="${CS_BACKUP:-}" reply
    case "$preset" in login|key|none) printf '%s' "$preset"; return ;; esac
    if (( ASSUME_YES )); then printf 'none'; return; fi
    cat >/dev/tty <<'EOF'

 How should this computer reach your GitHub repository?
   1) Sign in to GitHub in the browser - simplest; best if you're starting out.
      This computer (and any program you run on it) can then reach all of
      your repositories, not only this one.
   2) A key for this one repository only - tighter, but with manual steps:
      you create the repository and paste a key into its settings yourself.
   3) Not now
EOF
    while true; do
        printf '\033[1;36m ?\033[0m Choose 1-3 [1] ' >/dev/tty
        reply=$(tty_read)
        case "${reply,,}" in
            ""|1|login) printf 'login'; return ;;
            2|key)      printf 'key'; return ;;
            3|none|n)   printf 'none'; return ;;
            *)          printf '   Type 1, 2 or 3.\n' >/dev/tty ;;
        esac
    done
}

github_login() {
    installed github-cli || pac_install github-cli
    if gh_ready; then
        info "signed in to GitHub as $(gh api user -q .login 2>/dev/null || echo '?')"
    else
        info "GitHub will show a one-time code. Press Enter there, sign in on the page that"
        info "opens (or open the address it prints on your phone) and type the code."
        gh auth login --hostname github.com --git-protocol https --web \
            || die "Signing in to GitHub didn't finish. Run this again when you're ready."
    fi
    # Lets plain git commands use that sign-in for github.com.
    gh auth setup-git --hostname github.com >/dev/null 2>&1 || true
}

# ask_slug "Question" DEFAULT [OWNER] -> owner/name
ask_slug() {
    local q=$1 def=$2 owner=${3:-} reply
    while true; do
        printf '\033[1;36m ?\033[0m %s%s ' "$q" "${def:+ [$def]}" >/dev/tty
        reply=$(tty_read)
        reply=${reply:-$def}
        reply=${reply#https://github.com/}; reply=${reply%.git}
        [[ "$reply" != */* && -n "$owner" && -n "$reply" ]] && reply="$owner/$reply"
        if [[ "$reply" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then printf '%s' "$reply"; return; fi
        printf '   Type it as owner/name, for example %s/caelestia-config\n' "${owner:-yourname}" >/dev/tty
    done
}

# Make this computer's key for one repository, and wait until GitHub accepts it.
setup_deploy_key() {  # setup_deploy_key OWNER/NAME
    local slug=$1
    command -v ssh-keygen >/dev/null || pac_install openssh
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    if [[ ! -f "$DEPLOY_KEY" ]]; then
        ssh-keygen -q -t ed25519 -N "" -C "caelestia-setup on $(cat /etc/hostname 2>/dev/null || echo this-pc)" -f "$DEPLOY_KEY"
    fi
    while true; do
        if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$(deploy_ssh)" git ls-remote "git@github.com:$slug.git" >/dev/null 2>&1; then
            info "GitHub accepts this computer's key for $slug"
            return 0
        fi
        cat >/dev/tty <<EOF

 Add this computer's key to the repository:
   1. Open  https://github.com/$slug/settings/keys/new
   2. Title: this computer's name. Key: paste the line below.
   3. Tick "Allow write access", then "Add key".

 $(cat "$DEPLOY_KEY.pub")

EOF
        printf '\033[1;36m ?\033[0m Press Enter when that is done (or type skip) ' >/dev/tty
        [[ "$(tty_read)" == skip ]] && return 1
    done
}

# Commits are labelled with a name and address. Use GitHub's private
# "noreply" address so your real e-mail address isn't written into them.
set_identity() {
    [[ -n "$(cfg_git config user.email 2>/dev/null || true)" ]] && return 0
    local name="$USER" email
    email="$USER@$(cat /etc/hostname 2>/dev/null || echo localhost)"
    if gh_ready; then
        local login id
        login=$(gh api user -q .login 2>/dev/null || true)
        id=$(gh api user -q .id 2>/dev/null || true)
        if [[ -n "$login" && -n "$id" ]]; then name=$login; email="${id}+${login}@users.noreply.github.com"; fi
    fi
    cfg_git config user.name "$name"
    cfg_git config user.email "$email"
}

cfg_init() {
    mkdir -p "$CFG"
    cfg_is_repo || git init -q -b main "$CFG"
    if [[ ! -e "$CFG/.gitignore" ]]; then
        printf '%s\n' '# Editor leftovers and temporary files: not worth backing up.' '*.swp' '*~' '.*.tmp' '.answers.*' > "$CFG/.gitignore"
    fi
}

# Stage everything, show it, ask, commit. Returns 1 if the user says no.
save_commit() {
    local big
    big=$(find "$CFG" -path "$CFG/.git" -prune -o -type f -size +95M -print)
    if [[ -n "$big" ]]; then
        warn "GitHub refuses files over 100 MB. Move these out of ~/.config/caelestia, or list them in its .gitignore:"
        printf '%s\n' "$big" | sed 's/^/       /' >&2
        return 1
    fi

    cfg_git add -A
    if cfg_git diff --cached --quiet; then
        info "No changes since the last save."
        return 0
    fi

    local total
    total=$(cfg_git status --short | wc -l)
    info "Changed since the last save (A = new, M = changed, D = removed):"
    cfg_git status --short | head -n 30 | sed 's/^/      /'
    (( total > 30 )) && info "      ... and $((total - 30)) more"
    if ! confirm "Save these to GitHub?" yes; then
        cfg_git reset -q
        info "Nothing saved."
        return 1
    fi
    set_identity
    cfg_git commit -q -m "Save from $(cat /etc/hostname 2>/dev/null || echo this-pc) on $(date +%F)"
}

save_push() {
    local branch
    branch=$(cfg_git symbolic-ref --short HEAD)
    # If another computer saved in the meantime, put its changes underneath ours.
    if GIT_TERMINAL_PROMPT=0 cfg_git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        if ! GIT_TERMINAL_PROMPT=0 cfg_git pull -q --rebase origin "$branch" >/dev/null 2>&1; then
            cfg_git rebase --abort 2>/dev/null || true
            die "The copy on GitHub and this computer changed the same lines, and I won't guess which to keep. Your changes are safe here (committed, not uploaded). Run 'git -C ~/.config/caelestia pull' to merge by hand, or ask for help."
        fi
    fi
    info "uploading..."
    GIT_TERMINAL_PROMPT=0 cfg_git push -q -u origin "$branch" \
        || die "Upload failed. Check the network, then run: caelestia-setup save"
    info "Saved to github.com/$(cfg_slug)"
}

mode_save() {
    cfg_has_remote || die "No backup is set up yet. Run: caelestia-setup backup"
    log "Saving your settings"
    save_commit || return 0
    # Nothing committed at all yet (an empty folder): nothing to upload.
    [[ -n "$(cfg_git log --oneline -1 2>/dev/null || true)" ]] || return 0
    # Already uploaded? (No upstream yet means this is the first upload.)
    local upstream
    upstream=$(cfg_git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
    if [[ -n "$upstream" && "$(cfg_git rev-list --count "$upstream..HEAD")" == 0 ]]; then
        info "Everything is already on GitHub."
        return 0
    fi
    save_push
}

# A repository meant to be private that is public: offer to fix it.
check_visibility() {
    gh_ready || return 0
    local slug vis
    slug=$(cfg_slug)
    vis=$(gh repo view "$slug" --json visibility -q .visibility 2>/dev/null || true)
    [[ "$vis" == PUBLIC ]] || return 0
    warn "github.com/$slug is PUBLIC: anyone can read your settings and wallpapers."
    if confirm "Make it private?" yes; then
        gh repo edit "$slug" --visibility private --accept-visibility-change-consequences >/dev/null \
            && info "$slug is now private" \
            || warn "Could not change it. Do it on GitHub: Settings > General > Danger Zone > Change visibility."
    fi
}

mode_backup() {
    log "Backup of your settings"
    [[ -d "$CFG" ]] || die "There are no settings yet (~/.config/caelestia). Run the installer first."
    command -v git >/dev/null || pac_install git

    local auth slug login
    if cfg_has_remote; then
        slug=$(cfg_slug)
        info "settings are connected to github.com/$slug"
        if [[ -z "$(cfg_git config core.sshCommand 2>/dev/null || true)" ]] && ! gh_ready; then
            auth=$(choose_auth)
            case "$auth" in
                none)  info "Left as it is."; return 0 ;;
                login) github_login ;;
                key)   setup_deploy_key "$slug" || { info "Left as it is."; return 0; }
                       cfg_git remote set-url origin "git@github.com:$slug.git"
                       cfg_git config core.sshCommand "$(deploy_ssh)" ;;
            esac
            answer_set backup "$auth"
        fi
    else
        (( ASSUME_YES )) || explain_backup
        auth=$(choose_auth)
        [[ "$auth" == none ]] && { info "No backup set up. Any time later: caelestia-setup backup"; return 0; }
        cfg_init
        case "$auth" in
            login)
                github_login
                login=$(gh api user -q .login)
                if (( ASSUME_YES )); then slug="$login/${CS_CONFIG_REPO:-caelestia-config}"; slug="$login/${slug##*/}"
                else slug=$(ask_slug "Name for your private settings repository" caelestia-config "$login"); fi
                if gh repo view "$slug" >/dev/null 2>&1; then
                    info "github.com/$slug already exists; connecting to it"
                else
                    gh repo create "$slug" --private --description "My caelestia-setup settings" >/dev/null \
                        || die "Could not create github.com/$slug"
                    info "created private repository github.com/$slug"
                fi
                cfg_git remote add origin "https://github.com/$slug.git"
                ;;
            key)
                cat >/dev/tty <<'EOF'

 First create the repository yourself:
   1. Open  https://github.com/new
   2. Give it a name (for example caelestia-config) and choose "Private".
   3. Leave everything else unticked (no README) and click "Create repository".
EOF
                slug=$(ask_slug "What is it called? (owner/name)" "")
                setup_deploy_key "$slug" || { info "No backup set up. Any time later: caelestia-setup backup"; return 0; }
                cfg_git remote add origin "git@github.com:$slug.git"
                cfg_git config core.sshCommand "$(deploy_ssh)"
                ;;
        esac
        answer_set backup "$auth"
    fi

    check_visibility
    mode_save
}

# Fresh install: bring the settings back before anything is set up.
step_restore() {
    command -v git >/dev/null || pac_install git
    if cfg_has_remote; then
        info "Your settings are connected to github.com/$(cfg_slug)."
        return 0
    fi

    local slug="${CS_CONFIG_REPO:-}" auth login
    if [[ -z "$slug" ]]; then
        (( ASSUME_YES )) && return 0
        printf '\n If you have used caelestia-setup before, your settings may be saved in a\n private GitHub repository ("caelestia-setup backup").\n' >/dev/tty
        confirm "Bring back saved settings from GitHub?" no || return 0
    fi

    if [[ -d "$CFG" && -n "$(ls -A "$CFG" 2>/dev/null)" ]]; then
        warn "~/.config/caelestia already has files in it."
        confirm "Delete them and use the saved copy from GitHub?" no \
            || { info "Keeping what is here; not restoring."; return 0; }
        rm -rf "$CFG"
    fi

    log "Restoring your settings"
    auth=$(CS_BACKUP="${CS_BACKUP:-}" choose_auth)
    [[ "$auth" == none && -n "${CS_CONFIG_REPO:-}" ]] && auth=login
    case "$auth" in
        none) info "Not restoring."; return 0 ;;
        login)
            github_login
            login=$(gh api user -q .login)
            if [[ -z "$slug" ]]; then
                local found
                found=$(gh repo list --limit 100 --json nameWithOwner -q '.[].nameWithOwner' 2>/dev/null | grep -i caelestia | grep -vi 'default-config' || true)
                [[ -n "$found" ]] && { printf '\n Your repositories with "caelestia" in the name:\n' >/dev/tty; printf '%s\n' "$found" | sed 's/^/   /' >/dev/tty; }
                slug=$(ask_slug "Which repository holds your settings?" "$(printf '%s\n' "$found" | head -n 1)" "$login")
            elif [[ "$slug" != */* ]]; then
                slug="$login/$slug"
            fi
            mkdir -p "$(dirname "$CFG")"
            gh repo clone "$slug" "$CFG" -- -q || die "Could not download github.com/$slug. Check the name and run this again."
            ;;
        key)
            [[ -n "$slug" ]] || slug=$(ask_slug "Which repository holds your settings? (owner/name)" "")
            setup_deploy_key "$slug" || { info "Not restoring."; return 0; }
            mkdir -p "$(dirname "$CFG")"
            GIT_SSH_COMMAND="$(deploy_ssh)" git clone -q "git@github.com:$slug.git" "$CFG" \
                || die "Could not download github.com/$slug. Check the name and run this again."
            cfg_git config core.sshCommand "$(deploy_ssh)"
            ;;
    esac
    answer_set backup "$auth"
    info "settings restored from github.com/$slug"
    [[ -f "$ANSWERS" ]] && info "Your earlier answers are the defaults for the questions that follow: press Enter to keep each."
    return 0
}

# Update: bring in what another computer saved.
step_config_pull() {
    cfg_has_remote || return 0
    log "Your settings"
    if ! GIT_TERMINAL_PROMPT=0 cfg_git fetch -q origin 2>/dev/null; then
        info "Could not reach github.com/$(cfg_slug); skipped."
        return 0
    fi
    local upstream behind
    upstream=$(cfg_git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
    if [[ -n "$upstream" ]]; then
        behind=$(cfg_git rev-list --count "HEAD..$upstream")
        if (( behind == 0 )); then
            info "nothing new in your saved copy on GitHub"
        else
            info "Your saved copy on GitHub has changes this computer doesn't have yet:"
            cfg_git diff --stat "HEAD...$upstream" | sed 's/^/      /'
            if confirm "Apply them here?" yes; then
                if GIT_TERMINAL_PROMPT=0 cfg_git pull -q --rebase --autostash origin >/dev/null 2>&1; then
                    info "applied"
                    in_session && { hyprctl reload >/dev/null 2>&1 || true; }
                else
                    cfg_git rebase --abort 2>/dev/null || true
                    warn "Those changes clash with unsaved changes here; nothing was applied. Run 'caelestia-setup save' first, then update again."
                fi
            fi
        fi
    fi
    if [[ -n "$(cfg_git status --porcelain)" ]]; then
        info "This computer has settings that aren't saved yet. Upload them with: caelestia-setup save"
    fi
}

step_backup_offer() {
    cfg_has_remote && return 0
    (( ASSUME_YES )) && [[ -z "${CS_BACKUP:-}" ]] && return 0
    if (( ! ASSUME_YES )); then
        explain_backup
        confirm "Set up the backup now?" no || { info "Any time later: caelestia-setup backup"; return 0; }
    fi
    mode_backup
}

# ---------------------------------------------------------------------------
# Apps your settings refer to
#
# Settings can name apps this script doesn't install: the player for
# recordings, the app behind a workspace toggle, your terminal or editor. A
# restore brings the settings back but not those apps. So read the settings,
# find what is missing, and offer to install it -- by exact name, from the
# distribution's own repositories only, never the AUR. Anything else is
# listed for you to install yourself.
# ---------------------------------------------------------------------------

# Prints the commands named in shell.json, cli.json and hypr-vars.lua.
settings_apps() {
    python3 - "$CFG" <<'PY'
import json, os, re, shlex, sys

cfg = sys.argv[1]
found = []


def words(text):
    try:
        return shlex.split(text)
    except ValueError:
        return text.split()


def add(cmd):
    parts = words(cmd) if isinstance(cmd, str) else [str(x) for x in (cmd or [])]
    # Look through wrappers:  sh -c "exec app ..."   env VAR=x app   exec app
    for _ in range(6):
        if not parts:
            return
        head = os.path.basename(parts[0])
        if head in ("sh", "bash", "fish", "zsh") and len(parts) >= 3 and parts[1] == "-c":
            parts = words(parts[2])
        elif head in ("exec", "env", "nohup", "setsid"):
            parts = parts[1:]
        elif re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", parts[0]):
            parts = parts[1:]
        else:
            break
    if parts and "/" not in parts[0] and parts[0] not in found:
        found.append(parts[0])


def load(name):
    try:
        with open(os.path.join(cfg, name)) as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


apps = load("shell.json").get("general", {}).get("apps", {})
if isinstance(apps, dict):
    for value in apps.values():
        add(value)

toggles = load("cli.json").get("toggles", {})
if isinstance(toggles, dict):
    for group in toggles.values():
        if not isinstance(group, dict):
            continue
        for app in group.values():
            if isinstance(app, dict) and app.get("enable", True) and app.get("command"):
                add(app["command"])

try:
    with open(os.path.join(cfg, "hypr-vars.lua")) as f:
        lua = f.read()
    for m in re.finditer(r'(?m)^\s*(?:terminal|browser|editor|fileExplorer|audioSettings)\s*=\s*"([^"]+)"', lua):
        add(m.group(1))
except OSError:
    pass

print("\n".join(found))
PY
}

SETTINGS_INSTALL=() SETTINGS_UNKNOWN=()

# Sorts the missing ones into "can install" (package names) and "can't find".
find_missing_settings_apps() {
    SETTINGS_INSTALL=() SETTINGS_UNKNOWN=()
    [[ -d "$CFG" ]] || return 0
    local cmd pkg repo
    while IFS= read -r cmd; do
        [[ "$cmd" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || continue
        command -v "$cmd" >/dev/null 2>&1 && continue
        pkg=$cmd
        case "$cmd" in nvim) pkg=neovim ;; esac   # the few commands whose package has another name
        repo=$(LC_ALL=C pacman -Si -- "$pkg" 2>/dev/null | awk '/^Repository/ { print $3; exit }')
        if [[ "$repo" =~ ^(core|extra|multilib|cachyos.*)$ ]]; then
            SETTINGS_INSTALL+=("$pkg")
            # VLC's file-format support is a separate package on Arch.
            if [[ "$pkg" == vlc ]] && pacman -Si -- vlc-plugins-all >/dev/null 2>&1; then SETTINGS_INSTALL+=(vlc-plugins-all); fi
        else
            SETTINGS_UNKNOWN+=("$cmd")
        fi
    done < <(settings_apps)
}

step_settings_apps() {
    find_missing_settings_apps
    (( ${#SETTINGS_INSTALL[@]} + ${#SETTINGS_UNKNOWN[@]} )) || return 0
    log "Apps your settings use"
    if (( ${#SETTINGS_INSTALL[@]} )); then
        info "Not installed, and available from CachyOS's repositories: ${SETTINGS_INSTALL[*]}"
        if confirm "Install them?" yes; then
            pac_install "${SETTINGS_INSTALL[@]}" || warn "Could not install them; try: sudo pacman -S ${SETTINGS_INSTALL[*]}"
        fi
    fi
    if (( ${#SETTINGS_UNKNOWN[@]} )); then
        info "Not installed, and not in CachyOS's repositories (install these yourself): ${SETTINGS_UNKNOWN[*]}"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

mode_install() {
    preflight
    step_qt_guard
    step_restore
    ask_questions
    show_plan

    step_system_update
    step_packages
    # Before Caelestia, so that a hypr-user.lua which already loads the shared
    # additions (a restored config) finds them when Caelestia first reloads.
    step_system_files
    step_quickshell
    step_caelestia
    step_patch_shell --enable
    step_user_config
    step_scheme --write-default
    step_browser
    step_settings_apps
    step_sunshine
    step_thunar
    step_login
    step_monitors

    in_session && { hyprctl reload >/dev/null 2>&1 || true; }
    restart_shell
    step_lock_selftest
    # Last, because it also removes the terminal this is probably running in.
    step_remove_noctalia
    print_summary
    if (( SELFTEST_FAILED )); then
        warn "The lock-screen additions are OFF because their test failed (see above)."
        warn "Everything else is installed. Please pass on the messages above."
    fi
    step_backup_offer
}

mode_update() {
    preflight
    BROWSER=$(answer_get browser); SUNSHINE=$(answer_get sunshine)
    LOCK_AT_BOOT=$(answer_get lock_at_boot); COMPONENTS=$(answer_get components)

    log "Updating the system and Caelestia"
    local flags=()
    (( ASSUME_YES )) && flags+=(--noconfirm)
    # Caelestia's updater runs the full system update itself, then updates its
    # own files. The pacman hook re-adds the shell additions along the way.
    if qt_update_safe; then
        caelestia update "${flags[@]}" || warn "caelestia update reported a problem (see above)."
    else
        warn "So the system update is skipped this time; the rest of this update carries on."
    fi

    # A newer Qt may have just arrived.
    step_qt_rebuild

    log "Updating caelestia-setup"
    local tmp
    tmp=$(mktemp -d)
    if GIT_TERMINAL_PROMPT=0 git clone -q --depth 50 "$REPO_URL" "$tmp/src" 2>/dev/null; then
        local new old
        new=$(git -C "$tmp/src" rev-parse HEAD)
        old=$(cat "$LIB/VERSION" 2>/dev/null || echo none)
        if [[ "$new" == "$old" ]]; then
            info "already the newest version"
        else
            info "new version available:"
            git -C "$tmp/src" log --oneline "$old..$new" 2>/dev/null | sed 's/^/      /' \
                || info "      (first tracked version)"
            if confirm "Install it?" yes; then
                SRC="$tmp/src"
                step_system_files
            fi
        fi
    else
        info "Could not download $REPO_URL (not published yet, or no network); keeping the installed version."
    fi
    rm -rf "$tmp"

    step_patch_shell
    if (( SHELL_CHANGED )); then restart_shell; fi
    step_config_pull
    step_scheme
    step_settings_apps
    mode_check || true
    if (( QT_HELD )); then
        echo
        warn "Reminder: the system update was skipped because Qt is half-published (see the top)."
        warn "Run 'caelestia-setup update' again in a few hours, and don't update the system by"
        warn "other means (pacman, paru, a software centre) until then."
    fi
}

CHECK_FAILS=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; CHECK_FAILS=$((CHECK_FAILS + 1)); }
note() { printf '  \033[33mNOTE\033[0m  %s\n' "$*"; }
check() { local desc=$1; shift; if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi; }

mode_check() {
    CHECK_FAILS=0
    BROWSER=$(answer_get browser); SUNSHINE=$(answer_get sunshine); LOCK_AT_BOOT=$(answer_get lock_at_boot)

    echo "Caelestia"
    check "caelestia command installed" command -v caelestia
    check "qs is the real Quickshell, not Noctalia's fork" bash -c '[ "$(pacman -Qqo "$(command -v qs)")" = quickshell-git ]'
    local qt_now qt_fix
    qt_now=$(qt_family)
    if [[ -n "$qt_now" ]]; then
        if qt_is_mixed <<<"$qt_now"; then
            fail "Qt's packages are at mixed versions: $(qt_describe <<<"$qt_now")"
            note "Qt only works at one version, so the bar and lock screen cannot start. It happens"
            note "when an update is taken while a new Qt is half-published."
            if qt_fix=$(qt_repair_hint "$qt_now"); then
                note "Put the odd one(s) back with:  $qt_fix"
            else
                note "Run 'caelestia-setup update' in a few hours, once the rest is available."
            fi
        else
            pass "Qt's packages are all one version ($(qt_version))"
        fi
    fi
    if [[ -r "$QT_STAMP" ]]; then
        check "Quickshell was built for the installed Qt ($(qt_version))" test "$(cat "$QT_STAMP")" = "$(qt_version)"
    fi
    check "shell installed in $SHELL_DIR" test -f "$SHELL_DIR/shell.qml"
    check "Caelestia's files installed (dots)" test -f "$DOTS_STATE"
    local scheme_want scheme_now
    scheme_want=$(scheme_wanted)
    scheme_now=$(caelestia scheme get -n 2>/dev/null || true)
    if [[ "$scheme_now" == "$scheme_want" ]]; then
        if [[ "$scheme_want" == dynamic ]]; then pass "colours follow the wallpaper"; else pass "colour scheme is '$scheme_want'"; fi
    elif [[ ! -e "$SCHEME_MARK" ]]; then
        fail "colour scheme '$scheme_want' is not applied yet (it is '${scheme_now:-unknown}'); run: caelestia-setup update"
    fi
    if in_session; then
        check "shell is running" qs -c caelestia ipc call lock isLocked
        local errs
        errs=$(hyprctl configerrors 2>/dev/null | grep -v '^\s*$' || true)
        if [[ -z "$errs" ]] || grep -qi 'no errors' <<<"$errs"; then
            pass "Hyprland config has no errors"
        else
            fail "Hyprland config errors: $errs"
        fi
    else
        note "not in a Hyprland session; skipped the live checks"
    fi

    echo "caelestia-setup"
    check "files installed in $LIB" test -f "$LIB/patches/patch_shell.py"
    check "installed files are owned by root" bash -c "[ -z \"\$(find '$LIB' ! -user root -print -quit)\" ]"
    check "update hook installed" test -f "$HOOK"
    if [[ -e /var/lib/caelestia-setup/disabled ]]; then
        note "shell additions are turned off (turn on with: caelestia-setup patch)"
    elif [[ -r "$PATCH_STATUS" ]]; then
        python3 - "$PATCH_STATUS" <<'PY' | while IFS=$'\t' read -r state name detail; do
import json, sys
for name, r in json.load(open(sys.argv[1]))["results"].items():
    print(r["state"], name, r.get("detail", ""), sep="\t")
PY
            case "$state" in
                FAILED)  fail "shell addition '$name' no longer fits: $detail" ;;
                skipped) note "shell addition '$name' skipped: $detail" ;;
                *)       pass "shell addition: $name" ;;
            esac
        done
        # The loop above runs in a subshell, so count failures again here.
        local n
        n=$(python3 -c 'import json, sys; print(len(json.load(open(sys.argv[1])).get("failed", [])))' "$PATCH_STATUS")
        CHECK_FAILS=$((CHECK_FAILS + n))
    else
        fail "shell additions were never applied (run: caelestia-setup install)"
    fi
    check "lock video player can load (qt6-multimedia)" test -d /usr/lib/qt6/qml/QtMultimedia

    echo "Your settings"
    check "hypr-user.lua loads the shared additions" grep -q 'caelestia-setup/hypr/base.lua' "$CFG/hypr-user.lua"
    check "extras.json is valid" python3 -c "import json; json.load(open('$CFG/extras.json'))"
    local video
    video=$(python3 -c "
import json, os
v = json.load(open('$CFG/extras.json')).get('lock', {}).get('video', '')
if v:
    v = os.path.expanduser(v)
    print(v if os.path.isabs(v) else os.path.join('$CFG', v))" 2>/dev/null || true)
    if [[ -n "$video" ]]; then
        check "lock video file exists ($video)" test -f "$video"
    else
        note "no lock video set (extras.json: lock.video)"
    fi
    find_missing_settings_apps
    if (( ${#SETTINGS_INSTALL[@]} + ${#SETTINGS_UNKNOWN[@]} )); then
        note "apps your settings use that aren't installed: ${SETTINGS_INSTALL[*]} ${SETTINGS_UNKNOWN[*]} (caelestia-setup update offers to install what it can)"
    else
        pass "every app your settings use is installed"
    fi
    local host
    host=$(cat /etc/hostname 2>/dev/null || true)
    if [[ -f "$CFG/machines/$host.lua" ]]; then
        pass "monitor layout saved for '$host'"
    else
        note "no saved monitor layout for '$host' (automatic layout in use; caelestia-setup monitors)"
    fi

    if [[ "$BROWSER" == chrome || "$BROWSER" == brave ]]; then
        echo "Browser"
        check "sudo rule allows only the colour helper" sudo -n -l "$LIB/system/browser-theme" 0a0a0a
        check "cli.json runs the wallpaper hook, Caelestia's browser theming off" python3 -c "
import json
c = json.load(open('$CFG/cli.json'))
assert c['wallpaper']['postHook'] == '$LIB/bin/wallpaper-hook'
assert c['theme']['enableChromium'] is False"
    fi

    if [[ "$SUNSHINE" == yes ]]; then
        echo "Sunshine"
        check "sunshine installed" command -v sunshine
        check "virtual display registered for every stream" grep -q 'sunshine-vd-start' "$CONFIG_HOME/sunshine/sunshine.conf"
        if in_session; then
            local unit
            unit=$(sunshine_unit)
            check "Sunshine's service is running (${unit:-service not found})" systemctl --user is-active "${unit:-sunshine.service}"
            if hyprctl monitors 2>/dev/null | grep -q '^Monitor sunshine_vd'; then
                note "a stream is running now"
            else
                check "no leftover stream layout" test ! -e "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunshine_vd.lua"
            fi
        fi
    fi

    echo "Backup"
    if cfg_has_remote; then
        pass "settings are connected to github.com/$(cfg_slug)"
        local unsaved
        unsaved=$(cfg_git status --porcelain | wc -l)
        if (( unsaved )); then note "$unsaved unsaved change(s): caelestia-setup save"; else pass "everything is saved"; fi
        if gh_ready; then
            check "the repository is private" bash -c "[ \"\$(gh repo view '$(cfg_slug)' --json visibility -q .visibility)\" = PRIVATE ]"
        fi
    else
        note "no backup set up (caelestia-setup backup)"
    fi

    echo "Login"
    if [[ -f /etc/greetd/config.toml ]]; then
        check "login screen no longer uses Noctalia" bash -c '! grep -q noctalia /etc/greetd/config.toml'
        if [[ "$LOCK_AT_BOOT" == yes ]]; then
            check "automatic login configured" grep -q '^\[initial_session\]' /etc/greetd/config.toml
            check "lock at login turned on" python3 -c "
import json
assert json.load(open('$CFG/extras.json'))['lock']['atLogin'] is True"
        fi
    fi
    if installed noctalia; then note "Noctalia is still installed"; else pass "Noctalia uninstalled"; fi

    echo
    if (( CHECK_FAILS == 0 )); then
        echo "All checks passed."
    else
        echo "$CHECK_FAILS check(s) failed."
        return 1
    fi
}

usage() {
    sed -n '3,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
    local mode="" arg
    for arg in "$@"; do
        case "$arg" in
            -y|--yes)   ASSUME_YES=1 ;;
            -h|--help)  mode=help ;;
            install|update|check|monitors|patch|unpatch|save|backup) mode=$arg ;;
            *) die "Unknown option '$arg'. Try: caelestia-setup --help" ;;
        esac
    done

    locate_source || bootstrap "$@"

    # Run as the installed command with nothing to do: show the help.
    # Run from a download or a folder: install.
    if [[ -z "$mode" ]]; then
        [[ "$SRC" == "$LIB" ]] && mode=help || mode=install
    fi

    case "$mode" in
        help)     usage ;;
        install)  mode_install ;;
        update)   mode_update ;;
        check)    trap - ERR; mode_check || exit 1 ;;
        monitors) mode_monitors ;;
        patch)    mode_patch ;;
        unpatch)  mode_unpatch ;;
        save)     mode_save ;;
        backup)   mode_backup ;;
    esac
}

# (The test harness loads the functions without running anything.)
[[ -n "${CAELESTIA_SETUP_SOURCE_ONLY:-}" ]] || main "$@"
