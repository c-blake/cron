#!/bin/sh
# This build script replaces `cron -e`. You just edit whichever .nim file has
# your jobs & run this ./crup.sh to compile, install & SIGHUP the program.  Run
# as root to update system jobs demon.  Demon must still be launched at boot
# however is apt for your system, e.g. from /etc/local.d/local.start | etc.

[ -e cron.nim ] || {
  echo "Update script must run in the same directory as cron.nim source files."
  exit 1
}
set -e
: ${h:="`hostname`"}                    # Let user say h=X to override
: ${n:="/dev/null"}                     # Let user say n=/n to override
: ${nimc:="nim c"}                      # Let user say n=/n to override

H="$(echo $h | tr a-z A-Z | head -c1)"  # First letter capitalized
u="$(id -u)"                            # uid of invoking process

case "$u" in                            # Use $u to set jobs name $j & $dst
  0) j="jobs${H}0"       ; dst="/usr/local/bin" ;;
  *) j="jobs${H}$LOGNAME"; dst="$HOME/bin"      ;; esac

[ "$dst/$j" -nt "$j.nim" ] && [ "$dst/$j" -nt cron.nim ] && { # Be like `make`
  echo "$j is up to date."; exit 0
}
$nimc -d:HOME="$HOME" -d:null="$n" -d:danger $j  # Compile the jobs program

install -cvm755 "$j" "$dst"             # Copy binary exec into place
rm -f "$j"                              # Remove built copy
procs find -ak -shup "$j"               # Make any running version re-exec
