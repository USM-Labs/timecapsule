#!/bin/bash
# usage: load.sh <alb-dns> [seconds]  - the loop from the task, run in two parallel copies
ALB=$1; DUR=${2:-600}
run() { end=$((SECONDS+DUR)); n=0; while [ $SECONDS -lt $end ]; do curl -s -o /dev/null http://$ALB/; n=$((n+1)); done; echo "worker $1: $n requests"; }
date -u +"start %H:%M:%S UTC"; run 1 & run 2 & wait; date -u +"end %H:%M:%S UTC"
