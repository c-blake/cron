when not declared(doAssert): import std/assertions
import std/[os, posix, random]; export putEnv
when defined(release): randomize()
proc csystem(cmd: cstring): cint {.importc: "system", header: "stdlib.h".}
template bbop(op, T) =
  proc op*(a, b: T): bool {.borrow.}    # BorrowBinaryOp

# 1) types & globals    #{.push raises: [].}
const usec* = 1000; const msec* = 1000*usec; const sec* = 1000*msec #If you like
type WeekDay* = enum Sun=0, Mon, Tue, Wed, Thu, Fri, Sat
type Month* = enum Jan=0, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov, Dec
type D* = distinct range[1..31];  bbop `==`,D; bbop `<=`,D; bbop `<`,D
type H* = distinct range[0..23];  bbop `==`,H; bbop `<=`,H; bbop `<`,H
type M* = distinct range[0..59];  bbop `==`,M; bbop `<=`,M; bbop `<`,M
type S* = distinct range[0..59];  bbop `==`,S; bbop `<=`,S; bbop `<`,S
type N* = distinct range[0..sec]; bbop `==`,N; bbop `<=`,N; bbop `<`,N
proc `mod`*[T: WeekDay|Month|H|M|D](a,b: T): int = a.int mod b.int # Nicer EVERY

const HOME* {.strdefine.} = "/u/user"         ## crup.sh sets to user building
const null* {.strdefine.} = "/dev/null"       ## I like /n -> /dev/null symlinks
const n* = " <" & null & ">" & null & " 2>&1" ## stdin,stdout,stderr: /dev/null

var utc* = false                              ## Use gmtime_r for both test&logs
var period*: range[1i64..int64.high] = 60*sec ## Avg loop period (ns; see `sec`)
var jitter*: range[0i64..int64.high] =  6*sec ## +- this much jitter
var tmFmt* = "%Y-%m-%d %H:%M:%S %Z: "         ## strftime(2) format for logs

var ut, lgWU: bool                            # Client immutable copies fixed at
var tF: string                                #..loop start, but ref'd earlier.

# 2) Time query & conversion
template gT(ts) = discard clock_gettime(CLOCK_REALTIME, ts) # g)et T)ime

template cT(ts, tm) =                                       # c)onvert T)ime
  discard if ut: gmtime_r(ts.tv_sec, tm) else: localtime_r(ts.tv_sec, tm)

proc Ns*(ts: Timespec): int64 = ts.tv_sec.int64*sec + ts.tv_nsec

proc Ts*(ns: int64): Timespec = (result.tv_sec = Time(ns div sec); # T)ime s)pec
              result.tv_nsec = typeof(result.tv_nsec)(ns mod sec))

# 3) Logging; Wake-up nice BUT log-noisy(&jittered); Always want "rounded time".
proc lg(tm: var Tm; ts: Timespec; msg: cstring) =
  if lgWU: (var w = $ts.Ns; discard write(2.cint, w[0].addr, w.len))  # Wake-up
  var b: array[4096, char]              # Time stamped log; Len capped @4096B
  let n = max(0, strftime(cast[cstring](b[0].addr),b.sizeof.int, tF.cstring,tm))
  let m = min(msg.len, b.sizeof - n - 1)                   # Timestamps & logWr
  copyMem b[n].addr, msg[0].unsafeAddr, m; b[n + m] = '\n' #..are best effort
  discard write(2.cint, b[0].addr, n + m + 1)              #..since exit is bad.

# 4) Logging-Runner helpers
template bkgd(tm, ts, job) =      # Runs job in a detached kid so long jobs do
  var p: Pid                      #..not block loop; I.e. parent just returns.
  if (p = fork(); p == -1): lg tm, ts, "fork failed"
  elif p.int==0: job; quit()      # SIGCHLD Policy below blocks zombies

var saNZ = Sigaction(sa_flags: SA_NOCLDWAIT or SA_NOCLDSTOP)
discard sigaction(SIGCHLD, saNZ)  # Let our kids live/die on their own terms.

template lgDo(tm: var Tm, ts: Timespec, msg: cstring, bg: bool, job) =
  lg tm, ts, msg
  if bg: bkgd(tm, ts, job) else: job

