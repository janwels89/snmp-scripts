#!/bin/sh
# SPDX-FileCopyrightText: 2025 Jan Welslau jan.welslau@gmail.com
# SPDX-License-Identifier: GPL-3.0-or-later

########################################################################
##  check_apt - Bash script to monitor available apt updates          ##
##  Rewrite of nagios-plugins/plugins/check_apt.c                     ##
##  Author: Jan Welslau                                               ##
## License: GPL v3                                                    ##
##  Modified: 2025-11-28                                              ##
########################################################################

PROGNAME="check_apt"
PACKAGES_WARNING=1
VERBOSE=0
DO_UPDATE=0
ONLY_CRITICAL=0
UPGRADE_MODE="upgrade"
UPGRADE_OPTS="-o Debug::NoLocking=true -s -qq"
UPDATE_OPTS="-q"
INCLUDE_RE=""
EXCLUDE_RE=""
CRITICAL_RE=""
INPUT_FILE=""

# Default Debian/Ubuntu security regex
DEFAULT_SECURITY_RE="(Debian-Security:|Ubuntu:[^/]*/[^-]*-security)"

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

max_state() { [ "$1" -gt "$2" ] && echo "$1" || echo "$2"; }

usage() {
    echo "Usage: $PROGNAME [[-d|-u|-U]opts] [-n] [-t timeout] [-w packages-warning]"
}

# ---------------- ARGUMENT PARSING ----------------
while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verbose) VERBOSE=$((VERBOSE+1));;
        -u|--update)
            DO_UPDATE=1
            [ -n "$2" ] && UPDATE_OPTS="$2" && shift
            ;;
        -U|--upgrade)
            UPGRADE_MODE="upgrade"
            [ -n "$2" ] && UPGRADE_OPTS="$2" && shift
            ;;
        -d|--dist-upgrade)
            UPGRADE_MODE="dist-upgrade"
            [ -n "$2" ] && UPGRADE_OPTS="$2" && shift
            ;;
        -n|--no-upgrade) UPGRADE_MODE="none";;
        -i|--include) INCLUDE_RE="${INCLUDE_RE:+$INCLUDE_RE|}$2"; shift;;
        -e|--exclude) EXCLUDE_RE="${EXCLUDE_RE:+$EXCLUDE_RE|}$2"; shift;;
        -c|--critical) CRITICAL_RE="${CRITICAL_RE:+$CRITICAL_RE|}$2"; shift;;
        -o|--only-critical) ONLY_CRITICAL=1;;
        --input-file) INPUT_FILE="$2"; shift;;
        -w|--packages-warning) PACKAGES_WARNING="$2"; shift;;
        -h|--help) usage; exit $STATE_OK;;
    esac
    shift
done

[ -z "$CRITICAL_RE" ] && CRITICAL_RE="$DEFAULT_SECURITY_RE"

run_cmd() {
    MODE="$1"

    if [ "$MODE" = "update" ]; then
        CMD="apt-get $UPDATE_OPTS update"
    else
        CMD="apt-get $UPGRADE_OPTS $UPGRADE_MODE"
    fi

    if [ -n "$INPUT_FILE" ]; then
        cat "$INPUT_FILE"
    else
        sh -c "$CMD" 2>&1
    fi
    return $?
}

# ---------------- OPTIONAL UPDATE ----------------
RESULT=$STATE_OK
STDERR_WARN=0
EXEC_WARN=0

if [ "$DO_UPDATE" = 1 ]; then
    UPDATE_OUTPUT="$(run_cmd update)"
    UPDATE_STATUS=$?

    echo "$UPDATE_OUTPUT" | grep -q "^[EW]" && STDERR_WARN=1

    if [ $UPDATE_STATUS -ne 0 ]; then
        EXEC_WARN=1
        RESULT=$STATE_CRITICAL
    elif [ $STDERR_WARN -eq 1 ]; then
        RESULT=$STATE_WARNING
    fi
fi

# ---------------- UPGRADE DRY RUN ----------------
if [ "$UPGRADE_MODE" = "none" ]; then
    echo "APT OK: upgrade disabled"
    exit 0
fi

UPGRADE_OUTPUT="$(run_cmd upgrade)"
UPGRADE_STATUS=$?

if [ $UPGRADE_STATUS -ne 0 ]; then
    EXEC_WARN=1
    RESULT=$(max_state $RESULT $STATE_UNKNOWN)
fi

# ---------------- FILTER REAL UPGRADES ----------------
INST_LINES=$(printf "%s\n" "$UPGRADE_OUTPUT" | grep "^Inst ")

FILTERED_LINES=""
for LINE in $INST_LINES; do

    # Must contain old version [x]
    echo "$LINE" | grep -Eq "\[[0-9A-Za-z.+:~_-]+\]" || continue

    # Must contain new version (x source)
    echo "$LINE" | grep -Eq "\([0-9A-Za-z.+:~_-]+ " || continue

    # Include filter
    if [ -n "$INCLUDE_RE" ]; then
        echo "$LINE" | grep -Eq "$INCLUDE_RE" || continue
    fi

    # Exclude filter
    if [ -n "$EXCLUDE_RE" ]; then
        echo "$LINE" | grep -Eq "$EXCLUDE_RE" && continue
    fi

    FILTERED_LINES="${FILTERED_LINES}\n${LINE}"
done

PKG_COUNT=$(printf "%b" "$FILTERED_LINES" | sed '/^\s*$/d' | wc -l)
CRIT_COUNT=$(printf "%b" "$FILTERED_LINES" | grep -E "$CRITICAL_RE" | wc -l)

# ---------------- STATE DECISION ----------------
if [ "$CRIT_COUNT" -gt 0 ]; then
    RESULT=$STATE_CRITICAL
elif [ "$ONLY_CRITICAL" -eq 0 ] && [ "$PKG_COUNT" -ge "$PACKAGES_WARNING" ]; then
    RESULT=$(max_state $RESULT $STATE_WARNING)
fi

# ---------------- OUTPUT (IDENTICAL TO ORIGINAL) ----------------
STATUS_STR="UNKNOWN"
[ $RESULT -eq 0 ] && STATUS_STR="OK"
[ $RESULT -eq 1 ] && STATUS_STR="WARNING"
[ $RESULT -eq 2 ] && STATUS_STR="CRITICAL"

echo "APT $STATUS_STR: $PKG_COUNT packages available for $UPGRADE_MODE ($CRIT_COUNT critical updates). |available_upgrades=$PKG_COUNT;;;0 critical_updates=$CRIT_COUNT;;;0"

exit $RESULT

