when not declared(doAssert): import std/assertions
import std/[os, posix, random]; export putEnv
proc csys(cmd: cstring): cint {.importc:"system",header:"stdlib.h",discardable.}
template brop(op, T) = # BorrowRelationalOp
  proc op*(a, b: T): bool {.borrow.}

const usec* = 1000; const msec* = 1000*usec; const sec* = 1000*msec #If you like
type WeekDay* = enum Sun=0, Mon, Tue, Wed, Thu, Fri, Sat  # 1) types & globals
type Month* = enum Jan=0, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec
type D* = distinct range[1..31];  brop `==`,D; brop `<=`,D; brop `<`,D
type H* = distinct range[0..23];  brop `==`,H; brop `<=`,H; brop `<`,H
type M* = distinct range[0..59];  brop `==`,M; brop `<=`,M; brop `<`,M
type S* = distinct range[0..59];  brop `==`,S; brop `<=`,S; brop `<`,S
type N* = distinct range[0..sec]; brop `==`,N; brop `<=`,N; brop `<`,N
proc `mod`*[T:Weekday|Month|H|M|D](a, b: T): int = a.int mod b.int # Nicer EVERY

const HOME* {.strdefine.} = "/u/user"   ## crup.sh sets to the building user
const null* {.strdefine.} = "/dev/null" ## I put in /n -> /dev/null symlinks
const n* = " <"&null&">"&null&" 2>&1"   ## /dev/null stdin, stdout, stderr
var utc* = false                        ## Use gmtime_r for both test & logs
var period*: range[1i64..int64.high] = 60*sec ## Avg loop period (ns; see `sec`)
var jitter*: range[0i64..int64.high] =  6*sec ## +- this much jitter
var tmFmt* = "%Y-%m-%d %H:%M:%S %Z: "   ## strftime(2) format for logs
var ut, lgW: bool; var tF: string       # Client unmodifiable copies @Loop Start

template gT(ts) = discard clock_gettime(CLOCK_REALTIME, ts) # 2) Time query &
template cT(ts, tm) =                                       #..conversion.
  discard if ut: gmtime_r(ts.tv_sec, tm) else: localtime_r(ts.tv_sec, tm)
proc Ns*(ts: Timespec): int64 = ts.tv_sec.int64*sec + ts.tv_nsec
proc Ts*(ns: int64): Timespec = (result.tv_sec = Time(ns div sec);
                                 result.tv_nsec =     ns mod sec)

proc lg(tm: var Tm; ts: Timespec; msg: cstring) =     # 3) Logging
  if lgW: (var w = $ts.Ns; discard write(2.cint, w[0].addr, w.len))
  var b: array[4096, char]              # Time stamped log; Len capped @4096B
  var n = strftime(cast[cstring](b[0].addr), b.sizeof.int, tF.cstring, tm)
  if n < 0: n = 0
  let m = min(msg.len, b.sizeof - n - 1)              # Both time stamps & logWr
  copyMem b[n].addr, msg[0].addr, m; b[n + m] = '\n'  #..here are best effort
  discard write(2.cint, b[0].addr, n + m + 1)         #..since exiting is bad.

# 4) Runner helpers
template bkgd(tm, ts, job) =      # Runs job in a detached kid so long jobs do
  var p: Pid                      #..not block loop; I.e. parent just returns.
  if (p = fork(); p == -1): lg tm, ts, "fork failed"
  elif p.int==0: job; quit()      # SIGCHLD Policy below blocks zombies
var saNZ = Sigaction(sa_flags: SA_NOCLDWAIT or SA_NOCLDSTOP)
discard sigaction(SIGCHLD, saNZ)  # Let our kids live/die on their own terms.

template lgDo(tm: var Tm; ts: Timespec; msg: cstring, bg: bool, job) =
  lg tm, ts, msg; if bg: bkgd(tm, ts, job) else: job

proc lgRun(tm: var Tm; ts: Timespec; job: cstring; msg: cstring="") =
  lgDo tm, ts, (if not msg.isNil and msg[0]!='\0': msg else: job),true: csys job

# 5) The main event
template loop*(yr, mo,d, hr,mn,sc,ns, wd, body) = ## See an example for use
  # Sequencing loops means most >0 jitter one cycle should not hit most <0 next.
  # So, want @least /2, but since there can also be kernel jitter & logs do /4.
  doAssert period div 4 > jitter, "cron.jitter is >= cron.period/4"
  var ts, tr, slp, left: Timespec # tr=ts rounded to mulOfPeriod for exact tests
  var tm: Tm                      #..& for job logging in spite of jitter smooth

  # The Basic Actions; Guarded by `if` in all cases but `J` which automates that
  proc run(x:string,msg="") = lgRun tm,ts,x,msg
  proc r(x: string) = run "(" & x & ")" & n     # Two common cases;SERI>|<AL; !&
  proc runPat(p: string) {.used.} = run "for job in "&p&"; do $job "&n&"; done"
  template J(cond, x) {.used.} = (if cond: r x) # `J` for job; THE common case
  template Do(msg: cstring, act) {.used.} = lgDo tm, ts, msg, bg=true, act
  template DoSync(msg: cstring, act) {.used.} = lgDo tm, ts, msg, bg=false, act

  # Make client code immutable copies; Also, note magic W => log wake times.
  ut = utc; let jit = jitter; let per = period
  tF = if tmFmt.len>0 and tmFmt[0]==('W'): lgW=true; tmFmt[1..^1] else: tmFmt
  for i in 0u64 .. uint64.high:                         # Discover NOW&Calc slp
    gT ts; let tn=ts.Ns; let upR = if i == 0: 0 else: per div 2
    slp = Ts(((tn + upR) div per)*per + per + jit - 2*rand(jit) - tn)
    discard nanosleep(slp, left); gT ts                 # Sleep & refresh time
    tr = (((ts.Ns + 2*jit) div per)*per).Ts; cT tr, tm  # Round & Convert
    let yr {.used.} = tm.tm_year.int+1900; let mo {.used.} = tm.tm_mon.Month
    let d  {.used.} = tm.tm_mday.D       ; let hr {.used.} = tm.tm_hour.H
    let mn {.used.} = tm.tm_min.M        ; let wd {.used.} = tm.tm_wday.WeekDay
    let sc {.used.} = tm.tm_sec.S        ; let ns {.used.} = ts.tv_nsec.N
    body        # Above assigns enforce Nim types of params for checking here

# 6) This block sets up re-exec on SIGHUP for updates
let av {.importc: "cmdLine".}: cstringArray # nonLib Unix; importc simple & fast
proc reExec(sigNo: cint) {.noconv, used.} =
  var ts: Timespec; var tm: Tm; gT ts; cT ts, tm; lg tm,ts,"RE-EXEC" # Log actn
  discard execvp(av[0], av)     # pk -sh jobs updates post install of new `jobs`
var sa = Sigaction(sa_handler: reExec, sa_flags: SA_NODEFER)
discard sigaction(SIGHUP, sa)   # NODEFER is critical for a >=2 re-installs

# 7) Pre-defined convenience jobs for the system
const rdateSet* = "rdate -s -u time.nist.gov;hwclock --systohc" ## |init.d/rdate
template sysly*(mo,d, hr,mn, wd) =      ## System mly/wly/dly jobs as root
  if hr == 0.H and mn == 45.M:          # Every day @12a:45 do jobs for packages
    if d  == 1.D: runPat "/etc/cron.monthly/*"  # Q: What is normal cron order
    if wd == Sat: runPat "/etc/cron.weekly/*"   #    of mly/wly/dly dirs?
    runPat "/etc/cron.daily/*"