proc lgRun(tm: var Tm, ts: Timespec, job: cstring, msg: cstring="") =
  lgDo tm, ts, (if not msg.isNil and msg[0] != '\0': msg else: job), true:
    discard csystem(job)

# 5) The main event loop
template loop*(yr, mo,d, hr,mn,sc,ns, wd, body) = ## See an example for use
  # Sequencing loops means most >0 jitter one cycle should not hit most <0 next.
  # So, want @least /2, but since there can also be kernel jitter & logs do /4.
  doAssert period div 4 > jitter, "cron.jitter is >= cron.period/4"
  var ts, tr, slp, left: Timespec # tr=ts rounded to mulOfPeriod for exact tests
  var tm: Tm                      #..& for job logging in spite of jitter smooth

  # BASIC ACTIONS; Client `if`-guards in all cases but `J` which automates that
  proc run(j: string, msg="") {.used.} = lgRun tm, ts, j, msg
  proc r(j: string) {.used.} = run "("&j&")"&n  # Two Common Cases: Solo & Dir
  proc runPat(p: string) {.used.} = run "for j in "&p&"; do $j "&n&"; done"
                                                # ';' not '&' =>SERI^AL above
  template DoSync(msg: cstring, act) {.used.} = lgDo tm, ts, msg, bg=false, act
  template Do(msg: cstring, act) {.used.} = lgDo tm, ts, msg, bg=true, act

  template J(cond, cmd) {.used.} = (if cond: r cmd)           # `J` for Job
  template j(cond, cmd) {.used.} = (if cond: r "exec " & cmd) # Above w/exec

  # Set client code immutable copies; Note also: Magic "^W" =>Log Wake-Up times.
  ut = utc; let jit = jitter; let per = period
  tF = if tmFmt.len>0 and tmFmt[0]==('W'): lgWU=true; tmFmt[1..^1] else: tmFmt

  for i in 0u64 .. uint64.high:         # THE MAIN WRAPPED LOOP
    let upR = if i == 0: 0 else: per div 2      # Do not upRound 1st one
    gT ts; let tn = ts.Ns                       # getTm; calc sleep `slp`
    slp = Ts(((tn + upR) div per)*per + per + jit - 2*rand(jit) - tn)
    discard nanosleep(slp, left)                # Sleep
    gT ts                                       # Refresh time upon wake-up
    tr = (((ts.Ns + 2*jit) div per)*per).Ts     # Round "now" to period boundary
    cT tr, tm                                   # Convert & Bind for body
    let yr {.used.} = tm.tm_year.int+1900; let mo {.used.} = tm.tm_mon.Month
    let d  {.used.} = tm.tm_mday.D       ; let hr {.used.} = tm.tm_hour.H
    let mn {.used.} = tm.tm_min.M        ; let sc {.used.} = tm.tm_sec.S
    let ns {.used.} = ts.tv_nsec.N       ; let wd {.used.} = tm.tm_wday.WeekDay
    body  # Above bindings enforce Nim types of params for TESTing in this body

# 6) Establish SIGHUP handling for updating rules via re-exec of jobs program
let av {.importc: "cmdLine".}: cstringArray # NonLib Unix; importc simple & fast

proc reExec(sigNo: cint) {.noconv, used.} = # Logging re-exec
  var ts: Timespec; var tm: Tm; gT ts; cT ts, tm; lg tm, ts, "RE-EXEC"
  discard execvp(av[0], av)                 # `pk -sh jobs` after any re-install

var sa = Sigaction(sa_handler: reExec, sa_flags: SA_NODEFER)
discard sigaction(SIGHUP, sa)   # NODEFER is critical for a >=2 re-installs

# 7) Pre-defined convenience jobs for the system
const rdateSet* = "rdate -s -u time.nist.gov;hwclock --systohc" ## |init.d/rdate

template sysly*(mo,d,hr,mn,wd, hh:typed=0.H,mm:typed=30.M)=##System m/w/dly jobs
  if (hr, mn) == (hh, mm):          # Every day @hh:mm do /etc/cron.* jobs
    if d  == 1.D: runPat "/etc/cron.monthly/*"  # Q: What is normal cron's order
    if wd == Sat: runPat "/etc/cron.weekly/*"   #    for mly/wly/dly job dirs?
    runPat "/etc/cron.daily/*"
