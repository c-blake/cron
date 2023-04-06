import std/[os, posix, random]; export putEnv
proc csys(cmd: cstring): cint {.importc:"system",header:"stdlib.h",discardable.}
template brop(op, T) = # BorrowRelationalOp
  proc op*(a, b: T): bool {.borrow.}

type WeekDay* = enum Sun=0, Mon, Tue, Wed, Thu, Fri, Sat
type Month* = enum Jan=0, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec
type H* = distinct range[0..23]; brop `==`,H; brop `<=`,H; brop `<`,H
type M* = distinct range[0..59]; brop `==`,M; brop `<=`,M; brop `<`,M
type D* = distinct range[1..31]; brop `==`,D; brop `<=`,D; brop `<`,D
proc `mod`*[T:Weekday|Month|H|M|D](a, b: T): int = a.int mod b.int # Nicer EVERY

const HOME* {.strdefine.} = "/u/user"   ## crup.sh sets to the building user
const null* {.strdefine.} = "/dev/null" ## I put in /n -> /dev/null symlinks
const n* = " <"&null&">"&null&" 2>&1"   ## /dev/null stdin, stdout, stderr
var utc* = false                        ## Use gmtime_r for both test & logs
var jitter*: range[0..30] = 6           ## Add up to this many sec of jitter
var tmFmt* = "%Y-%m-%d %H:%M:%S %Z: "   ## strftime(2) format for logs

template gT(ts, tm) =
  discard clock_gettime(CLOCK_REALTIME, ts)
  if utc: discard gmtime_r(ts.tv_sec, tm)
  else: discard localtime_r(ts.tv_sec, tm)

proc lg(tm: var Tm; msg: cstring; fmt=tmFmt) =
  var b: array[4096, char]              # Time stamped log; Len capped @4096B
  var n = strftime(cast[cstring](b[0].addr), b.sizeof.int, fmt, tm); if n<0: n=0
  let m = min(msg.len, b.sizeof - n - 1)              # Both time stamps & log
  copyMem b[n].addr, msg[0].addr, m; b[n + m] = '\n'  #..here are best effort
  discard write(2.cint, b[0].addr, n + m + 1)         #..since exiting is bad.

template lgDo(tm: var Tm; msg: cstring, job) =
  lg tm, msg; var p: Pid
  if (p = fork(); p == -1): lg(tm, "fork failed")
  elif p.int==0: job; quit() # Run job in a kid; SIGCHLD Policy blocks zombies.
  else: discard              # Parent returns so long jobs do not block loop.
var saNZ = Sigaction(sa_flags: SA_NOCLDWAIT or SA_NOCLDSTOP)
discard sigaction(SIGCHLD, saNZ)  # Let our kids live/die on their own terms.

proc lgRun(tm: var Tm; job: cstring; msg: cstring="") =
  lgDo tm, (if not msg.isNil and msg[0]!='\0': msg else: job): csys job

template loop*(yr, mo,d, hr,mn, wd, body) =     ## See an example for use
  var tm: Tm

  proc run(x: string, msg="") = lgRun tm, x,msg # The 5 Basic Actions
  proc r(x: string) = run "(" & x & ")" & n     # Two common cases;SERI>|<AL
  proc runPat(p: string) {.used.} = run "for job in "&p&"; do $job "&n&"; done"
  template J(cond, x) {.used.} = (if cond: r x) # `J` for job; THE common case
  template Do(msg: cstring, act) {.used.} = lgDo tm, msg, act

  var ts, slp, left: Timespec
  while true:
    discard clock_gettime(CLOCK_REALTIME, ts)   # Sleep until next loop boundary
    slp.tv_sec  = Time(60 - ts.tv_sec.int mod 60 - 1)
    slp.tv_nsec = if ts.tv_nsec > 0: 1_000_000_000 - ts.tv_nsec else: 0
    if jitter > 0:                              # Add jitter*1e9 random ns
      slp.tv_nsec += rand(jitter*1_000_000_000)
      slp.tv_sec   = Time(slp.tv_sec.int + slp.tv_nsec div 1_000_000_000)
      slp.tv_nsec  = slp.tv_nsec mod 1_000_000_000
    discard nanosleep(slp, left); gT ts, tm     # Sleep, then refresh time
    let yr {.used.} = tm.tm_year.int + 1900     # Should we add 1900?
    let mo {.used.} = tm.tm_mon.Month           # These assignments are just to
    let d  {.used.} = tm.tm_mday.D              #..enforce Nim typing of params
    let hr {.used.} = tm.tm_hour.H      # Below rounds for exact user tests
    let mn {.used.} = (if tm.tm_sec > 55: tm.tm_min + 1 else: tm.tm_min).M
    let wd {.used.} = tm.tm_wday.WeekDay
    tm.tm_sec = 0.cint                  # Clamp second to 0 for log msgs easy to
    body                                #..correlate w/jobs in spite of jitter.

# This block sets up re-exec on SIGHUP for updates
let av {.importc: "cmdLine".}: cstringArray # nonLib Unix; importc simple & fast
proc reExec(sigNo: cint) {.noconv, used.} =
  var ts: Timespec; var tm: Tm; gT ts, tm; lg tm, "RE-EXEC" # Log re-start
  discard execvp(av[0], av)     # pk -sh jobs updates post install of new `jobs`
var sa = Sigaction(sa_handler: reExec, sa_flags: SA_NODEFER)
discard sigaction(SIGHUP, sa)   # NODEFER is critical for a >=2 re-installs

# Pre-defined convenience jobs for the system
const setClock* = "rdate -s -u time.nist.gov;hwclock --systohc" ## |init.d/rdate
template sysly*(mo,d, hr,mn, wd) =      ## System mly/wly/dly jobs as root
  if hr == 0.H and mn == 45.M:          # Every day @12a:45 do jobs for packages
    if d  == 1.D: runPat "/etc/cron.monthly/*"  # Q: What is normal cron order
    if wd == Sat: runPat "/etc/cron.weekly/*"   #    of mly/wly/dly dirs?
    runPat "/etc/cron.daily/*"

#Qs: Loop over skipped minutes on time jumps (susp-resume)? {But - time storms!}
# Sleep more by pre-compute next day/week of sleeps w/body to a lgRun run=false?
# Best to allow `cron.period=300`->Any sec(|even ns)? Need better rounding logic
