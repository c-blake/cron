#!/bin/sh
if [ $# -lt 2 -o $# -gt 3 ]; then
    cat <<EOF
Usage:
  [n=/dev/null] [nimc='nim c'] $0 DEST_DIR JOBS_PROG [/path/to/cron.nim]

This build script replaces \`cron -e\`. You edit whichever .nim file has jobs &
point this at the destination directory, the binary exec file, and optionally
cron.nim itself.  This script will, if necessary, compile, install & SIGHUP the
program, but otherwise exit cleanly.  Demons must still be launched at boot
however is apt for your system, e.g. from /etc/local.d/local.start | etc.

This only works on Linux right now (since \`procs\` only works on Linux).
EOF
  exit 1
fi
dst="$1"; j="$2"
set -e
: ${n:="/dev/null"}                             # User can n=/n to override
: ${nimc:="nim c"}                              # Or user can nimc="nim c .."
if [ $# -gt 2 ]; then                           # Be like `make` 2-ways
  [ "$dst/$j" -nt "$j.nim" -a "$dst/$j" -nt "$3" ] &&
    { echo "$j is up to date."; exit 0; }
else [ "$dst/$j" -nt "$j.nim" ] && { echo "$j is up to date."; exit 0; }
fi

$nimc -d:HOME="$HOME" -d:null="$n" -d:danger $j # Compile jobs program
install -cvm755 "$j" "$dst"                     # Copy bin.exec into dst
procs find --actions=kill -shup "$j"            # Make running version re-exec
rm -f "$j"                                      # Nix built; Doesn't clear cache
