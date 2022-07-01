#!/bin/bash
TIME_OUT=600
RETRY=0
FILE=${1}
MATCH=${2}
DEBUG=TRUE
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

debug(){
  MSG=${1}
  TIMESTAMP=`date +%T.%N`
  if [[ $DEBUG == "TRUE" ]]
  then
    touch $SCRIPT_DIR/../../last_results/bench_debug.log
    echo "[check_file_readiness.sh] $HOSTNAME $TIMESTAMP: $MSG" >> $SCRIPT_DIR/../../last_results/bench_debug.log
  fi
}

debug "Checking if $FILE exists"
while [ ! -f "$FILE" ]
do
    if (( $RETRY >= $TIME_OUT )); then
      debug "ERROR waited for $TIME_OUT seconds (timeout) but $FILE was not created -> exit"
      exit;
    fi
    sleep 5
    RETRY=$(($RETRY+5))
done
debug "File $FILE found! Checking for matching keyword $MATCH"
FOUND=$(grep "${MATCH}" "${FILE}" | grep -v grep)
while [ "$FOUND" == "" ]
do
    if (( $RETRY >= $TIME_OUT )); then
      debug "ERROR no matching keyword $MATCH in file $FILE after $TIME_OUT seconds (timeout) -> exit"
      exit;
    fi
    RETRY=$(($RETRY+5))
    sleep 5
    FOUND=`grep "${2}" "${1}" | grep -v grep`
done
debug "Found matching keyword $MATCH in file $FILE -> continue"
