#!/bin/sh
# SPDX-FileCopyrightText: 2025 Jan Welslau jan.welslau@gmail.com
# SPDX-License-Identifier: GPL-3.0-or-later

########################################################################
##  check_softwareupdate - Monitor available macOS updates            ##
##  inspired by check_apt  (nagios-plugins/plugins/check_apt.c)       ##
##  Author: Jan Welslau                                               ##
##  License: GPL v3                                                   ##
##  Modified: 2025-12-19 (inital release)                             ##
########################################################################

PROGNAME="check_softwareupdate"
PACKAGES_WARNING=1
VERBOSE=0
DO_UPDATE=0
ONLY_CRITICAL=0
INCLUDE_RE=""
EXCLUDE_RE=""
CRITICAL_RE="(Security|Critical|macOS.*Update|Firmware|Safari)"
INPUT_FILE=""

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

max_state() { [ "$1" -gt "$2" ] && echo "$1" || echo "$2"; }

usage() {
    echo "Usage: $PROGNAME [-v] [-u] [-i regex] [-e regex] [-c regex] [-o] [--input-file file] [-w num]"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -v|--verbose) VERBOSE=$((VERBOSE+1));;
        -u|--update) DO_UPDATE=1;;
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

run_cmd() {
    if [ -n "$INPUT_FILE" ]; then
        cat "$INPUT_FILE"
    else
        softwareupdate -l 2>&1
    fi
    return $?
}

RESULT=$STATE_OK
STDERR_WARN=0
EXEC_WARN=0

if [ "$DO_UPDATE" = 1 ]; then
    UPDATE_OUTPUT="$(run_cmd)"
    UPDATE_STATUS=$?
    echo "$UPDATE_OUTPUT" | grep -q "No new software available." && STDERR_WARN=0 || STDERR_WARN=1
    if [ $UPDATE_STATUS -ne 0 ]; then
        EXEC_WARN=1
        RESULT=$STATE_CRITICAL
    elif [ $STDERR_WARN -eq 1 ]; then
        RESULT=$STATE_WARNING
    fi
fi

UPDATE_OUTPUT="$(run_cmd)"
UPDATE_STATUS=$?
if [ $UPDATE_STATUS -ne 0 ]; then
    EXEC_WARN=1
    RESULT=$(max_state $RESULT $STATE_UNKNOWN)
fi

# Patched logic for correct update counting
INST_LINES=$(echo "$UPDATE_OUTPUT" | grep -E "^\s*\* Label:")

PKG_COUNT=0
CRIT_COUNT=0

while IFS= read -r LINE; do
    # Include filter (if set)
    INCLUDE_OK=1
    if [ -n "$INCLUDE_RE" ]; then
        echo "$LINE" | grep -Eq "$INCLUDE_RE" || INCLUDE_OK=0
    fi
    if [ "$INCLUDE_OK" = "0" ]; then continue; fi
    # Exclude filter (if set)
    if [ -n "$EXCLUDE_RE" ] && echo "$LINE" | grep -Eq "$EXCLUDE_RE"; then continue; fi

    PKG_COUNT=$((PKG_COUNT+1))
    if echo "$LINE" | grep -Eq "$CRITICAL_RE"; then
        CRIT_COUNT=$((CRIT_COUNT+1))
    fi
done <<EOF
$INST_LINES
EOF

if [ "$CRIT_COUNT" -gt 0 ]; then
    RESULT=$STATE_CRITICAL
elif [ "$ONLY_CRITICAL" -eq 0 ] && [ "$PKG_COUNT" -ge "$PACKAGES_WARNING" ]; then
    RESULT=$(max_state $RESULT $STATE_WARNING)
fi

STATUS_STR="UNKNOWN"
[ $RESULT -eq 0 ] && STATUS_STR="OK"
[ $RESULT -eq 1 ] && STATUS_STR="WARNING"
[ $RESULT -eq 2 ] && STATUS_STR="CRITICAL"

echo "SOFTWAREUPDATE $STATUS_STR: $PKG_COUNT updates available ($CRIT_COUNT critical updates). |available_updates=$PKG_COUNT;;;0 critical_updates=$CRIT_COUNT;;;0"

exit $RESULT
