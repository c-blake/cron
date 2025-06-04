# Overview

When things break at 3am, instead of having to figure out what
```
0,6 3 * 3-6 */5 act
```
means in a config file, you can instead read a *whole program*:
```Nim
import cron; loop y,mo,d, h,m,s,ns, w: # Runs EVERY minute
  J w in {Sat,Sun} and mo==Mar and h in 3.H..6.H and m mod 5.M==0: "act"
```
Which you prefer is clearly a question of taste.  To each his own.

# Background

The whole `cron` system design has accumulated much no longer needed complexity
that was maybe never a great idea - from a setuid-root(or cron) crontab to
manage job files, to demons running as root changing UIDs and hopefully not
leaking anything, to bespoke syntaxes for specifying periodicity.  Even spartan
busybox crond/tab is 1200 lines of C.[^1]

Instead of all that, I give you `cron`: cron in Nim with its core only ~75
non-space / comment lines, 12 bonus/quality of life lines & a 20 line shell
script to update & install new versions of a periodic runner.  This is a
simplification along the lines of [kslog](https://github.com/c-blake/kslog).

***The key idea is re-cast the cron problem to be "a library to make writing a
cron-like demon easy for a user" that uses some independent way to get user
demons launched at boot.[^2]***  To my knowledge this is a novel take (but too
simple to publish anywhere).[^3]

Such a demon just runs as a regular, unprivileged user all the time.  It can be
written with a fully Turing complete programming language and any library that
eases a main loop, "run now?" tests and job launch easy.  Indeed, you can
***write Nim code rather than shell scripts*** for your actions.[^4]

If your system/sysadmin provides no way to launch user demons at boot then you
may need to launch it yourself.  Now, one way for unprivileged users to ensure
something comes up at boot has been to use a traditional cron with a "check for
existence" to avoid duplicates.  By rotating that to "have sysadmin provide some
other way to launch at boot" and then relying upon a compiler/PL, the whole
problem is simplified a lot.  Personally, I just put a line in my `rc` scripts
for non-root users.  I would guess systemd has some story.

# Some Niceties

There are basic syntax niceties.  These are best understood by just looking at
[`jobsE0.nim`](examples/jobsE0.nim).  Among these are `sysly` to do `runPat`
over the monthly, weekly, and daily system job directories for the root demon.
For Nim code actions, `if ..: Do` is what you want.  For old-style external
program jobs, see `J`.

## Compile-time Checked Ranges

Using a Nim `distinct range[0..23]` for "hours" prevents you from successfully
compiling a program with dumb mistakes in numbers.  Similar ideas are enforced
on the other common time fields.  The only cost is writing `.H` after using an
hour.  This also prevents mistakes if you mismatch fields in tuples, such as
`(m, h) == (0.H, 30.M)`.  Similar comments apply to month/weekday enums or days
of the month.  (No calendar of days in each month is done, however.)  This will
not stop you from accidentally running jobs every loop (an intended use case).

## Re-compile/updates with [`crup.sh`](crup.sh)

One thing `crontab` does is tell the cron demon to re-read job configs.  That
functionality is replaced here by either the provided `crup.sh` or some similar
device of your own creation.  Basically, `cron.nim` programs just re-exec when
sent a `SIGHUP`.  So, `crup.sh` just checks if the binary executable is out of
date, recompiles if so, and sends `SIGHUP` if all that worked.  So, you just
edit your jobs program and run `./crup.sh` & done.[^5]

Personally, I like to have a `/n -> /dev/null` symlink on my systems (this grew
out of a Zsh global alias).  In this case, it also helps log messages be shorter
but still explicit.  So, `$n` & `$h` for host name & `$nimc` are all overridable
environment variables.  I.e., what I run on my system is `n=/n nimc='nim c
--mm:arc' ./crup.sh`.  If you have many hosts to compile for you can `for h in A
B C; do sh -c "h=$h ./crup.sh"; done`.  Program names are arbitrary. `jobsXuser`
is just one convention.  It is likely you will want to use `crup.sh` just as a
basis to write your own.[^6]

This last bit raises one other virtue of this setup, that process accounting
(e.g. cumulative CPU time) directly identifies which users are doing a lot of
things just via process table data.  In the unlikely case that you have dozens
of user with jobs demons, you may want process merges/roll-ups a la
[procs](https://github.com/c-blake/procs#basics).

## Version Control

While one *can* put cron jobs files under version control and use the crontab
program to manage such, this careful activity "feels" more "natural" with actual
source code in a prog.lang.  "Natural" is higher order & subjective, of course.

## Desync/Jitter

A more subtle knob is the `cron.jitter` variable.  One hazard I have run into
unaddressed by most `cron`s is that of "load spikes".  Essentially, just one
centralized demon (without even a natural desync of process scheduling) waking
up every minute and launching various activity for various users spikes system
load.  I have seen such spikes cause UDP packet loss and even actual data loss
in financial data systems.

One mitigation is to add a random sleep before programs to jitter/desync system
activity.  This advice is probably as old as exponential back off, but just to
give a concrete example the
[`certbot`](https://stackoverflow.com/questions/41535546/how-do-i-schedule-the-lets-encrypt-certbot-to-automatically-renew-my-certificat)
guys were recommending it.  However, it is also easy to generalize this idea to
have `cron.loop` just sleep by extra random amounts of schedule jitter.  So,
that is what this `cron` library does.[^7]

## Overhead

Jobs written with `cron.nim` are usually very low overhead - on the order of 10
parts per billion of one CPU (much like `kslog`).  I haven't done so, but this
can probably be shrunk without much loss of generality by "faking the future"
for all tests in a `loop` in order to compute much longer equivalent sleeps.[^8]
This duration aggregation/compiling would, however, break jobs reaching out to
dynamic system state, e.g. file presence, to decide if they run (which cronds do
not even allow at the scheduling level, though obviously anything can in dynamic
test of what's scheduled).

In practice, when I want low overhead, I just set `cron.period = 30*60*sec` and
schedule stuff on half-hours.  At the other end of the spectrum, one can look at
the limits of [very rapid scheduling](test/testRes.md).

## Time Zones

More subtle than jitter/desynchronization is the unending saga of time zones.
If you like, you can just set `cron.utc = true` to use UTC for everything.  If
you have a Nim lib you like to convert to local zones then you can engage that
as inline code right in your tests (in Nim with probably some type conversions
to `int`).  There is no new specification language to learn - only proc calls /
lib access in Nim (or if you rewrite this in your PL of choice).

# Missing Things

`crond` detects non-empty output and spams users with local emails that these
days may not even be routed to somewhere they will be seen.  This seems.. less
than useful.  So, `cron.nim` does not do that.  In fact, `cron.nim` does not
close inherited file descriptors on its own.  I usually run my demons with a
wrapper program that does that[^9].  Hence, if you do not re-direct your output
to a file, it will probably just get put to the launching demon's fds, like a
/var/log/cron0 or something.  For this reason, even if you do *usually* use a
wrapper program, it is better practice to have your jobs redirect their output.

`cron.nim` does make it easy to redirect job output to `/dev/null`.  E.g., calls
like `J`, `j`, `r` all do this.  If you have somewhere you want things to go,
like `/var/log/HappyNY` in the example program, you can just `>` that at launch.
Or, if a sysadmin doesn't let you put things in `/var/log`, but only where you
have a disk quota, like `$HOME/log/`, you can direct it there.  Or if that is a
net FS & you prefer local then `/var/tmp/$LOGNAME/jobsLog` or wherever.

[^1]: I can only speculate why the original cron system was so complex - that is
more a question for TUHS.

[^2]: Well, and a demon for the system as well.

[^3]: Famous last words.  And right here is "somewhere".  Also, by this I mean
for outright crond-tab replacement, not the zillions of async frameworks with
their various internal work schedulers/timer systems.

[^4]: While Nim does make for a compact syntax for this use case, I use hardly
anything that could not be done with C preprocessor macros or facilities in
Python or many PLs.  In fact, the first version of this system was in ANSI C and
barely larger than the Nim.  Also, `fork` is much cheaper than `fork & exec`.

[^5]: If you miss the full `crontab -e` experience you can always put a "vim
jobsXme.nim" at the top of crup.sh. ;-)

[^6]: This kind of "config-free" programming is not unlike the [suck
less](https://suckless.org/) philosophy of `st` or `dwm` where you just edit a
header file to configure things.  Here the library makes it such that the entire
program is often not even a whole page.

[^7]: If you prefer "more precise" scheduling to load-spreading, just set
`cron.jitter=0` in your own `cron.nim` programs.  Similarly, for log(U(0,1))
PASTA-like jitter.

[^8]: While the same amount of total calculation would happen, CPU caching and
other effects might mean up to 10X less actual time/power consumption done in a
batch.  Also more infrequent wake ups would be nicer to the system from the
perspective of everything else that needs to be spun up every minute in the
usual mode.  This smells like something someone has probably written a paper on.
Happy to cite if someone provides a reference.

[^9]: If you ask nicely I can add a tiny demonize proc to `cron.nim` to call
before `cron.loop` or port my C program wrapper to Nim & toss it in `bu`.
