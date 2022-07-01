#!/bin/bash

OUTPUT=${1}
DURATION=${2}
PID=${1}
while [ "$1" != "" ]; do
	case $1 in
		-d| --duration )		shift
      DURATION=$1
      ;;
		-o| --outputfile )		shift
      OUTPUT=$1
      ;;
		-p| --pid )		shift
      PID=$1
      ;;
	esac
	shift
done
top -b -d $DURATION -p $PID > $OUTPUT 2>&1 &
TOP_PID=$!
sleep 5
sleep $DURATION

kill $TOP_PID




