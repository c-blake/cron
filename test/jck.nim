import cron, std/[os, strutils]     # A trivial jobs checking program

cron.period = if paramCount()>=1: 1.paramStr.parseInt else: 1*msec
cron.jitter = if paramCount()>=2: 2.paramStr.parseInt else:      0 # No Jitter
cron.tmFmt  = "W "                  # Perf test wants only "WakeupNs "
if paramCount()>=3: cron.tmFmt = "W %Y/%m/%d-%H:%M:%S: "  # But nice to validate
                                    # ^^^Extend strftime like my lc??
loop y,mo,d, h,m,s,ns, w: # discard # To time overhead of just running loop
  DoSync(""): discard               # Minimal log messages each period

# To validate viscerally, can just do 2 terminals - one doing `while {sleep .1}
# {date}`; Another `./jck 3_000_000_000 0 verb` or edit `0` to some jitter, e.g.
# 749_000_000.  (Recall +- jitter centered on the target times.)  Use `meas.sh`
# & `toEDF.sh` for more automatic validation.
