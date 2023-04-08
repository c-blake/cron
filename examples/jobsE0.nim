# This is a big example showing many features; Only use what you need, obv.
when not declared(writeFile): import std/syncio # slimSystem junk
import cron

putEnv "HOME", HOME  # This may seem terse, but it is ANY FULL Nim program
putEnv "PATH", HOME & "/bin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin"

cron.utc    =  false # true=>UTC tm; Use any lib you like to convert test conds
cron.period = 60*sec # Be careful conditions are about round multiples of this!
cron.jitter =  3*sec # Make sleep jitter 3 seconds; 0 is valid but risks herds
cron.tmFmt  =  "%Y/%m/%d-%H:%M:%S %Z: " # Change tm format for log (note space)

# WHEN,WHAT&WHY cron.loop (which runs EVERY MINUTE) (mostly) sorted by frequency
# In USA [1,2)am reRun;[2,3)am skip => DO NOT USE [1,3)am if Sun in Mar|Nov
loop y,mo,d, h,m,s, ns, w:                       # Idents can be changed
  DoSync("echo"): echo "hi!"                     # *Sync* Nim code every period
  Do("tmpF"): writeFile "/tmp/m." & $m.int, ""   # Backgd Nim code each period
  J   (h,m) ==     ( 0.H, 2.M): rdateSet         # Desync if in||to not Bug NIST
  sysly mo,d, h,m, w                             # Sys Mly/Wly/Dly jobs FOR ROOT
  J m mod 15.M == 7: "every-15-on-the-7"         # 4 times/hour
  J   (h,m) ==      (0.H, 0.M): "train to GA"    # Daily
  J (w,h,m) == (Sat, 3.H, 1.M): "exec fstrim /"  # Keep flash mem writes fast
  J (w,h,m) == (Sat, 3.H,55.M): "xfs_fsr /dev/X" # Keep XFS writes on HDDs fast
  J (d,h,m) == (1.D, 4.H, 1.M): "emaint sync -a" # Monthly pull from G2
  if h mod 4.H == 0 and m == 9.M: r "something"  # Every 4th hr on the 9th min
  if (mo,d,h,m) == (Jan,1.D,0.H,0.M):
    run "HappyNY <"&n&">/var/log/HappyNY 2>&1", "Annual Log Job Name"
  if s == 30.S:
    Do("WILL NEVER RUN"): discard # *unless* you change period to 30*sec!

# If you have a holiday/business day lib/file then you could import that & do:
#   J bizDayKind.isa(y,mo,d) and (h,m)==(0.H,9.M): "myJob"
