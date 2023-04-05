Overview
========
The whole `cron` system design has accumulated much complexity that is no longer
needed and was maybe never a great idea - from a setuid-root (or cron) crontab
to manage job files, to demons running as root changing UIDs and hopefully not
leaking anything, to bespoke syntaxes for specifying periodicity.  Even the more
spartan busybox crond/crontab is 1200 lines of C.[^1]

Instead of all that, I give you `cron`: cron in Nim with its core only about 50
non-space/comment lines, 12 lines for bonus/quality of life & a 20 line shell
script to update & install new versions of your periodic tasks.  This is a
simplification along the lines of [kslog](https://github.com/c-blake/kslog).

***The key idea is re-cast the cron problem to be "a library to make writing a
cron-like demon easy for a user" that uses some independent way to get user
demons launched at boot.[^2]***  To my knowledge this is a novel take (but too
simple to publish anywhere).[^3]

Such a demon just runs as a regular, unprivileged user all the time.  It can be
written with a fully Turing complete programming language and any library that
makes a main loop and "run now" time tests and launch activity easy.  Indeed,
you can write Nim functions rather than scripts to do any actions you want.[^4]

If your system/sysadmin provides no way to launch a user-demon at boot then you
may need to launch it yourself.  One traditional way to ensure something comes
up at boot as an unprivileged user has been to use a traditional cron with some
"check for existence" to avoid duplicates.  By rotating that to "have sysadmin
provide some other way to launch at boot" and then relying upon a compiler/PL,
the entire problem is simplified drastically.  Personally, I just put something
in my `rc` scripts for my regular user.  I would guess systemd has some story.

Some Niceties
=============
There are basic syntax niceties.  These are best understood by just looking at
[`jobsE0.nim`](examples/jobsE0.nim).  Among these are `sysly` to do `runPat`
over the monthly, weekly, and daily system job directories for the root demon.

Compile-time Checked Ranges
---------------------------
Using a Nim distinct range[0..23] for "hours" prevents you from successfully
compiling a program with dumb mistakes in numbers.  Similar ideas are enforced
on the other common time fields.  The only cost is you have to write ".H" after
using an hour.  This also prevents mistakes if you mismatch fields in a tuple,
such as `(m,h) == (0.H, 30.M)`.  Similar comments apply to month/weekday enums
or days of the month.  (No calendar of which months have how many days is done,
however.)

While this cannot prevent you from accidentally running a job every minute, it
can prevent a lot of other dumb mistakes.

Re-compile/updates with [`crup.sh`](crup.sh)
--------------------------------------------
One thing `crontab` does is tell the cron demon to re-read job configs.  That
functionality is replaced here by either the provided `crup.sh` or some similar
device of your own creation.  Basically, `cron.nim` programs just re-exec when
sent a `SIGHUP`.  So, `crup.sh` just checks if the binary executable is out of
date, recompiles if so, and sends `SIGHUP` if all that worked.  So, you just
edit your jobs program and run `./crup.sh` & done.[^5]

Personally, I like to have a `/n -> /dev/null` symlink on my systems (this grew
out of a Zsh global alias) to reduce ballast.  In this case, it also helps log
messages be shorter but still explicit.  So, `$n` & `$h` for host name and
`$nimc` are all overridable environment variables.  I.e., what I run on my
system is `n=/n nimc='nim c --mm:arc' ./crup.sh`.  If you have many hosts to
compile for you can `for h in A B C; do sh -c "h=$h ./crup.sh"; done`.  Program
names are arbitrary - I just use `jobsXuser` as an easy convention.  It seems
likely you will want to use `crup.sh` just as a basis to write your own.[^6]

Version Control
---------------
While one *can* put cron jobs files under version control and use the crontab
program to manage such, this careful activity "feels" more "natural" with actual
source code in a prog.lang.  This is a more higher order aspect, of course.

Spread/Jitter
-------------
A more subtle one is the `cron.spread` variable.  One hazard I have run into
unaddressed by most `cron`s is that of "load spikes".  Essentially, just one
centralized demon (without even a natural desync of process scheduling) waking
up every minute and launching various activity for various users spikes system
load.  I have seen such cause UDP packet loss and even actual data loss in
financial data systems.

One mitigation is to add a random sleep before programs to jitter/desync system
activity.  This advice is probably as old as exponential back off, but just to
give a concrete example the
[`certbot`](https://stackoverflow.com/questions/41535546/how-do-i-schedule-the-lets-encrypt-certbot-to-automatically-renew-my-certificat)
guys were recommending it.  However, it is less costly to have `cron.loop` just
sleep by an extra random amount, and it is best to default to a non-zero amount.
So, that is what this `cron` library does.[^7]

Jobs written with `cron` are in fact usually very low overhead - on the order of
100 parts per billion of one CPU (much like `kslog`).  I have not done so, but I
suspect this could be made even lower without compromising Turing completeness
by "faking the future" to tests in a batch to compute much longer sleeps.[^8]
This would, however, break jobs that reach out to dynamic system state, e.g. the
presence of files, to decide if they run (which cronds do not even allow).

Time Zones
----------
Even more subtle than jitter/desynchronization is the never ending morass of
time zones.  If you like, you can just set `cron.utc = true` and then use UTC
for everything.  If you have a Nim library you like to convert to local zones
then you can engage that as inline code right in your tests (in Nim with
probably some type conversions to `int`).  There is no new specification
language to learn - only function calls/lib access in Nim (or if you rewrite
this in your PL of choice).

Missing Things
==============
`crond` detects non-empty output and spams users with local emails that these
days may not even be routed to somewhere they will be seen.  This seems.. less
than useful.  So, `cron.nim` does not do that.  In fact, `cron.nim` does not
close inherited file descriptors on its own.  I usually run my demons with a
wrapper program that does that[^9].  Hence, if you do not re-direct your output
to a file, it will probably just get put to the launching demon's fds, like a
/var/log/cron0 or something.  For this reason, even if you do *usually* use a
wrapper program, it is better practice to have your jobs redirect their output.

`cron.nim` *does* make it easy to redirect to /dev/null.  The `J` job `template`
does this by default, for example.  But if you have somewhere you want things to
go, like `/var/log/HappyNY` in the example jobs program, you can just do that.
Or, if the sysadmin does not let you put things in `/var/log`, but only where
you have a disk quota, like `$HOME/log/`, then you can direct it there.  Or if
that is a network filesystem, `/var/tmp/$ME/log`.  Or wherever.

[^1]: I can only speculate why the original cron system was so complex - that is
more a question for TUHS.

[^2]: Well, and a demon for the system as well.

[^3]: Famous last words.  And right here is "somewhere".

[^4]: While Nim does make for a compact syntax for this use case, I use hardly
anything that could not be done with C preprocessor macros or facilities in
Python or many PLs.  In fact, the first version of this system was in ANSI C and
barely any larger than the Nim.

[^5]: If you miss the full `crontab -e` experience you can always put a "vim
jobsXme.nim" at the top of crup.sh. ;-)

[^6]: This kind of "config-free" programming is not unlike the [suck
less](https://suckless.org/) philosophy of `st` or `dwm` where you just edit a
header file to configure things.  Here the library makes it such that the entire
program is often not even a whole page.

[^7]: If you prefer "more precise" scheduling, just set `cron.spread = 0` in
your own cron-like programs.

[^8]: While the same amount of total calculation would happen, CPU caching and
other effects might mean up to 10X less actual time/power consumption done in a
batch.  Also more infrequent wake ups would be nicer to the system from the
perspective of everything else that needs to be spun up every minute in the
usual mode.  This smells like something someone has probably written a paper on.
Happy to cite if someone provides a reference.

[^9]: If you ask nicely I can add a tiny demonize proc to `cron.nim` to call
before `cron.loop` or port my C program wrapper to Nim & toss it in `bu`.
