#!/bin/sh
# Collect 60 kSample of 1ms timer wake-ups. (Invoker should write to /dev/shm.)
taskset 0x2 chrt 99 ./jck & # Run out of build dir
sleep 60                    # NOTE: for real deployments, you want chrt -R 99
kill $!
