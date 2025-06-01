# This is a big example showing most features; Only use what you need, obv.
when not declared(writeFile): import std/syncio # slimSystem junk
import cron
putEnv "HOME", HOME  # This may seem terse, but it is ANY FULL Nim program
putEnv "PATH", HOME & "/bin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin"

cron.utc    =  false # true=>UTC tm; Use any lib you like to convert test conds
cron.period = 60*sec # Be careful conditions are about round multiples of this!
cron.jitter =  3*sec # Make sleep jitter 3 seconds; 0 is valid but risks herds
cron.tmFmt  = "W %Y/%m/%d-%H:%M:%S %Z: " # Augmented strftime format for logs

# WHEN: WHAT #WHY cron.loop (running EACH PERIOD).  Mostly sorted by frequency.
# In USA [1,2)am reRun;[2,3)am skip => DO NOT USE [1,3)am if Sun in Mar|Nov
cron.loop y,mo,d, h,m,s, ns, w:                  # Time idents can be changed
  DoSync("echo"): echo "hi!"                     # *Sync* Nim code EACH PERIOD
  Do("tmpF"): writeFile "/tmp/m." & $m.int, ""   # Backgnd Nim code EACH PERIOD
  if s == 30.S:                                  # Conditional bkgd job
    Do("WILL NEVER RUN"): discard       # *UNLESS* you change period to 30*sec!
  if (mo,d,h,m) == (Jan,1.D,0.H,0.M):            # `run` wants user IO redirects
    run "HappyNY <"&n&">/var/log/NYE 2>&1", "Annual Job Log Name"
  if h mod 4.H == 0 and m == 9.M:                # Every 4th hr on the 9th min
    r "something"                                # `r` suppresses output
  if (h,m) == ( 0.H,30.M):                       # Every day @0h:30m, run
    runPat HOME & "/.config/cron/daily/*"        #   jobs in dir suppressing IO
  # More vanilla/typical jobs; J(COND, job) = if COND: r job
  J   (h,m) ==     ( 0.H, 2.M): rdateSet         # Desync if in||to not Bug NIST
  sysly mo,d, h,m,w, 0.H, 30.M                   # Sys Mly/Wly/Dly jobs FOR ROOT
  J m mod 15.M == 7: "every-15-at-7"             # 4 times/hour
  J   (h,m) ==      (0.H, 0.M): "train to GA"    # Daily
  J (w,h,m) == (Sat, 3.H, 1.M): "exec fstrim /"  # Keep flash mem writes fast
  J (w,h,m) == (Sat, 3.H,55.M): "xfs_fsr /dev/X" # Keep XFS writes on HDDs fast
  J (d,h,m) == (1.D, 4.H, 1.M): "emaint sync -a" # Monthly pull from G2

# If you have a holiday/business day lib/file then you could import that & do:
#   J bizDayKind.isa(y,mo,d) and (h,m)==(0.H,9.M): "myJob"
