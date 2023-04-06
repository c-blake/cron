when not declared(writeFile): import std/syncio
import cron # [1,2)am reRun;[2,3)am skip => DO NOT USE [1,3)am if Sun in Mar|Nov

putEnv "HOME", HOME     # This may seem terse, but it is any full Nim program
putEnv "PATH", HOME & "/bin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin"

cron.utc = false  # true => UTC time; Use any lib you want to convert test specs
cron.jitter = 3   # Lower sleep jitter from default to 3 seconds
cron.tmFmt  = "%Y/%m/%d-%H:%M:%S %Z: " # change time format for log (note space)

# WHEN,WHAT&WHY cron.loop (which runs EVERY MINUTE) (mostly) sorted by frequency
loop y,mo,d, h,m, w:                             # Idents can be changed
  Do("mFile"): writeFile "/tmp/m." & $m.int, ""  # Arbitrary Nim code ~every min
  J   (h,m) ==     ( 0.H, 2.M): setClock         # Desync if in||to not Bug NIST
  sysly mo,d, h,m, w                             # Sys Mly/Wly/Dly jobs FOR ROOT
  J m mod 15.M == 7: "every-15-on-the-7"         # 4 times/hour
  J   (h,m) ==      (0.H, 0.M): "train to GA"    # Daily
  J (w,h,m) == (Sat, 3.H, 1.M): "exec fstrim /"  # Keep flash mem writes fast
  J (w,h,m) == (Sat, 3.H,55.M): "xfs_fsr /dev/X" # Keep XFS writes on HDDs fast
  J (d,h,m) == (1.D, 4.H, 1.M): "emaint sync -a" # Monthly pull from G2
  if h.int mod 4 == 0 and m == 9.M: r "something" # Every 4th hr on the 9th min
  if (mo,d,h,m) == (Jan,1.D,0.H,0.M):
    run "HappyNY <"&n&">/var/log/HappyNY 2>&1", "Annual Log Job Name"

# If you have a holiday/business day lib/file then you could import that & do:
#   J bizDayKind.isa(y,mo,d) and (h,m)==(0.H,9.M): "myJob"
