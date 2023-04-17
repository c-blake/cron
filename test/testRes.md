On an *otherwise idle* system[^1], running a 1ms period test as root:[^2]
```
./meas.sh 2>/dev/shm/i; awk '{print $1%1e6}' /dev/shm/i |
    sort -n | gnuplot -e 'plot "-" u ($1/1e6):0'
```
I get a 99.9% worst lag into the period of about 0.149 ms.  Under more moderate
load (nim `build_all.sh` w/firefox & UHD video playing) with `chrt` & `taskset`,
I saw 99.9% samples under 30% off cycle, though the tail is heavy enough that
under 10/60e3 made it all the way through the 1ms period (some all the way to
the end!).  Seeing load *helps* the median & thinking full freq CPUS a likely
cause, I ran as competing work 3 "burn-cpu" instances (which just loop in an
adder doing no syscalls, IO, or mem ops).  This run yielded very narrow misses
(Median overshoot only 6.37us w/IQR 267 ns; Max of 60,000 samples only 10us!).
Here's a plot of this (very basic) evaluation:[^3]
![wakeUps](https://raw.githubusercontent.com/c-blake/cron/main/test/wakeUps.png)

This makes 1ms seem "practical-ish" (though likely wasteful!).  At that rate,
jobs demons use ~1% of 1 CPU.  Personally, I *boost* my period by 6 orders of
magnitude to 15\*60sec.  The way `cron.nim` works currently will not run jobs if
their time slot is missed (this is not unique to `cron.nim`).[^4]  So, longer is
also safer.  Full eval of Linux scheduling is out of scope, but there are surely
loads that can even mess up 60s period wake-ups.

How low can we push the period & still have this check-the-time-sleep program
concept work?  On the 3 burn-cpus but otherwise idle system load, period=10us
gives focused wake ups (q.99-q.01=1.2us).  *However*, they are shifted 60% (6us)
off target wake-up.  That lag seems similar for many periods.  Thus, scheduling
gets misleading around period=15-20us,[^5] but kernel lag calibration can maybe
improve that to 3us given 1.2us.  One can surely play with other policies (e.g.
chrt -d) & CPUs.  HW/kernel behavior varies under stress.  BTW, all this is
intended only to inspire others to do their own experiments, not be the last
word (on anything!).

Of course, it's rare to need periodic cron-like work at even 1s boundaries, let
alone 3us.  If you do change `period`, be careful that time conditions all use
period-rounded values or tests will never match.[^6]

[^1]: This is all on a 4-core i7-6700k at 4.7GHz with no hyper-threading with an
nVidia GPU running Linux 6.2.8.  Idle means no X11/etc. and all system demons
are SIGSTOPed (but I was too lazy to unplug the network).

[^2]: 1ms is not unlike original cronds written in a naive 5GHz vs. 5MHz sense,
6-way superscalar, ~10 core sense.

[^3]: An early lesson in all systems programming is that more contention yields
a lot more complexity in system dynamics.

[^4]: If you think `at` can save you, that is usually implemented *on top* of
cron, not via `sleep;run` - since cron will (usually) come up on reboots.  I
figure if I cannot get a chrt elevated process scheduled in a small fraction of
15 min then I almost surely have bigger worries than a cron job not running. ;)

[^5]: Of course, the jitter feature can make it misleading at *any* time scale,
but that is intended load spreading/desync, not a system limitation.  Numerical
coincidence of 1e-3/15e-6=~60 makes it amusing to speculate if anyone tried
cranking down 1970s crond to 1 second sleeps with similar results.  Ask TUHS.

[^6] Also, strftime does not support sub-seconds, but you can do e.g. `tmFmt =
"W %Y/%m/%d-%H:%M:%S."; Do(align($ns.int, 9, '0') & " myThing")`.
