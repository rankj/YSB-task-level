#!/bin/bash

TIME_OUT=${1}
EXPERIMENT_DIR=${2}
INTERVALS=$(($TIME_OUT/10)) #13,5
STARTTIME=$(date +%s)
DEBUG="TRUE"
echo $EXPERIMENT_DIR

debug(){
MSG=${1}
TIMESTAMP=`date +%T.%N` #21:25:56.528279717
if [[ $DEBUG == "TRUE" ]]
then
  echo "[loadavg.sh] $HOSTNAME $TIMESTAMP: $MSG" >> $EXPERIMENT_DIR/sps_profiler_debug.log
fi
}

cd $EXPERIMENT_DIR
#nohup mpstat 60 15 &
sleep $INTERVALS
CPU_UTIL=`cat /proc/loadavg | awk '{print $3}'`
ENDTIME=$(date +%s)
LAPSED=$(($ENDTIME - $STARTTIME))
debug "Time lapse = $LAPSED, timeout=$TIME_OUT"
while (( $TIME_OUT > $LAPSED ))
do
      debug "sleeping for $INTERVALS"
      sleep $INTERVALS
      CPU_UTIL_NEXT=`cat /proc/loadavg | awk '{print $3}'`
      CPU_UTIL=`awk -vn=${CPU_UTIL} -vx=${CPU_UTIL_NEXT} 'BEGIN{printf("%.2f", x+n)}'`
      CPU_UTIL=`awk -vx=${CPU_UTIL} 'BEGIN{printf("%.2f", x/2)}'`
      ENDTIME=$(date +%s)
      LAPSED=$(($ENDTIME - $STARTTIME))
done
echo "$CPU_UTIL" > $EXPERIMENT_DIR/cpu_avg.txt
#echo "Util_end: $CPU_UTIL"
