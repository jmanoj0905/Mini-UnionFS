#!/bin/bash
# unionfs_cli.sh — Interactive CLI to manually test Mini-UnionFS
#
# Usage: ./unionfs_cli.sh
#
# Folder layout (relative to project root):
#   unionfs_test_env/
#     lower/   read-only base layer
#     upper/   writable layer (CoW writes land here)
#     mnt/     FUSE mount point (merged view)

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="$SCRIPT_DIR/mini_unionfs"
TEST_ENV="$SCRIPT_DIR/unionfs_test_env"
LOWER="$TEST_ENV/lower"
UPPER="$TEST_ENV/upper"
MNT="$TEST_ENV/mnt"

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
banner() {
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║        Mini-UnionFS  Interactive CLI         ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

info()    { echo -e "  ${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "  ${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "  ${RED}[ERR]${NC}   $*"; }
section() { echo -e "\n${BOLD}${BLUE}── $* ──${NC}"; }

is_mounted() {
    mountpoint -q "$MNT" 2>/dev/null
}

# ── Setup / teardown ──────────────────────────────────────────────────────────
do_setup() {
    section "Setting up test environment"

    # Unmount if already mounted
    if is_mounted; then
        warn "mnt/ already mounted — unmounting first"
        fusermount -u "$MNT" 2>/dev/null || umount "$MNT" 2>/dev/null || true
        sleep 0.5
    fi

    # Wipe and recreate layers (keep mnt/ as a dir)
    rm -rf "$LOWER" "$UPPER"
    mkdir -p "$LOWER" "$UPPER" "$MNT"

    # Seed lower with sample files that cover every test scenario
    echo "base_content_line1"              > "$LOWER/base.txt"
    echo "base_content_line2"             >> "$LOWER/base.txt"
    echo "to_be_deleted"                   > "$LOWER/delete_me.txt"
    echo "read_only_data"                  > "$LOWER/readonly.txt"
    mkdir -p "$LOWER/subdir"
    echo "nested file in lower"            > "$LOWER/subdir/nested.txt"
    echo "another lower file"              > "$LOWER/subdir/other.txt"

    ok "lower/ seeded:"
    find "$LOWER" -type f | sed "s|$TEST_ENV/||" | sort | while read -r f; do
        echo -e "        ${DIM}$f${NC}"
    done

    # Mount
    info "Mounting: $BINARY lower/ upper/ mnt/"
    "$BINARY" "$LOWER" "$UPPER" "$MNT" 2>/dev/null &
    sleep 1

    if is_mounted; then
        ok "Mounted at mnt/"
    else
        err "Mount failed — is the binary built? Run: make"
        exit 1
    fi
}

do_teardown() {
    section "Teardown"
    if is_mounted; then
        fusermount -u "$MNT" 2>/dev/null || umount "$MNT" 2>/dev/null || true
        ok "Unmounted mnt/"
    else
        info "mnt/ was not mounted"
    fi
}

# ── Layer snapshot ────────────────────────────────────────────────────────────
do_layers() {
    echo ""
    echo -e "  ${BOLD}${MAGENTA}lower/${NC}  (read-only base)"
    if [ -z "$(ls -A "$LOWER" 2>/dev/null)" ]; then
        echo -e "    ${DIM}(empty)${NC}"
    else
        find "$LOWER" | tail -n +2 | sed "s|$LOWER||" | sort | while read -r f; do
            if [ -f "$LOWER$f" ]; then
                echo -e "    ${DIM}$f${NC}"
            else
                echo -e "    ${BLUE}$f/${NC}"
            fi
        done
    fi

    echo ""
    echo -e "  ${BOLD}${YELLOW}upper/${NC}  (writable / CoW layer)"
    if [ -z "$(ls -A "$UPPER" 2>/dev/null)" ]; then
        echo -e "    ${DIM}(empty)${NC}"
    else
        find "$UPPER" | tail -n +2 | sed "s|$UPPER||" | sort | while read -r f; do
            if [ -f "$UPPER$f" ]; then
                fname=$(basename "$f")
                if [[ "$fname" == .wh.* ]]; then
                    echo -e "    ${RED}$f  [whiteout]${NC}"
                else
                    echo -e "    ${GREEN}$f${NC}"
                fi
            else
                echo -e "    ${BLUE}$f/${NC}"
            fi
        done
    fi

    echo ""
    echo -e "  ${BOLD}${CYAN}mnt/${NC}    (merged view)"
    if ! is_mounted; then
        echo -e "    ${RED}(not mounted)${NC}"
    elif [ -z "$(ls -A "$MNT" 2>/dev/null)" ]; then
        echo -e "    ${DIM}(empty)${NC}"
    else
        find "$MNT" | tail -n +2 | sed "s|$MNT||" | sort | while read -r f; do
            if [ -f "$MNT$f" ]; then
                echo -e "    ${CYAN}$f${NC}"
            else
                echo -e "    ${BLUE}$f/${NC}"
            fi
        done
    fi
    echo ""
}

# ── Help text ─────────────────────────────────────────────────────────────────
do_help() {
    echo ""
    echo -e "  ${BOLD}Built-in commands${NC}"
    echo -e "  ${GREEN}layers${NC}              show files in lower/, upper/, mnt/"
    echo -e "  ${GREEN}setup${NC}               (re)create layers and remount"
    echo -e "  ${GREEN}mount${NC}               mount without resetting layers"
    echo -e "  ${GREEN}umount${NC}              unmount mnt/"
    echo -e "  ${GREEN}reset${NC}               alias for setup"
    echo -e "  ${GREEN}help${NC}                show this message"
    echo -e "  ${GREEN}exit / quit${NC}         unmount and exit"
    echo ""
    echo -e "  ${BOLD}All other input runs as a Linux command inside mnt/${NC}"
    echo -e "  ${DIM}Commands execute with CWD = mnt/, so relative paths work directly.${NC}"
    echo -e "  ${DIM}You can also use absolute paths like \$MNT, \$LOWER, \$UPPER.${NC}"
    echo ""
    echo -e "  ${BOLD}Example test commands${NC}"
    echo -e "  ${CYAN}ls -la${NC}                        list merged view"
    echo -e "  ${CYAN}cat base.txt${NC}                  read file from lower"
    echo -e "  ${CYAN}echo hello >> base.txt${NC}        trigger CoW — writes to upper/"
    echo -e "  ${CYAN}cat base.txt${NC}                  verify appended content"
    echo -e "  ${CYAN}rm delete_me.txt${NC}              whiteout — file hidden from mnt/"
    echo -e "  ${CYAN}ls delete_me.txt${NC}              should show 'No such file'"
    echo -e "  ${CYAN}touch newfile.txt${NC}             create new file — lands in upper/"
    echo -e "  ${CYAN}mkdir newdir${NC}                  create dir in upper/"
    echo -e "  ${CYAN}echo hi > newdir/x.txt${NC}        write inside new dir"
    echo -e "  ${CYAN}stat base.txt${NC}                 inode / permission info"
    echo -e "  ${CYAN}chmod 644 base.txt${NC}            change permissions"
    echo -e "  ${CYAN}layers${NC}                        inspect all three layers"
    echo ""
}

# ── Mount without reset ───────────────────────────────────────────────────────
do_mount() {
    if is_mounted; then
        warn "mnt/ already mounted"
        return
    fi
    info "Mounting..."
    "$BINARY" "$LOWER" "$UPPER" "$MNT" 2>/dev/null &
    sleep 1
    if is_mounted; then
        ok "Mounted at mnt/"
    else
        err "Mount failed"
    fi
}

# ── REPL ──────────────────────────────────────────────────────────────────────
repl() {
    echo -e "\n  ${DIM}Type ${NC}${GREEN}help${NC}${DIM} for usage. Tab-completion works inside mnt/.${NC}"
    echo -e "  ${DIM}Type ${NC}${GREEN}exit${NC}${DIM} to quit.${NC}\n"

    while true; do
        # Prompt shows mount status
        if is_mounted; then
            prompt="${BOLD}${CYAN}unionfs${NC}${DIM}:${NC}${GREEN}mnt/${NC}${BOLD}\$${NC} "
        else
            prompt="${BOLD}${RED}unionfs (unmounted)${NC}${BOLD}\$${NC} "
        fi

        # Read input with readline support
        IFS= read -r -e -p "$(echo -e "$prompt")" cmd || { echo ""; break; }

        # Add to readline history
        [ -n "$cmd" ] && history -s "$cmd"

        # Trim leading/trailing whitespace
        cmd="$(echo "$cmd" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$cmd" ] && continue

        case "$cmd" in
            exit|quit)
                break
                ;;
            layers|ls-layers|show)
                do_layers
                ;;
            setup|reset)
                do_setup
                ;;
            mount)
                do_mount
                ;;
            umount|unmount)
                if is_mounted; then
                    fusermount -u "$MNT" 2>/dev/null || umount "$MNT" 2>/dev/null || true
                    ok "Unmounted"
                else
                    warn "Not mounted"
                fi
                ;;
            help|h|\?)
                do_help
                ;;
            *)
                if ! is_mounted; then
                    warn "mnt/ is not mounted — run 'setup' or 'mount' first"
                    continue
                fi
                # Run the command with CWD inside mnt/
                # Export paths so the user can reference them
                (
                    export MNT LOWER UPPER
                    cd "$MNT"
                    eval "$cmd"
                )
                status=$?
                if [ $status -ne 0 ]; then
                    echo -e "  ${DIM}exit status: $status${NC}"
                fi
                ;;
        esac
    done
}

# ── Entry point ───────────────────────────────────────────────────────────────
main() {
    # Verify binary exists
    if [ ! -x "$BINARY" ]; then
        banner
        err "Binary not found: $BINARY"
        err "Build it first:  cd $(dirname "$BINARY") && make"
        exit 1
    fi

    banner
    do_setup
    do_layers
    do_help
    repl
    do_teardown
    echo -e "\n  ${BOLD}Goodbye.${NC}\n"
}

main "$@"
