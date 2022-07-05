#!/bin/bash
# Copyright 2015, Yahoo Inc.
# Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.

# PLEASE CHECK THESE SETTINGS
PROJECT_HOME=/YSB-task-level

PARTITIONS=$(cat "${PROJECT_HOME}/conf/clusterConf.yaml" | grep kafka.partitions | awk -F ": " '{print $2}')
KAFKALOGS=/tmp/kafka-logs/ #As defined in server.properties
ZKSTATE=/tmp/zookeeper/

# MAINTAINED BY DEPLOY.SH
KAFKA_VERSION="3.0.0"
REDIS_VERSION="6.0.10"
FLINK_SCALA_VERSION="2.12"
KAFKA_SCALA_VERSION="2.12"
FLINK_VERSION="1.14.3"
SPARK_VERSION="3.2.0"
SPARK_HADOOP_VERSION="2.7"

REDIS_DIR="redis-$REDIS_VERSION"
KAFKA_DIR="kafka_$KAFKA_SCALA_VERSION-$KAFKA_VERSION"
FLINK_DIR="flink-$FLINK_VERSION"
SPARK_DIR="spark-$SPARK_VERSION-bin-hadoop$SPARK_HADOOP_VERSION"

TOPIC=${TOPIC:-"ad-events"}
LOAD=${LOAD:-10000}
START_LOAD=${START_LOAD:-10000}
LOAD_INCREASE=${LOAD_INCREASE:-10000}
CONF_FILE="$PROJECT_HOME/conf/clusterConf.yaml"
CLUSTER_FILEPATH="$PROJECT_HOME/conf/cluster.txt"
TEST_TIME=${TEST_TIME:-900}
#PAYLOAD_FLINK="flink-benchmarks-0.1.2.jar"
PAYLOAD_FLINK="flink-benchmarks-0.1.3.jar"
PAYLOAD_SPARK_CP="spark-cp-benchmarks-0.1.0.jar"
PAYLOAD_SPARK="spark-structured-benchmarks-0.1.2.jar"
PAYLOAD="undefined"
BENCHMARK_VARIANT="undefined"

WARMUP_PHASE=900
HERTZ=99
NUMBER_OF_CAMPAIGNS=100
PREFIX=""
BENCHMARK_VARIANT=""
TIMESTAMP=$(date +%Y%m%d_%k_%M_%S)
EXPERIMENT_DIR="$(echo -e "${TIMESTAMP}" | tr -d '[:space:]')"
COOL_DOWN=15
BPF_PROFILING="TRUE"
BPF_PROFILING2="TRUE"
WAIT_TIME=0
TIME_OUT=600
DEBUG="FALSE"
DEBUG_STDOUT="FALSE"
DEBUG2="FALSE"
DEBUG2_STDOUT="FALSE"
RESULT=""
ACTIVE_EXP="FALSE"
PASSED_EXPERIMENT=""
declare -A HOST_ROLES
LOADING_REQ="true"
LEIN=${LEIN:-lein}
MVN=${MVN:-mvn}
GIT=${GIT:-git}
MAKE=${MAKE:-make}
KAFKA_BROKER=""
HOST_MASTER=""
NUMBER_OF_SLAVES=0
PREFIX=""
INFO="Info;none"
SUSTAINABLE_LATENCY_INCREASE=60000
LOAD_INCREASE=10000
MAX_SUST_LATENCY=0
THROUGHPUT_SUSTAINABLE="true"
PROCESSED_EVENTS=0
RESULT_FILE=""
REPEAT="TRUE"
RETRY=3
RUNS=${RUNS:-3}
MAX_LATENCY=0

MAX_OBSERVED_LATENCY=0
TARGET_NODES=0
pid_match() {
   local VAL=`ps -aef | grep "$1" | grep -v grep | awk '{print $2}'`
   echo $VAL
}

start_if_needed() {
  local match="$1"
  shift
  local name="$1"
  shift
  local sleep_time="$1"
  shift
  local PID=`pid_match "$match"`

  if [[ "$PID" -ne "" ]];
  then
    echo "$name is already running..."
  else
    "$@" &
    sleep $sleep_time
  fi
}

stop_if_needed() {
  local match="$1"
  local name="$2"
  local PID=`pid_match "$match"`
  debug "stop_if_needed match=$match name=$name found pid=$PID"
  if [[ "$PID" -ne "" ]];
  then
    kill "$PID"
    sleep 1
    local CHECK_AGAIN=`pid_match "$match"`
    if [[ "$CHECK_AGAIN" -ne "" ]];
    then
      kill -9 "$CHECK_AGAIN"
    fi
  else
    echo "No $name instance found to stop"
  fi
}

create_kafka_topic() {
    debug "creating Kafka Topic: $PROJECT_HOME/$KAFKA_DIR/bin/kafka-topics.sh --create --bootstrap-server localhost:9092 --replication-factor 1 --partitions $PARTITIONS --topic $TOPIC"
    $PROJECT_HOME/$KAFKA_DIR/bin/kafka-topics.sh --create --bootstrap-server localhost:9092 --replication-factor 1 --partitions $PARTITIONS --topic $TOPIC
}
wait_until_file_is_written2() {
  FILE=${1}
  FILESIZE_1=`wc -c <"${FILE}"`
  sleep 5
  FILESIZE_2=`wc -c <"${FILE}"`
  debug "wait_until_file_is_written2: Checking size of ${FILE}"
  local RETRY=0
  debug2 "Checking Filesize of $FILE"
  debug2 "Compare $FILESIZE_2 > $FILESIZE_1"
  while [ $FILESIZE_2 != $FILESIZE_1 ]
  do
    FILESIZE_1=$FILESIZE_2
    sleep 5
    FILESIZE_2=`wc -c <"${FILE}"`
  done
}

# Checks for file readniss on all cluster nodes with TARGET_ROLE by checking if FILE contains WORD
cluster_check_filereadiness(){
  TARGET_ROLE=${1}
  FILE=${2}
  WORD=${3}
  debug "Checking file $FILE for the searchstring $WORD on all nodes with role $TARGET_ROLE"
  for HOST in "${!HOST_ROLES[@]}"; do
        ROLE=${HOST_ROLES[$HOST]}
        if [[ $ROLE == *"$TARGET_ROLE"* ]]; then
            debug2 "waiting for matching word=$WORD in file=$FILE on Host=$HOST"
            if [ "$HOST" == $HOSTNAME ]; then
               debug2 "localhost: $PROJECT_HOME/profiling/scripts/check_file_readiness.sh $PROJECT_HOME/last_results/$FILE $WORD"
               $PROJECT_HOME/profiling/scripts/check_file_readiness2.sh $PROJECT_HOME/last_results/$FILE $WORD
            else
               debug2 "ssh $HOST '$PROJECT_HOME/profiling/scripts/check_file_readiness.sh $PROJECT_HOME/last_results/$FILE $WORD'"
               ssh $HOST "$PROJECT_HOME/profiling/scripts/check_file_readiness.sh $PROJECT_HOME/last_results/$FILE $WORD"
            fi
        fi
  done
}
wait_for(){
  TARGET_ROLE=${1}
  STATE=${2}
  debug2 "wait_for state $STATE on all nodes of role $TARGET_ROLE"
  cluster_check_filereadiness $TARGET_ROLE progress.txt $STATE
  debug2 "state $STATE on all nodes with role $TARGET_ROLE reached -> continue"
}

cluster_run(){
  local TARGET=$1
  local COMMAND=$2
  shift
  if [ "$TARGET" == $HOSTNAME ]; then
    debug "Running on localhost: $PROJECT_HOME/stream-bench2.sh -o $COMMAND -t $TEST_TIME -l $LOAD -f $HERTZ -d $DEBUG -b $BPF_PROFILING -e $EXPERIMENT_DIR -n $NUMBER_OF_CAMPAIGNS -a $PAYLOAD &"
    $PROJECT_HOME/stream-bench2.sh -o $COMMAND -t $TEST_TIME -l $LOAD -f $HERTZ -d $DEBUG -b $BPF_PROFILING -e $EXPERIMENT_DIR -n $NUMBER_OF_CAMPAIGNS -a $PAYLOAD &

  else
    debug "Running: ssh $TARGET $PROJECT_HOME/stream-bench2.sh -o $COMMAND -t $TEST_TIME -l $LOAD -f $HERTZ -d $DEBUG -b $BPF_PROFILING -e $EXPERIMENT_DIR -n $NUMBER_OF_CAMPAIGNS -a $PAYLOAD &"
    ssh $TARGET "$PROJECT_HOME/stream-bench2.sh -o $COMMAND -t $TEST_TIME -l $LOAD -f $HERTZ -d $DEBUG -b $BPF_PROFILING -e $EXPERIMENT_DIR -n $NUMBER_OF_CAMPAIGNS  -a $PAYLOAD" &
  fi
}
check_file_structure(){
  if [ ! -d "${PROJECT_HOME}/profiling/measurments/${EXPERIMENT_DIR}/tmp/" ]; then
        mkdir -p "${PROJECT_HOME}/profiling/measurments/${EXPERIMENT_DIR}/tmp/"
        rm -f $PROJECT_HOME/last_results
        ln -s ${PROJECT_HOME}/profiling/measurments/${EXPERIMENT_DIR}/tmp/ $PROJECT_HOME/last_results
        touch $PROJECT_HOME/profiling/measurments/$EXPERIMENT_DIR/tmp/progress.txt
  fi
}
cluster_profile(){
 local TARGET=$1
 local COMMAND=$2
 shift
 DURATION=$(($TEST_TIME+$COOL_DOWN))
 if [ "$TARGET" == $HOSTNAME ]; then
   $PROJECT_HOME/profiling/scripts/sps_profiler.sh -o $COMMAND -d ${DURATION} -f $HERTZ -p "${PROJECT_HOME}" -b $BPF_PROFILING &
 else
    ssh $TARGET "$PROJECT_HOME/profiling/scripts/sps_profiler.sh -o $COMMAND -d ${DURATION} -f $HERTZ -p ${PROJECT_HOME} -b $BPF_PROFILING" &
 fi
}
debug(){
MSG=${1}
TIMESTAMP=`date +%T.%N`
if [[ $DEBUG == "TRUE" ]]
then
  echo "[DEBUG] $HOSTNAME $TIMESTAMP: $MSG" >> ${PROJECT_HOME}/profiling/measurments/${EXPERIMENT_DIR}/tmp/bench_debug.log
fi
if [[ $DEBUG_STDOUT == "TRUE" ]]
then
  echo "[DEBUG] $HOSTNAME $TIMESTAMP: $MSG"
fi
}
debug2(){
MSG=${1}
TIMESTAMP=`date +%T.%N`
if [[ $DEBUG2 == "TRUE" ]]
then
  echo "[DEBUG] $HOSTNAME $TIMESTAMP: $MSG" >> ${PROJECT_HOME}/profiling/measurments/${EXPERIMENT_DIR}/tmp/bench_debug.log
fi
if [[ $DEBUG_STDOUT2 == "TRUE" ]]
then
  echo "[DEBUG] $HOSTNAME $TIMESTAMP: $MSG"
fi
}
progress(){
  STATE=${1}
  TIMESTAMP=`date +%T.%N`
  echo "${1} : $TIMESTAMP" >> $PROJECT_HOME/profiling/measurments/${EXPERIMENT_DIR}/tmp/progress.txt
}

readClusterConf(){
   PARTITIONS=$(grep "kafka.partitions" $CONF_FILE | awk '{print $2}')
   TOPIC=$(grep "kafka.topic" $CONF_FILE | awk '{print $2}')
   TOPIC=$(echo "$TOPIC" | tr -d '"')
}

readHostRoles(){
  {
    if $LOADING_REQ; then
      LOADING_REQ="false"
      while IFS= read -r line || [ -n "$line" ];
      do
        local HOST=`echo $line | awk '{print $1}'`
        local ROLE=`echo $line | awk '{print $2}'`
        HOST_ROLES[$HOST]="$ROLE"
        if [[ "$ROLE" == *"KAFKA"* ]]; then
          KAFKA_BROKER=$HOST
        fi
        if [[ "$ROLE" == *"SLAVE"* ]]; then
            NUMBER_OF_SLAVES=$((NUMBER_OF_SLAVES+1))
        fi
        if [[ "$ROLE" == *"MASTER"* ]]; then
           HOST_MASTER=$HOST
        fi
      done
  fi
  } < $CLUSTER_FILEPATH
}

run() {
  OPERATION=$1
  start=`date +%s`

  debug "Starting Operation $OPERATION"
  if [ "GET_STATS" = "$OPERATION" ]; then
	SPE=${2}

    if [ "flink" = "$SPE" ]; then
      PAYLOAD=$PAYLOAD_FLINK
    elif [ "spark" = "$SPE" ]; then
      PAYLOAD=$PAYLOAD_SPARK
    fi
    if [ "" = "$RESULT_FILE" ]; then
      RESULT_FILE="${SPE}_bench_summary"
    fi
    ($PROJECT_HOME/$KAFKA_DIR/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list $KAFKA_BROKER:9092 --topic ad-events | awk -F  ":" '{sum += $3} END {print sum}' > $PROJECT_HOME/last_results/kafka_messages_total.txt)&
    ($PROJECT_HOME/$KAFKA_DIR/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list $KAFKA_BROKER:9092 --topic ad-events > $PROJECT_HOME/last_results/kafka_partitions_total.txt)&
    sleep 5
	run "GET_REDIS_STATS" $SPE

    # updated.txt
    STANDARD_DEVIATION_UP=`cat $PROJECT_HOME/last_results/updated.txt | awk '{x+=$0;y+=$0^2}END{print sqrt(y/NR-(x/NR)^2)}'`
    MAX_LAT_UP=`cat $PROJECT_HOME/last_results/updated.txt | awk 'max<$1 || NR==1{ max=$1 } END {print max}'`
    MIN_LAT_UP=`cat $PROJECT_HOME/last_results/updated.txt | awk 'min>$1 || NR==1{ min=$1 } END {print min}'`
    AVG_LAT_UP=`cat $PROJECT_HOME/last_results/updated.txt | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; }'`
    # pre-window
    STANDARD_DEVIATION_WNDW=`cat $PROJECT_HOME/last_results/pre-window.txt | awk '{x+=$0;y+=$0^2}END{print sqrt(y/NR-(x/NR)^2)}'`
    MAX_LAT_WNDW=`cat $PROJECT_HOME/last_results/pre-window.txt | awk 'max<$1 || NR==1{ max=$1 } END {print max}'`
    MIN_LAT_WNDW=`cat $PROJECT_HOME/last_results/pre-window.txt | awk 'min>$1 || NR==1{ min=$1 } END {print min}'`
    AVG_LAT_WNDW=`cat $PROJECT_HOME/last_results/pre-window.txt | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; }'`
    # latency
    chmod 777 $PROJECT_HOME/last_results/latency.txt
    STANDARD_DEVIATION_LAT=`cat $PROJECT_HOME/last_results/latency.txt | awk '{x+=$0;y+=$0^2}END{print sqrt(y/NR-(x/NR)^2)}'`
    MAX_LAT_LAT=`cat $PROJECT_HOME/last_results/latency.txt | awk 'max<$1 || NR==1{ max=$1 } END {print max}'`
    MIN_LAT_LAT=`cat $PROJECT_HOME/last_results/latency.txt | awk 'min>$1 || NR==1{ min=$1 } END {print min}'`
    AVG_LAT_LAT=`cat $PROJECT_HOME/last_results/latency.txt | awk '{ sum += $1; n++ } END { if (n > 0) print sum / n; }'`


    KAFKA_EVENTS_WARMUP=$(head -n 1 $PROJECT_HOME/last_results/kafka_events_after_initializing.txt)
    if [ -f $PROJECT_HOME/last_results/kafka_messages_total.txt ]; then
      KAFKA_EVENTS_TOTAL=$(head -n 1 $PROJECT_HOME/last_results/kafka_messages_total.txt)
    else
      KAFKA_EVENTS_TOTAL="unknown"
    fi

    wait_for "MASTER" "FINISHED_RESULT_AGGREGATION"
    wait_for "SLAVE" "FINISHED_RESULT_AGGREGATION"
    run "CLUSTER_GET_FILE" "MASTER_SLAVE" "$PROJECT_HOME/profiling/measurments/${EXPERIMENT_DIR}/experiment_results.txt" "$PROJECT_HOME/profiling/measurments/${EXPERIMENT_DIR}/tmp/"

    for HOST in "${!HOST_ROLES[@]}"; do
      ROLE=${HOST_ROLES[$HOST]}
      TARGET_ROLE="MASTER_SLAVE"
      if [[ $TARGET_ROLE == *$ROLE* || $ROLE == *$TARGET_ROLE* || $TARGET_ROLE == "ALL" ]]; then
          RESULT=`cat $PROJECT_HOME/last_results/${HOST}_experiment_results.txt`
          while IFS="NEXT" read -r line; do
            if [[ $line != *"END_OF_RESULT"* ]]; then
              echo "EXPERIMENT_ID;${EXPERIMENT_DIR};$INFO;Duration;$TEST_TIME;Load;$LOAD;Slaves;$NUMBER_OF_SLAVES;Payload;$PAYLOAD;Campaigns;$NUMBER_OF_CAMPAIGNS;Partitions;$PARTITIONS;Node;$HOST;Role;$ROLE;ProcessedEvents;$PROCESSED_EVENTS;KAFKA_WARMUP_EVENTS;${KAFKA_EVENTS_WARMUP};KAFKA_TOTAL_EVENTS;${KAFKA_EVENTS_TOTAL};STANDARD_DEVIATION_UP;${STANDARD_DEVIATION_UP};MAX_LAT_UP;${MAX_LAT_UP};MIN_LAT_UP;${MIN_LAT_UP};AVG_LAT_UP;${AVG_LAT_UP};STANDARD_DEVIATION_WNDW;${STANDARD_DEVIATION_WNDW};MAX_LAT_WNDW;${MAX_LAT_WNDW};MIN_LAT_WNDW;${MIN_LAT_WNDW};AVG_LAT_WNDW;${AVG_LAT_WNDW};STANDARD_DEVIATION_LAT;${STANDARD_DEVIATION_LAT};MAX_LAT_LAT;${MAX_LAT_LAT};MIN_LAT_LAT;${MIN_LAT_LAT};AVG_LAT_LAT;${AVG_LAT_LAT};${line}" >> $PROJECT_HOME/${RESULT_FILE}.csv
            fi
          done <<< "$RESULT"
      fi
    done
    $PROJECT_HOME/utils/convertToHTML.sh $PROJECT_HOME/${RESULT_FILE}.csv > $PROJECT_HOME/${RESULT_FILE}.html

  elif [ "KILL_SCRIPTS" = "$OPERATION" ]; then
      pkill -f 'java'
      pkill -f 'sps_profiler'
      pkill -f 'loadavg'
      pkill -f 'network_traffic'
      pkill -f 'check_file_readiness'
      progress "SCRIPTS_KILLED"
      sleep 1
      pkill -f 'stream-bench'

  elif [ "CLUSTER_RESTART" = "$OPERATION" ]; then
    for HOST in "${!HOST_ROLES[@]}"; do
        if [[ $HOST != $HOSTNAME ]]; then
          ssh $HOST "shutdown -r now"
        fi
    done
    sleep 5
    shutdown -r now
    exit

  elif [ "CLUSTER_STOP_ALL" = "$OPERATION" ]; then
    run "STOP_LOAD_CLUSTER"
    run "STOP_FLINK_PROCESSING_CLUSTER"
    run "STOP_FLINK_CLUSTER"
    run "STOP_SPARK_PROCESSING_CLUSTER"
    run "STOP_SPARK_CLUSTER"
    run "STOP_REDIS_KAFKA_CLUSTER"
    sleep 20 # Since all stop procedures run in the background it would be possible to interrupt them by killing the stream-bench.sh program

    run "CLUSTER" "ALL" "KILL_SCRIPTS"

  ###################################################
  ##########     Full Spark Benchmark      ##########
  ###################################################
elif [ "SPARK_CLUSTER_BENCH3" = "$OPERATION" ]; then
  PAYLOAD=$PAYLOAD_SPARK
  run "START_REDIS_KAFKA_CLUSTER"
  run "START_SPARK_CLUSTER"
  run "START_SPARK_PROCESSING_CLUSTER"
  #run "WARMUP_PHASE"
  run "START_LOAD_CLUSTER"
  #run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK"
  sleep 99999
  run "CLUSTER" "LOAD" "STOP_LOAD"
  sleep $COOL_DOWN

  run "INITIALIZE_KAFKA_CLUSTER"
  wait_for "SLAVE" "FINISHED_RESULT_AGGREGATION"
  run "STOP_SPARK_PROCESSING_CLUSTER"
  run "STOP_SPARK_CLUSTER"
  run "GET_STATS" "spark"
  #run "STOP_REDIS_KAFKA_CLUSTER"
run "CLUSTER_STOP_ALL"
sleep 300
  elif [ "SPARK_CLUSTER_BENCH" = "$OPERATION" ]; then
	PAYLOAD=$PAYLOAD_SPARK
    run "START_REDIS_KAFKA_CLUSTER"
    run "START_SPARK_CLUSTER"
    run "START_SPARK_PROCESSING_CLUSTER"
    sleep 20
    run "WARMUP_PHASE"
	sleep 15
    run "START_LOAD_CLUSTER"
	run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK"
    sleep $TEST_TIME
    run "CLUSTER" "LOAD" "STOP_LOAD"
    sleep $COOL_DOWN

    run "INITIALIZE_KAFKA_CLUSTER"
    wait_for "SLAVE" "FINISHED_RESULT_AGGREGATION"
    run "STOP_SPARK_PROCESSING_CLUSTER"
    run "STOP_SPARK_CLUSTER"
    run "GET_STATS" "spark"
    #run "STOP_REDIS_KAFKA_CLUSTER"
	run "CLUSTER_STOP_ALL"
	sleep 300
  elif [ "SPARK_CLUSTER_BENCH2" = "$OPERATION" ]; then
	PAYLOAD=$PAYLOAD_SPARK
	TIMESTAMP=$(date +%Y%m%d_%k_%M_%S)
	EXPERIMENT_DIR="$(echo -e "${TIMESTAMP}" | tr -d '[:space:]')"
	EXPERIMENT_DIR="RUN1_${EXPERIMENT_DIR}_${BENCHMARK_VARIANT}_Load${LOAD}_Duration${TEST_TIME}_Frequ${HERTZ}_Warmup${WARM_UP}"
	check_file_structure

    run "START_REDIS_KAFKA_CLUSTER"
    run "START_SPARK_CLUSTER"
    run "START_SPARK_PROCESSING_CLUSTER"
    run "START_LOAD_CLUSTER"
	USER_TEST_TIME=$TEST_TIME
	sleep 60
	TEST_TIME=120
    run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK"
    sleep 120
	run "CLUSTER" "LOAD" "STOP_LOAD"
	sleep 60


	TIMESTAMP=$(date +%Y%m%d_%k_%M_%S)
	EXPERIMENT_DIR="$(echo -e "${TIMESTAMP}" | tr -d '[:space:]')"
	EXPERIMENT_DIR="RUN120_${EXPERIMENT_DIR}_${BENCHMARK_VARIANT}_Load${LOAD}_Duration${TEST_TIME}_Frequ${HERTZ}_Warmup${WARM_UP}"
	check_file_structure
	run "START_LOAD_CLUSTER"
	TEST_TIME=120
	run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK"
	sleep 120
	run "CLUSTER" "LOAD" "STOP_LOAD"
	sleep 60

	TIMESTAMP=$(date +%Y%m%d_%k_%M_%S)
	EXPERIMENT_DIR="$(echo -e "${TIMESTAMP}" | tr -d '[:space:]')"
	EXPERIMENT_DIR="RUN300_${EXPERIMENT_DIR}_${BENCHMARK_VARIANT}_Load${LOAD}_Duration${TEST_TIME}_Frequ${HERTZ}_Warmup${WARM_UP}"
	check_file_structure
	run "START_LOAD_CLUSTER"
	TEST_TIME=300
	run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK"
	sleep 300
	run "CLUSTER" "LOAD" "STOP_LOAD"
	sleep 60

	TIMESTAMP=$(date +%Y%m%d_%k_%M_%S)
	EXPERIMENT_DIR="$(echo -e "${TIMESTAMP}" | tr -d '[:space:]')"
	EXPERIMENT_DIR="RUN600_${EXPERIMENT_DIR}_${BENCHMARK_VARIANT}_Load${LOAD}_Duration${TEST_TIME}_Frequ${HERTZ}_Warmup${WARM_UP}"
	check_file_structure
	run "START_LOAD_CLUSTER"
	TEST_TIME=600
	run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK"
	sleep 600
	run "CLUSTER" "LOAD" "STOP_LOAD"
	sleep 60

	TIMESTAMP=$(date +%Y%m%d_%k_%M_%S)
	EXPERIMENT_DIR="$(echo -e "${TIMESTAMP}" | tr -d '[:space:]')"
	EXPERIMENT_DIR="RUN900_${EXPERIMENT_DIR}_${BENCHMARK_VARIANT}_Load${LOAD}_Duration${TEST_TIME}_Frequ${HERTZ}_Warmup${WARM_UP}"
	check_file_structure
	run "START_LOAD_CLUSTER"
	TEST_TIME=900
	run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK"
	sleep 900
	run "CLUSTER" "LOAD" "STOP_LOAD"
	sleep 60

    run "INITIALIZE_KAFKA_CLUSTER"
    wait_for "SLAVE" "FINISHED_RESULT_AGGREGATION"
    run "STOP_SPARK_PROCESSING_CLUSTER"
    run "STOP_SPARK_CLUSTER"
    run "GET_STATS" "spark"
    #run "STOP_REDIS_KAFKA_CLUSTER"
	run "CLUSTER_STOP_ALL"
	sleep 300
  elif [ "SPARK_CP_CLUSTER_BENCH" = "$OPERATION" ]; then
    PAYLOAD=$PAYLOAD_SPARK_CP
	run "START_REDIS_KAFKA_CLUSTER"
    run "START_SPARK_CLUSTER"
    run "START_SPARK_CP_PROCESSING_CLUSTER"
    sleep 20
    run "WARMUP_PHASE"
	sleep 15
    run "START_LOAD_CLUSTER"
    run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK_CP"
    sleep $TEST_TIME
    run "CLUSTER" "LOAD" "STOP_LOAD"
    sleep $COOL_DOWN
    #run "INITIALIZE_KAFKA_CLUSTER"
    wait_for "SLAVE" "FINISHED_RESULT_AGGREGATION"
    run "STOP_SPARK_CP_PROCESSING_CLUSTER"
    run "STOP_SPARK_CLUSTER"
    run "GET_STATS" "spark"
    #run "STOP_REDIS_KAFKA_CLUSTER"
	run "CLUSTER_STOP_ALL"
	sleep 300

  elif [ "SPARK_MAX_SUST_THROUGHPUT" = "$OPERATION" ]; then
    run "START_REDIS_KAFKA_CLUSTER"
    run "START_SPARK_CLUSTER"
    run "START_SPARK_PROCESSING_CLUSTER"
    sleep 10
    run "WARMUP_PHASE"
    debug "WARMUP_PHASE finished. Starting Throughput loop"
    run "SUST_THROUGHPUT_LOOP" "spark"
    run "STOP_SPARK_PROCESSING_CLUSTER"
    run "STOP_SPARK_CLUSTER"
    run "CLUSTER_STOP_ALL"
	sleep 300
	
  elif [ "SPARK_CP_MAX_SUST_THROUGHPUT" = "$OPERATION" ]; then
    run "START_REDIS_KAFKA_CLUSTER"
    run "START_SPARK_CLUSTER"
    run "START_SPARK_CP_PROCESSING_CLUSTER"
    sleep 10
    run "WARMUP_PHASE"
    debug "WARMUP_PHASE finished. Starting Throughput loop"
    run "SUST_THROUGHPUT_LOOP" "spark_cp"
    run "STOP_SPARK_PROCESSING_CLUSTER"
    run "STOP_SPARK_CLUSTER"
    run "CLUSTER_STOP_ALL"
	sleep 300
  ###################################################
  ##########     Full Flink Benchmark      ##########
  ###################################################
  elif [ "FLINK_CLUSTER_BENCH" = "$OPERATION" ]; then
	run "START_REDIS_KAFKA_CLUSTER"
    run "START_FLINK_CLUSTER"
    run "START_FLINK_PROCESSING_CLUSTER"
	sleep 20
    run "WARMUP_PHASE"
	sleep 15
    run "START_LOAD_CLUSTER"
    run "CLUSTER" "MASTER_SLAVE" "PROFILE_FLINK"
    sleep $TEST_TIME
    run "CLUSTER" "LOAD" "STOP_LOAD"
    sleep $COOL_DOWN
    #sleep 20
    run "INITIALIZE_KAFKA_CLUSTER"
    #sleep 30
    wait_for "SLAVE" "FINISHED_RESULT_AGGREGATION"
    #sleep 10
    run "STOP_FLINK_PROCESSING_CLUSTER"
    #sleep 10
    run "STOP_FLINK_CLUSTER"
    #sleep 30
    run "GET_STATS" "flink"
    #run "STOP_REDIS_KAFKA_CLUSTER"
	run "CLUSTER_STOP_ALL"
	sleep 300

  elif [ "FLINK_CLUSTER_BENCH_LOOP" = "$OPERATION" ]; then
    PAYLOAD=$PAYLOAD_FLINK
	MAX_LOAD=$LOAD
	#LOAD=60000
	#LOAD_INCREASE=40000
	run "START_REDIS_KAFKA_CLUSTER"
    run "START_FLINK_CLUSTER"
    run "START_FLINK_PROCESSING_CLUSTER"
    run "WARMUP_PHASE"
	LOAD=$START_LOAD
	while [ $LOAD -le $MAX_LOAD ]; do
		for((i=1;i<=$RUNS;i+=1)); do

			TIMESTAMP=$(date +%Y%m%d_%k_%M_%S)
			EXPERIMENT_DIR="$(echo -e "${TIMESTAMP}" | tr -d '[:space:]')"
			EXPERIMENT_DIR="${PREFIX}_${EXPERIMENT_DIR}_${BENCHMARK_VARIANT}_Load${LOAD}_Duration${TEST_TIME}_Frequ${HERTZ}_Warmup${WARM_UP}"
			check_file_structure
			run "INITIALIZE_KAFKA_CLUSTER"
			run "START_LOAD_CLUSTER"
			run "CLUSTER" "MASTER_SLAVE" "PROFILE_FLINK"
			sleep $TEST_TIME
			run "CLUSTER" "LOAD" "STOP_LOAD"
			sleep $COOL_DOWN
			#INITIALIZE KAFKA -> Stop Processing
			wait_for "SLAVE" "FINISHED_RESULT_AGGREGATION"
			run "GET_STATS" "flink"
			run "INITIALIZE_REDIS_CLUSTER"
			#for((i=1;i<=3;i+=1)); do ./stream-bench2.sh -p E1 -o FLINK_CLUSTER_BENCH -f 99 -t 300 -l $LOAD -n 100 ; ./stream-bench2.sh -o CLUSTER_STOP_ALL; sleep 10; done
		done
		LOAD=$((LOAD+LOAD_INCREASE))
	done
	#run "STOP_REDIS_KAFKA_CLUSTER"
	run "CLUSTER_STOP_ALL"
	sleep 300

  elif [ "SPARK_CLUSTER_BENCH_LOOP" = "$OPERATION" ]; then   
	PAYLOAD=$PAYLOAD_SPARK
	MAX_LOAD=$LOAD
	
	LOAD=60000
	run "START_REDIS_KAFKA_CLUSTER"
    run "START_SPARK_CLUSTER"
    run "START_SPARK_PROCESSING_CLUSTER"
    run "WARMUP_PHASE"
	LOAD=$START_LOAD #TODO -> Change back to 10000
	TOTAL_LOAD=$((LOAD*4))
	while [ $LOAD -le $MAX_LOAD ]; do
		for((i=1;i<=$RUNS;i+=1)); do
			TIMESTAMP=$(date +%Y%m%d_%k_%M_%S)
			EXPERIMENT_DIR="$(echo -e "${TIMESTAMP}" | tr -d '[:space:]')"
			EXPERIMENT_DIR="${PREFIX}_${EXPERIMENT_DIR}_${BENCHMARK_VARIANT}_Load${LOAD}_Duration${TEST_TIME}_Frequ${HERTZ}_Warmup${WARM_UP}"
			check_file_structure
			run "INITIALIZE_KAFKA_CLUSTER"
			run "START_LOAD_CLUSTER"
			run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK"
			sleep $TEST_TIME
			run "CLUSTER" "LOAD" "STOP_LOAD"
			sleep $COOL_DOWN
			#run "INITIALIZE_KAFKA_CLUSTER"
			wait_for "SLAVE" "FINISHED_RESULT_AGGREGATION"
			run "GET_STATS" "spark"
			sleep 20
			run "INITIALIZE_REDIS_CLUSTER"
		done
		LOAD=$((LOAD+LOAD_INCREASE))
		TOTAL_LOAD=$((LOAD*4))
	done
	#run "STOP_REDIS_KAFKA_CLUSTER"
	run "CLUSTER_STOP_ALL"
	sleep 300
	
  elif [ "SPARK_CP_CLUSTER_BENCH_LOOP" = "$OPERATION" ]; then
    PAYLOAD=$PAYLOAD_SPARK_CP
	MAX_LOAD=$LOAD
	LOAD=60000
	#LOAD_INCREASE=10000
	run "START_REDIS_KAFKA_CLUSTER"
    run "START_SPARK_CLUSTER"
    run "START_SPARK_CP_PROCESSING_CLUSTER"
	sleep 20
    run "WARMUP_PHASE"
	LOAD=$START_LOAD #TODO -> Change back to 10000

	while [ $LOAD -le $MAX_LOAD ]; do
		for((i=1;i<=$RUNS;i+=1)); do
			TIMESTAMP=$(date +%Y%m%d_%k_%M_%S)
			EXPERIMENT_DIR="$(echo -e "${TIMESTAMP}" | tr -d '[:space:]')"
			EXPERIMENT_DIR="${PREFIX}_${EXPERIMENT_DIR}_${BENCHMARK_VARIANT}_Load${LOAD}_Duration${TEST_TIME}_Frequ${HERTZ}_Warmup${WARM_UP}"
			check_file_structure
			run "INITIALIZE_KAFKA_CLUSTER"
			run "START_LOAD_CLUSTER"
			run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK_CP"
			sleep $TEST_TIME
			run "CLUSTER" "LOAD" "STOP_LOAD"
			sleep $COOL_DOWN
			run "INITIALIZE_KAFKA_CLUSTER"
			wait_for "SLAVE" "FINISHED_RESULT_AGGREGATION"
			run "GET_STATS" "spark"
			sleep 40
			run "INITIALIZE_REDIS_CLUSTER"
		done
		LOAD=$((LOAD+LOAD_INCREASE))
	done
	run "CLUSTER_STOP_ALL"
	sleep 300

  elif [ "FLINK_MAX_SUST_THROUGHPUT" = "$OPERATION" ]; then
    run "START_REDIS_KAFKA_CLUSTER"
    run "START_FLINK_CLUSTER"
    run "START_FLINK_PROCESSING_CLUSTER"
    sleep 10
    run "WARMUP_PHASE"
    run "SUST_THROUGHPUT_LOOP" "flink"
    run "STOP_FLINK_PROCESSING_CLUSTER"
    run "STOP_FLINK_CLUSTER"
    run "CLUSTER_STOP_ALL"
	sleep 300

  elif [ "FLINK_PROCESSING_CONSISTENCY" = "$OPERATION" ]; then
    run "START_REDIS_KAFKA_CLUSTER"
    run "START_FLINK_CLUSTER"
    run "START_FLINK_PROCESSING_CLUSTER"
    sleep 10
    $PROJECT_HOME/$KAFKA_DIR/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list c06lp1:9092 --topic ad-events | awk -F  ":" '{sum += $3} END {print sum}' > $PROJECT_HOME/last_results/kafka_initial.txt
    run "START_LOAD_CLUSTER"
    sleep $TEST_TIME
    run "CLUSTER" "LOAD" "STOP_LOAD"

    sleep 17 # COOLDOWN
    $PROJECT_HOME/$KAFKA_DIR/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list c06lp1:9092 --topic ad-events | awk -F  ":" '{sum += $3} END {print sum}' > $PROJECT_HOME/last_results/kafka_final.txt
    cd $PROJECT_HOME/data
    $LEIN run -g --configPath $CONF_FILE || true


    PROCESSED=$(cat $PROJECT_HOME/data/seen.txt | awk '{sum += $1} END {print sum}')
    run "STOP_FLINK_PROCESSING_CLUSTER"
    sleep 30
    #run "STOP_KAFKA"

    sleep 15
    run "STOP_KAFKA_CLUSTER"
    cd $PROJECT_HOME/data
    $LEIN run -g --configPath $CONF_FILE || true

    PROCESSED2=$(cat $PROJECT_HOME/data/seen.txt | awk '{sum += $1} END {print sum}')
    echo "[BENCH] Number of Kafka events before starting the load cluster"
    cat $PROJECT_HOME/last_results/kafka_initial.txt
    echo "[BENCH] Number of Kafka events after final execution"
    KAFKAEVENTS=$(cat $PROJECT_HOME/last_results/kafka_final.txt)
    echo $KAFKAEVENTS
    echo "[BENCH] Number of Redis events before stopping"
    echo $PROCESSED
    echo "[BENCH] Number of Redis events after final execution"
    echo $PROCESSED2
    DIFFERENCE=$((KAFKAEVENTS-PROCESSED2))
    echo "[BENCH] Difference"
    echo $DIFFERENCE
    run "CLUSTER_STOP_ALL"
    exit

  ################################################
  # COMMON BENCHMARK PHASES
  ################################################
  elif [ "WARMUP_PHASE" = "$OPERATION" ]; then
    CONFIGURED_LOAD=$LOAD
	LOAD=$((CONFIGURED_LOAD/2))
	run "START_LOAD_CLUSTER"
		#sleep 120
		#TEST_TIME=180
	  #run "CLUSTER" "MASTER_SLAVE" "PROFILE_SPARK"
		#sleep 600
    sleep $WARMUP_PHASE
    run "STOP_LOAD_CLUSTER"
    wait_for "LOAD" "LOAD_STOPPED"
	LOAD=$CONFIGURED_LOAD
    run "INITIALIZE_KAFKA_CLUSTER"
	sleep $((WARMUP_PHASE/10))
	sleep 30
    run "INITIALIZE_REDIS_CLUSTER"
    debug "WARMUP Finished"


  elif [ "START_REDIS_KAFKA_CLUSTER" = "$OPERATION" ]; then
    run "START_KAFKA_CLUSTER"
    run "START_REDIS_CLUSTER"
    wait_for "KAFKA" "KAFKA_STARTED"
    sleep 5
	wait_for "REDIS" "REDIS_STARTED"
	sleep 5

  elif [ "STOP_REDIS_KAFKA_CLUSTER" = "$OPERATION" ]; then
    run "STOP_KAFKA_CLUSTER"
    run "STOP_REDIS_CLUSTER"

  elif [ "SUST_THROUGHPUT_LOOP" = "$OPERATION" ]; then
      SPE=${2}
      SUSTAINABLE_EVENTS=0

	  debug "Sarting Sustainable Throughput Loop for $SPE"
      #run "START_LOAD_CLUSTER"
      #sleep 120
      #run "CLUSTER" "LOAD" "STOP_LOAD"

      #GET Baseline Latency
      #run "GET_REDIS_STATS" $SPE
      #BASELINE_LATENCY=`cat $PROJECT_HOME/last_results/latency.txt | awk 'max<$1 || NR==1{ max=$1 } END {print max}'`
      #MAX_SUST_LATENCY=$((BASELINE_LATENCY+SUSTAINABLE_LATENCY_INCREASE))
      MAX_SUST_LATENCY=$SUSTAINABLE_LATENCY_INCREASE
	  #debug "Baseline latency is $BASELINE_LATENCY, + sustainable latency increase $SUSTAINABLE_LATENCY_INCREASE => MAX_SUST_LATENCY = $MAX_SUST_LATENCY"
      #run "INITIALIZE_REDIS_CLUSTER"
	  LOAD=$START_LOAD
      # Loop
	  MAX_OBSERVED_LATENCY=0
      while [ "$THROUGHPUT_SUSTAINABLE" = "true" ]; do
        SUSTAINABLE_EVENTS=${PROCESSED_EVENTS}
		SUSTAINABLE_LATENCY=${MAX_OBSERVED_LATENCY}
        debug "SUSTAINABLE_EVENTS=${PROCESSED_EVENTS} SUSTAINABLE_LATENCY=${MAX_OBSERVED_LATENCY}"
		debug2 "Starting loadcheck $LOAD events/s"
        LOAD=$((LOAD+LOAD_INCREASE))
        run "START_LOAD_CLUSTER"
        sleep $TEST_TIME
        run "CLUSTER" "LOAD" "STOP_LOAD"
		sleep $COOL_DOWN
        run "INITIALIZE_KAFKA_CLUSTER"
        sleep 60
        run "GET_REDIS_STATS" $SPE
        run "CHECK_LATENCY"
		run "INITIALIZE_REDIS_CLUSTER"
      done
      LOAD=$((LOAD-LOAD_INCREASE))
      LOAD_INCREASE=$((LOAD_INCREASE/4)) #
      THROUGHPUT_SUSTAINABLE="true"
	  MAX_OBSERVED_LATENCY=$SUSTAINABLE_LATENCY #reset max observed latency to sustainable latency
      PROCESSED_EVENTS=$SUSTAINABLE_EVENTS #reset processed events, because at this point processed_events was unsustainable
      while [ "$THROUGHPUT_SUSTAINABLE" = "true" ]; do
        SUSTAINABLE_EVENTS=${PROCESSED_EVENTS}
		SUSTAINABLE_LATENCY=${MAX_OBSERVED_LATENCY}
		debug "SUSTAINABLE_EVENTS=${PROCESSED_EVENTS} SUSTAINABLE_LATENCY=${MAX_OBSERVED_LATENCY}"
        debug2 "Starting loadcheck $LOAD events/s"
        LOAD=$((LOAD+LOAD_INCREASE))
        run "START_LOAD_CLUSTER"
        sleep $TEST_TIME
        run "CLUSTER" "LOAD" "STOP_LOAD"
		sleep $COOL_DOWN
        run "INITIALIZE_KAFKA_CLUSTER"
        sleep 60
        run "GET_REDIS_STATS" $SPE
        run "CHECK_LATENCY"	
        run "INITIALIZE_REDIS_CLUSTER"
      done
      LOAD=$((LOAD-LOAD_INCREASE))

      echo "${EXPERIMENT_DIR};Payload;$PAYLOAD;$INFO;Nodes;$NUMBER_OF_SLAVES;SUST_THROUGHPUT;$LOAD;Duration;${TEST_TIME};ProcessedEvents;${SUSTAINABLE_EVENTS}" >> $PROJECT_HOME/last_results/sustainable_throughput.txt
      echo "${EXPERIMENT_DIR}: Load=$LOAD, Max_Sust_Lat=$MAX_SUST_LATENCY" >> $PROJECT_HOME/last_results/throughput_result.txt
      echo "${EXPERIMENT_DIR};Payload;$PAYLOAD;$INFO;Nodes;$NUMBER_OF_SLAVES;SUST_THROUGHPUT;$TOTAL_LOAD;Duration;${TEST_TIME};ProcessedEvents;${SUSTAINABLE_EVENTS};MaxObservedSustLatency;${SUSTAINABLE_LATENCY}" >> $PROJECT_HOME/${SPE}_sustainable_throughput.txt
  ##############################################################################
  ##########       COMMONS
  ##############################################################################
    elif [ "CLUSTER" = "$OPERATION" ]; then
      TARGET_ROLE=$2
      REMOTE_OPERATION=$3
      debug "Requested cluster to run operation $REMOTE_OPERATION on all nodes with role $TARGET_ROLE"
      LOCAL_EXEC="FALSE"
	  TARGET_NODES=0
      for HOST in "${!HOST_ROLES[@]}"; do
        ROLE=${HOST_ROLES[$HOST]}
        debug2 "checking HOST $HOST of ROLE $ROLE"
        debug2 "IF $TARGET_ROLE == *$ROLE* || $ROLE == *$TARGET_ROLE* || $TARGET_ROLE == 'ALL'"
		
        if [[ $TARGET_ROLE == *$ROLE* || $ROLE == *$TARGET_ROLE* || $TARGET_ROLE == "ALL" ]]; then
            # If this node is also target of the remote operation ensure that its operation is executed last (1)
			TARGET_NODES=$((TARGET_NODES+1))
            if [[ $HOST == $HOSTNAME ]]; then
              LOCAL_EXEC="TRUE"			 
            else
              debug "Performing cluster run of operation $REMOTE_OPERATION on host $HOST"
              cluster_run $HOST $REMOTE_OPERATION
            fi
        fi
      done
      # If this node is also target of the remote operation ensure that its operation is executed last (2)
      if [[ $LOCAL_EXEC == "TRUE" ]]; then
              debug "performing cluster run of operation $REMOTE_OPERATION locally on host $HOSTNAME"
              cluster_run $HOSTNAME $REMOTE_OPERATION
      fi
    elif [ "CLUSTER_SLOW" = "$OPERATION" ]; then
      TARGET_ROLE=$2
      REMOTE_OPERATION=$3
      debug "Requested cluster to run operation $REMOTE_OPERATION on all nodes with role $TARGET_ROLE"
      LOCAL_EXEC="FALSE"
	  TARGET_NODES=0
      for HOST in "${!HOST_ROLES[@]}"; do
        ROLE=${HOST_ROLES[$HOST]}
        debug2 "checking HOST $HOST of ROLE $ROLE"
        debug2 "IF $TARGET_ROLE == *$ROLE* || $ROLE == *$TARGET_ROLE* || $TARGET_ROLE == 'ALL'"
		
        if [[ $TARGET_ROLE == *$ROLE* || $ROLE == *$TARGET_ROLE* || $TARGET_ROLE == "ALL" ]]; then
            # If this node is also target of the remote operation ensure that its operation is executed last (1)
			TARGET_NODES=$((TARGET_NODES+1))
			sleep 3
            if [[ $HOST == $HOSTNAME ]]; then
              LOCAL_EXEC="TRUE"			 
            else
              debug "Performing cluster run of operation $REMOTE_OPERATION on host $HOST"
              cluster_run $HOST $REMOTE_OPERATION
            fi
        fi
      done
      # If this node is also target of the remote operation ensure that its operation is executed last (2)
      if [[ $LOCAL_EXEC == "TRUE" ]]; then
              debug "performing cluster run of operation $REMOTE_OPERATION locally on host $HOSTNAME"
              cluster_run $HOSTNAME $REMOTE_OPERATION
      fi
    elif [ "CLUSTER_ONCE" = "$OPERATION" ]; then
        TARGET_ROLE=$2
        REMOTE_OPERATION=$3
        ONCE="TRUE"
        debug "Requested cluster run operation $REMOTE_OPERATION only once on a node with role $TARGET_ROLE"
        for HOST in "${!HOST_ROLES[@]}"; do
          ROLE=${HOST_ROLES[$HOST]}
          debug2 "checking HOST $HOST of ROLE $ROLE"
          debug2 "IF: $ROLE == *$TARGET_ROLE* || $ROLE = ALL"
          if [[ $TARGET_ROLE == *$ROLE* || $ROLE == *$TARGET_ROLE* || $TARGET_ROLE == "ALL" ]]; then
              if [[ $ONCE == "TRUE" ]]; then
                debug "Performing cluster run of operation $REMOTE_OPERATION on host $HOST"
                cluster_run $HOST $REMOTE_OPERATION
                ONCE="FALSE"
              fi
          fi
        done
    elif [ "CLUSTER_GET_FILE" = "$OPERATION" ]; then
      TARGET_ROLE=$2
      FILE=$3
      DESTINATION=$4
      FILENAME=${FILE##*/}
      debug "Requested cluster to run operation $REMOTE_OPERATION on all nodes with role $TARGET_ROLE"
      for HOST in "${!HOST_ROLES[@]}"; do
        ROLE=${HOST_ROLES[$HOST]}
        debug2 "checking HOST $HOST of ROLE $ROLE"
        debug2 "IF: $ROLE == *$TARGET_ROLE* || $ROLE = ALL"
        if [[ $TARGET_ROLE == *$ROLE* || $ROLE == *$TARGET_ROLE* || $TARGET_ROLE == "ALL" ]]; then
            scp $HOST:$FILE ${DESTINATION}${HOST}_${FILENAME}
        fi
      done
    elif [ "GET_REDIS_STATS" = "$OPERATION" ]; then
      SPE=${2}
      cd $PROJECT_HOME/data
	  sleep 1
	  $LEIN run -o --configPath $CONF_FILE || true
	  sleep 6
      $LEIN run -g --configPath $CONF_FILE || true
      sleep 15
      wait_until_file_is_written2 $PROJECT_HOME/data/latency.txt
      FILESIZE=`wc -c <"$PROJECT_HOME/data/latency.txt"`
      if [ $FILESIZE = 0 ]; then
          debug "ERROR: No latency results"
          #if (( RETRY < 3 )); then
          #  RETRY=$((RETRY+1))
          #  REPEAT="TRUE"
          #else
            #debug "ERROR: to many retries -> exit"
            run "CLUSTER_STOP_ALL"
            exit
          fi
      #else
      #  REPEAT="FALSE"
      #fi
      #echo "WOULD YOU LIKE TO CONTINUE?"
      #read userinput

      cp $PROJECT_HOME/data/seen.txt $PROJECT_HOME/last_results/
      cp $PROJECT_HOME/data/updated.txt $PROJECT_HOME/last_results/
      cp $PROJECT_HOME/data/latency.txt $PROJECT_HOME/last_results/
      cp $PROJECT_HOME/data/pre-window.txt $PROJECT_HOME/last_results/
      #flink always waits for the watermark before writing its window. When the load is stopped, flink will not write the output of its last windows.
      #Therefore we implemented a custom timeout of 10s to send a final watermark that triggers flink to write its output eventually
      #However, for these last windows the latency will always be +10s, therefore we delete these last records.
      if [ "flink" = "$SPE" ]; then
        LINES=$(wc -l $PROJECT_HOME/last_results/latency.txt | awk '{print $1}')
        OFFSET=$((LINES/NUMBER_OF_CAMPAIGNS))
        
		#sed "1~${OFFSET}d" $PROJECT_HOME/last_results/latency.txt > $PROJECT_HOME/last_results/latency_corrected.txt
        STDDEV_LAT=$(awk '{for(i=1;i<=NF;i++) {sum[i] += $i; sumsq[i] += ($i)^2}} END {for (i=1;i<=NF;i++) { printf "%f \n", sqrt((sumsq[i]-sum[i]^2/NR)/NR)}}' $PROJECT_HOME/data/latency.txt)
		AVG_LAT=$(awk '{for(i=1;i<=NF;i++) {sum[i] += $i; sumsq[i] += ($i)^2}} END {for (i=1;i<=NF;i++) {printf "%f \n", sum[i]/NR}}' $PROJECT_HOME/data/latency.txt)
		MAX_DEV=$(echo $STDDEV_LAT $AVG_LAT| awk '{print $1 + $2}')
		debug "Maximum Latency Deviation is $MAX_DEV"
		awk -v var="$MAX_DEV" '{ if (($0 ~ /^[^0-9]/) || ($1 <= var)) {print $0}}' $PROJECT_HOME/data/latency.txt > $PROJECT_HOME/last_results/latency_corrected.txt

		sed "1~${OFFSET}d" $PROJECT_HOME/last_results/updated.txt > $PROJECT_HOME/last_results/updated_corrected.txt
        sed "1~${OFFSET}d" $PROJECT_HOME/last_results/pre-window.txt > $PROJECT_HOME/last_results/pre-window_corrected.txt
        mv $PROJECT_HOME/last_results/latency.txt $PROJECT_HOME/last_results/latency_original.txt
        mv $PROJECT_HOME/last_results/updated.txt $PROJECT_HOME/last_results/updated_original.txt
        mv $PROJECT_HOME/last_results/pre-window.txt $PROJECT_HOME/last_results/pre-window_original.txt
        mv $PROJECT_HOME/last_results/latency_corrected.txt $PROJECT_HOME/last_results/latency.txt
        mv $PROJECT_HOME/last_results/updated_corrected.txt $PROJECT_HOME/last_results/updated.txt
        mv $PROJECT_HOME/last_results/pre-window_corrected.txt $PROJECT_HOME/last_results/pre-window.txt
      fi
      LINES=$(wc -l $PROJECT_HOME/last_results/latency.txt | awk '{print $1}')
      OFFSET=$((LINES/NUMBER_OF_CAMPAIGNS)) # z.B. 12
      # Write semantic window IDs
      window=0
      while [ $window != $NUMBER_OF_CAMPAIGNS ]; do
        counter=0
        while [ $counter != $OFFSET ]; do
          echo "${window}" >> $PROJECT_HOME/last_results/windowIDs.txt
          counter=$((counter+1))
        done
        window=$((window+1))
      done
      # Write processing time
      counter=0
      while [ $counter != $NUMBER_OF_CAMPAIGNS ]; do
        time=$OFFSET
        while [ $time != 0 ]; do
          timestamp=$((time*10))
          echo "${timestamp}" >> $PROJECT_HOME/last_results/timings.txt
          time=$((time-1))
        done
        counter=$((counter+1))
      done
      paste $PROJECT_HOME/last_results/timings.txt $PROJECT_HOME/last_results/windowIDs.txt $PROJECT_HOME/last_results/latency.txt > $PROJECT_HOME/last_results/latency_annotated.txt
      sed -i '1 i\time window latency' $PROJECT_HOME/last_results/latency_annotated.txt

      PROCESSED_EVENTS=`cat $PROJECT_HOME/last_results/seen.txt | awk '{s+=$1} END {print s}'`
    elif [ "CHECK_LATENCY" = "$OPERATION" ]; then
      mv $PROJECT_HOME/last_results/latency.txt $PROJECT_HOME/last_results/${LOAD}_latency.txt
      MAX_OBSERVED_LATENCY=`cat $PROJECT_HOME/last_results/${LOAD}_latency.txt | awk 'max<$1 || NR==1{ max=$1 } END {print max}'`
      echo "Max observed latency for load $LOAD = $MAX_OBSERVED_LATENCY ms" >> $PROJECT_HOME/last_results/sustainable_throughput.txt
      echo "Max sustainable latency = $MAX_SUST_LATENCY" >> $PROJECT_HOME/last_results/sustainable_throughput.txt

      if (( MAX_OBSERVED_LATENCY < MAX_SUST_LATENCY )); then
        THROUGHPUT_SUSTAINABLE="true"
      else
        echo "Load $LOAD not sustainable. Observed latency was $MAX_OBSERVED_LATENCY. Max allowed latency is $MAX_SUST_LATENCY" >> $PROJECT_HOME/last_results/sustainable_throughput.txt
        THROUGHPUT_SUSTAINABLE="false"
      fi

    elif [ "TEST2" = "$OPERATION" ]; then
		run "START_LOAD_CLUSTER"
		echo "2nd Load Cluster"
		run "START_LOAD_CLUSTER"
		
	elif [ "TEST" = "$OPERATION" ]; then

          run "START_REDIS_KAFKA_CLUSTER"
          run "START_FLINK_CLUSTER"
          run "START_FLINK_PROCESSING_CLUSTER"
          echo "################################################################################################################################################################################"
          echo "######## WOULD YOU LIKE TO START THE LOAD CLUSTER? ####"
          read userInput
          #run "WARMUP_PHASE"
          run "START_LOAD_CLUSTER"
          #run "CLUSTER" "MASTER_SLAVE" "PROFILE_FLINK"
          #run "CLUSTER_PROFILE" "PROFILE_FLINK"
          echo "################################################################################################################################################################################"
          echo "######## WOULD YOU LIKE TO STOP THE LOAD CLUSTER? ####"
          read userInput
          #sleep $TEST_TIME
          run "CLUSTER" "LOAD" "STOP_LOAD"
          echo "################################################################################################################################################################################"
          echo "######## NOW PLEASE CHECK IF YOUR PROGRAM CAN DEAL WITH THIS? ####"
          read userInput
          run "START_LOAD_CLUSTER"
          echo "################################################################################################################################################################################"
          echo "######## DOES YOUR PROGRAM STILL WORK? ####"
          read userInput
          run "CLUSTER" "LOAD" "STOP_LOAD"
          #sleep $COOL_DOWN
          #run "INITIALIZE_KAFKA_CLUSTER"
          #wait_for "MASTER_SLAVE" "FINISHED_RESULT_AGGREGATION"
          run "STOP_FLINK_PROCESSING_CLUSTER"
          run "STOP_FLINK_CLUSTER"
          #run "GET_STATS" "flink"
          run "STOP_REDIS_KAFKA_CLUSTER"

    elif [ "CLUSTER_PROFILE" = "$OPERATION" ]; then
            PROFILING_OPERATION=$2
            debug2 "Starting $TARGET_ENGINE"
            for HOST in "${!HOST_ROLES[@]}"; do
              ROLE=${HOST_ROLES[$HOST]}
              if [[ $ROLE == *"SLAVE"* ]]; then
                  debug "Start $PROFILING_OPERATION on host $HOST"
                  BPF_PROFILING="TRUE"
                  cluster_profile $HOST $PROFILING_OPERATION
              elif [[ $ROLE == *"MASTER"* ]]; then
                  BPF_PROFILING="FALSE"
                  cluster_profile $HOST $PROFILING_OPERATION
              fi
            done

	################################################
	# REDIS CLUSTER MANAGEMENT
	################################################
  elif [ "START_REDIS" = "$OPERATION" ]; then
    start_if_needed redis-server Redis 1 "$PROJECT_HOME/$REDIS_DIR/src/redis-server" "--protected-mode no"
    cd $PROJECT_HOME/data
    $LEIN run -n --campaigns $NUMBER_OF_CAMPAIGNS --configPath $CONF_FILE
    cd ..
    KEY_COUNT=$(echo "DBSIZE" | $PROJECT_HOME/$REDIS_DIR/src/redis-cli | grep -E '[0-9]{1,}')
    debug "Number of keys in Redis = $KEY_COUNT, expected 1002 (1000x campaign-Ids + 'ads' + 'campaigns')"
    $PROJECT_HOME/utils/getAllKeys2.sh
    #TODO JRA should be 1002 -> 1000x campaigns + 2 (ads and campaigns)
    progress "REDIS_STARTED"

  elif [ "STOP_REDIS" = "$OPERATION" ]; then
    stop_if_needed redis-server Redis
    rm -f dump.rdb

  elif [ "INITIALIZE_REDIS" = "$OPERATION" ]; then
    cd $PROJECT_HOME
    debug "Initialized Redis with $PROJECT_HOME/utils/writeAllKeys2.sh"
    $PROJECT_HOME/utils/writeAllKeys2.sh
	debug "REDIS_INITIALIZED"
    progress "REDIS_INITIALIZED"

  elif [ "INITIALIZE_REDIS_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER_ONCE" "REDIS" "INITIALIZE_REDIS"
    wait_for "REDIS" "REDIS_INITIALIZED"
    sleep 20

  elif [ "START_REDIS_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER" "REDIS" "START_REDIS"

  elif [ "STOP_REDIS_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER" "REDIS" "STOP_REDIS"


	################################################
	# KAFKA CLUSTER MANAGEMENT
	################################################
  elif [ "START_KAFKA" = "$OPERATION" ]; then
    start_if_needed kafka\.Kafka Kafka 10 "$PROJECT_HOME/$KAFKA_DIR/bin/kafka-server-start.sh" "$PROJECT_HOME/$KAFKA_DIR/config/server.properties"
    progress "KAFKA_STARTED"
  elif [ "CREATE_KAFKA_TOPIC" = "$OPERATION" ]; then
	create_kafka_topic
    KAFKA_OUTPUT=$($PROJECT_HOME/$KAFKA_DIR/bin/kafka-topics.sh --describe --bootstrap-server localhost:9092 --topic $TOPIC)
	echo "$KAFKA_OUTPUT"
    debug "Kafka - Expected number of partitions = $PARTITIONS"
    debug "Created Kafka Partitions: "
    debug "$KAFKA_OUTPUT"
  elif [ "STOP_KAFKA" = "$OPERATION" ]; then
    # JMX Dump
    #java -jar  ${PROJECT_HOME}/utils/jmx-dump-0.10.3.jar -h localhost -p 9998 --dump-all > ${PROJECT_HOME}/kafka-jmx-dump.json #profiling/measurments/${EXPERIMENT_DIR}/tmp/kafka-jmx-dump.json
    stop_if_needed kafka\.Kafka Kafka
    rm -rf $KAFKALOGS
    progress "KAFKA_STOPPED"

    elif [ "GET_OFFSET_KAFKA" = "$OPERATION" ]; then
    stop_if_needed org.apache.zookeeper.server ZooKeeper
    rm -rf $ZKSTATE

  elif [ "INITIALIZE_KAFKA" = "$OPERATION" ]; then
    $PROJECT_HOME/$KAFKA_DIR/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic ad-events | awk -F  ":" '{sum += $3} END {print sum}' >> $PROJECT_HOME/profiling/measurments/$EXPERIMENT_DIR/tmp/kafka_events_after_initializing.txt
    #$PROJECT_HOME/$KAFKA_DIR/bin/kafka-delete-records.sh --bootstrap-server localhost:9092 --offset-json-file $PROJECT_HOME/utils/delete-ad-events.config
    #debug "KAFKA Initialized with $PROJECT_HOME/$KAFKA_DIR/bin/kafka-delete-records.sh --bootstrap-server localhost:9092 --offset-json-file $PROJECT_HOME/utils/delete-ad-events.config"
    #$PROJECT_HOME/$KAFKA_DIR/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic ad-events | awk -F  ":" '{sum += $3} END {print sum}' >> $PROJECT_HOME/profiling/measurments/$EXPERIMENT_DIR/tmp/kafka_partitions_after_initializing.txt
    progress "KAFKA_INITIALIZED"


  elif [ "START_ZK" = "$OPERATION" ]; then
    start_if_needed org.apache.zookeeper.server ZooKeeper 10 "$PROJECT_HOME/$KAFKA_DIR/bin/zookeeper-server-start.sh" $PROJECT_HOME/$KAFKA_DIR/config/zookeeper.properties

  elif [ "STOP_ZK" = "$OPERATION" ]; then
    stop_if_needed org.apache.zookeeper.server ZooKeeper
    rm -rf $ZKSTATE

  elif [ "INITIALIZE_KAFKA_CLUSTER" = "$OPERATION" ]; then
      run "CLUSTER_ONCE" "ZK" "INITIALIZE_KAFKA"
	  sleep 5
      #wait_for "KAFKA" "KAFKA_INITIALIZED"

  elif [ "START_KAFKA_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER" "ZK" "START_ZK"
	sleep 6
	run "CLUSTER_SLOW" "KAFKA" "START_KAFKA"
	sleep 15
	run "CLUSTER_ONCE" "KAFKA" "CREATE_KAFKA_TOPIC"
	
  elif [ "STOP_KAFKA_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER" "KAFKA" "STOP_KAFKA"
    sleep 5
    run "CLUSTER" "ZK" "STOP_ZK"

  elif [ "TEST_KAFKA_THROUGHPUT" = "$OPERATION" ]; then
    run "START_REDIS_KAFKA_CLUSTER"
	sleep 10
	echo "[SPS-BENCH] Start Load Cluster"
	run "START_LOAD_CLUSTER"
	LOAD_NODES=$TARGET_NODES
	sleep $TEST_TIME
	sleep 0.1
	run "STOP_LOAD_CLUSTER"
	echo "[SPS-BENCH] Stop Load Cluster"
	RECEIVED_EVENTS=$($PROJECT_HOME/$KAFKA_DIR/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic ad-events | awk -F  ":" '{sum += $3} END {print sum}')
	KAFKA_OUTPUT=$($PROJECT_HOME/$KAFKA_DIR/bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic ad-events)
	LOAD_THROUGHPUT=$((RECEIVED_EVENTS/TEST_TIME))
	LOAD_PER_NODE=$((LOAD_THROUGHPUT/LOAD_NODES))
	run "CLUSTER" "KAFKA" "STOP_KAFKA"
	run "STOP_REDIS"
	
    sleep 5
    run "CLUSTER" "ZK" "STOP_ZK"
	sleep 5
	
	echo "$KAFKA_OUTPUT"
	echo "[SPS-BENCH] Received Events: $RECEIVED_EVENTS"
	echo "[SPS-BENCH] Number of Hosts with Role LOAD: $LOAD_NODES"
	echo "[SPS-BENCH] Total Throughput per second: $LOAD_THROUGHPUT"
	echo "[SPS-BENCH] Configured Load per Loadgenerator: $LOAD"
	echo "[SPS-BENCH] Actual Load per Loadgenerator: $LOAD_PER_NODE"

	################################################
	# SPARK CLUSTER MANAGEMENT
	################################################
  elif [ "START_SPARK" = "$OPERATION" ]; then
    start_if_needed org.apache.spark.deploy.worker.Worker SparkSlave 5 $PROJECT_HOME/$SPARK_DIR/sbin/start-all.sh
    progress "SPARK_CLUSTER_STARTED"
  elif [ "CLEAR_WORK" = "$OPERATION" ]; then
    rm -rf $PROJECT_HOME/$SPARK_DIR/work/*
    progress "SPARK_WORK_CLEARED"
  elif [ "START_SPARK_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER" "MASTER" "START_SPARK"
    wait_for "MASTER" "SPARK_CLUSTER_STARTED"

  elif [ "STOP_SPARK" = "$OPERATION" ]; then
    $PROJECT_HOME/$SPARK_DIR/sbin/stop-all.sh

  elif [ "START_SPARK_PROCESSING" = "$OPERATION" ]; then
  # --conf spark.streaming.backpressure.enabled=true --conf spark.streaming.backpressure.initialRate=14000
  debug "'$SPARK_DIR/bin/spark-submit' --master spark://${HOST_MASTER}:7077 --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.2.0 --class spark.benchmark.SparkCPImplementierung --conf spark.cleaner.referenceTracking=false --conf spark.cleaner.referenceTracking.blocking=false --conf spark.cleaner.referenceTracking.blocking.shuffle=false --conf spark.cleaner.referenceTracking.cleanCheckpoints=false $PROJECT_HOME/spark-benchmarks/target/spark-structured-benchmarks-0.1.0.jar '$CONF_FILE'"
    "${SPARK_DIR}/bin/spark-submit" --master spark://${HOST_MASTER}:7077 --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.2.0 --class spark.benchmark.SparkCPImplementierung --conf spark.cleaner.referenceTracking=false --conf spark.cleaner.referenceTracking.blocking=false --conf spark.cleaner.referenceTracking.blocking.shuffle=false --conf spark.cleaner.referenceTracking.cleanCheckpoints=false $PROJECT_HOME/spark-benchmarks/target/$PAYLOAD_SPARK "$CONF_FILE" &
    #"$SPARK_DIR/bin/spark-submit" --master spark://$HOST_MASTER:7077 --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.2.0 --class spark.benchmark.SparkContinuousProcessing --conf spark.cleaner.referenceTracking=false --conf spark.cleaner.referenceTracking.blocking=false --conf spark.cleaner.referenceTracking.blocking.shuffle=false --conf spark.cleaner.referenceTracking.cleanCheckpoints=false $PROJECT_HOME/spark-cp-benchmarks/target/spark-cp-benchmarks-0.1.0.jar "$CONF_FILE" &
	sleep 10
    progress "SPARK_PROCESSING_STARTED"

  elif [ "START_SPARK_CP_PROCESSING" = "$OPERATION" ]; then
  debug "'$SPARK_DIR/bin/spark-submit' --master spark://${HOST_MASTER}:7077 --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.2.0 --class spark.benchmark.SparkCPImplementierung --conf spark.cleaner.referenceTracking=false --conf spark.cleaner.referenceTracking.blocking=false --conf spark.cleaner.referenceTracking.blocking.shuffle=false --conf spark.cleaner.referenceTracking.cleanCheckpoints=false $PROJECT_HOME/spark-benchmarks/target/spark-structured-benchmarks-0.1.0.jar '$CONF_FILE'"
    #"$SPARK_DIR/bin/spark-submit" --master spark://${HOST_MASTER}:7077 --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.2.0 --class spark.benchmark.SparkCPImplementierung --conf spark.cleaner.referenceTracking=false --conf spark.cleaner.referenceTracking.blocking=false --conf spark.cleaner.referenceTracking.blocking.shuffle=false --conf spark.cleaner.referenceTracking.cleanCheckpoints=false $PROJECT_HOME/spark-benchmarks/target/$PAYLOAD_SPARK "$CONF_FILE" &
    "$SPARK_DIR/bin/spark-submit" --master spark://$HOST_MASTER:7077 --packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.2.0 --class spark.benchmark.SparkContinuousProcessing --conf spark.cleaner.referenceTracking=false --conf spark.cleaner.referenceTracking.blocking=false --conf spark.cleaner.referenceTracking.blocking.shuffle=false --conf spark.cleaner.referenceTracking.cleanCheckpoints=false $PROJECT_HOME/spark-cp-benchmarks/target/$PAYLOAD_SPARK_CP "$CONF_FILE" &
	sleep 10
    progress "SPARK_PROCESSING_STARTED"

  elif [ "STOP_SPARK_PROCESSING" = "$OPERATION" ]; then
    stop_if_needed spark.benchmark.SparkCPImplementierung "Spark Client Process"
	rm -rf $SPARK_DIR/work/*

  elif [ "STOP_SPARK_CP_PROCESSING" = "$OPERATION" ]; then
    stop_if_needed spark.benchmark.SparkContinuousProcessing "Spark Client Process"
	rm -rf $SPARK_DIR/work/*

  elif [ "START_SPARK_PROCESSING_CLUSTER" = "$OPERATION" ]; then
	PAYLOAD=$PAYLOAD_SPARK
    run "CLUSTER" "MASTER" "START_SPARK_PROCESSING"
    wait_for "MASTER" "SPARK_PROCESSING_STARTED"

  elif [ "START_SPARK_CP_PROCESSING_CLUSTER" = "$OPERATION" ]; then
    PAYLOAD=$PAYLOAD_SPARK_CP
	run "CLUSTER" "MASTER" "START_SPARK_CP_PROCESSING"
    wait_for "MASTER" "SPARK_PROCESSING_STARTED"

  elif [ "STOP_SPARK_PROCESSING_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER" "MASTER" "STOP_SPARK_PROCESSING"

  elif [ "STOP_SPARK_CP_PROCESSING_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER" "MASTER" "STOP_SPARK_CP_PROCESSING"

  elif [ "STOP_SPARK_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER" "MASTER" "STOP_SPARK"
	run "CLUSTER" "SLAVE" "CLEAR_WORK"
	wait_for "SPARK_WORK_CLEARED"
	################################################
	# FLINK CLUSTER MANAGEMENT
	################################################
  elif [ "START_FLINK" = "$OPERATION" ]; then
    start_if_needed org.apache.flink.runtime.jobmanager.JobManager Flink 1 $PROJECT_HOME/$FLINK_DIR/bin/start-cluster.sh
    progress "FLINK_CLUSTER_STARTED"

  elif [ "START_FLINK_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER" "MASTER" "START_FLINK"
    wait_for "MASTER" "FLINK_CLUSTER_STARTED"
    sleep 5

  elif [ "STOP_FLINK" = "$OPERATION" ]; then
    $FLINK_DIR/bin/stop-cluster.sh

  elif [ "STOP_FLINK_CLUSTER" = "$OPERATION" ]; then
    run "CLUSTER" "MASTER" "STOP_FLINK"

  elif [ "START_FLINK_PROCESSING" = "$OPERATION" ]; then
    debug "$FLINK_DIR/bin/flink run $PROJECT_HOME/flink-benchmarks/target/${PAYLOAD_FLINK} --confPath $CONF_FILE &"
    "$FLINK_DIR/bin/flink" run $PROJECT_HOME/flink-benchmarks/target/${PAYLOAD_FLINK} --confPath $CONF_FILE &
    progress "FLINK_PROCESSING_STARTED"

  elif [ "START_FLINK_PROCESSING_CLUSTER" = "$OPERATION" ]; then
    PAYLOAD=$PAYLOAD_FLINK
	run "CLUSTER" "MASTER" "START_FLINK_PROCESSING"
    wait_for "MASTER" "FLINK_PROCESSING_STARTED"
    sleep 5

  elif [ "STOP_FLINK_PROCESSING" = "$OPERATION" ]; then
    FLINK_ID=`"$FLINK_DIR/bin/flink" list | grep 'Flink Streaming Job' | awk '{print $4}'; true`
    if [ "$FLINK_ID" == "" ]; then
	    echo "Could not find streaming job to kill"
    else
      #"$FLINK_DIR/bin/flink" stop --savepointPath /tmp/flink-savepoints --drain $FLINK_ID
      "$FLINK_DIR/bin/flink" cancel $FLINK_ID
    fi

  elif [ "STOP_FLINK_PROCESSING_CLUSTER" = "$OPERATION" ]; then
	  run "CLUSTER" "MASTER" "STOP_FLINK_PROCESSING"

	################################################
	# Load Cluster Management
	################################################
  elif [ "START_LOAD" = "$OPERATION" ]; then
    echo "Starting load on $HOSTNAME"
	cd $PROJECT_HOME/data
	$LEIN run -r -t $LOAD -p 8 --configPath $CONF_FILE &
	#round down
	#NUM_GENERATORS=$(($LOAD/200000))
	#LOAD_MOD=$((LOAD%200000))
	#echo "$NUM_GENERATORS * 200k + $LOAD_MOD"
	#i=0
	#while [ $i != $NUM_GENERATORS ]; do
	#	echo "Starting loadgenerator instance ${i} on $HOSTNAME with load = 200000"
	#	$LEIN run -r -t 200000 --configPath $CONF_FILE &
	#	sleep 0.2
	#	i=$((i+1))
	#done
	#if (($LOAD_MOD > 0 )); then
	#	echo "Starting loadgenerator instance ${i} on $HOSTNAME with load = $LOAD_MOD"
	#	$LEIN run -r -t $LOAD_MOD --configPath $CONF_FILE &
	#	sleep 3
	#fi
    #start_if_needed leiningen.core.main "Load Generation" 1 $LEIN run -r -t $LOAD --configPath $CONF_FILE
    #$LEIN run -r -t $LOAD --configPath $CONF_FILE
	#echo "Running: $LEIN run -r -t $LOAD --configPath $CONF_FILE &"
	cd ..

  elif [ "START_LOAD_CLUSTER" = "$OPERATION" ]; then
    
	run "CLUSTER" "LOAD" "START_LOAD"
    sleep 6

  elif [ "STOP_LOAD" = "$OPERATION" ]; then
    pkill -f "clojure"
    progress "LOAD_STOPPED"

  elif [ "STOP_LOAD_CLUSTER" = "$OPERATION" ]; then
      run "CLUSTER" "LOAD" "STOP_LOAD"


	################################################
	# PERFORMANCE MEASURMENT
	################################################
  elif [ "PROFILE_FLINK" = "$OPERATION" ]; then
        DURATION=$(($TEST_TIME+$COOL_DOWN))
        debug "$PROJECT_HOME/profiling/scripts/sps_profiler.sh -o 'PROFILE_FLINK' -d ${DURATION} -f $HERTZ -p ${PROJECT_HOME} -b $BPF_PROFILING -w $WAIT_TIME &"
        $PROJECT_HOME/profiling/scripts/sps_profiler.sh -o "PROFILE_FLINK" -d ${DURATION} -f $HERTZ -p ${PROJECT_HOME} -b $BPF_PROFILING -w $WAIT_TIME &

  elif [ "PROFILE_SPARK" = "$OPERATION" ]; then
        DURATION=$(($TEST_TIME+$COOL_DOWN))
        debug "$PROJECT_HOME/profiling/scripts/sps_profiler.sh -o 'PROFILE_SPARK' -d ${DURATION} -f $HERTZ -p ${PROJECT_HOME} -b $BPF_PROFILING -w $WAIT_TIME &"
        $PROJECT_HOME/profiling/scripts/sps_profiler.sh -o "PROFILE_SPARK" -d ${DURATION} -f $HERTZ -p ${PROJECT_HOME} -b $BPF_PROFILING -w $WAIT_TIME &

  elif [ "PROFILE_SPARK_CP" = "$OPERATION" ]; then
        DURATION=$(($TEST_TIME+$COOL_DOWN))
        debug "$PROJECT_HOME/profiling/scripts/sps_profiler.sh -o "PROFILE_SPARK_CP" -d ${DURATION} -f $HERTZ -p ${PROJECT_HOME} -b $BPF_PROFILING -w $WAIT_TIME &"
        $PROJECT_HOME/profiling/scripts/sps_profiler.sh -o "PROFILE_SPARK_CP" -d ${DURATION} -f $HERTZ -p ${PROJECT_HOME} -b $BPF_PROFILING -w $WAIT_TIME &

  elif [[ "GLOBAL_PERF_STAT" = "$OPERATION" ]]; then
    #JRATODO
    echo "Call bpfscript on all nodes"


  else
    if [ "HELP" != "$OPERATION" ];
    then
      echo "UNKNOWN OPERATION '$OPERATION'"
      echo
    fi
    echo "Supported OPTIONS"
    echo "-o| -operation 'OPERATION'-> See 'Supported Operations'"
    echo "-t| --timer 'INT' -> Duration of the Benchmark run"
    echo "-b| --bpfprofiler 'TRUE/FALSE' -> Activate/Deactive profiling with bpf (PMC measurment will always be performed)"
    echo "-e| --experiment 'EXPERIMENT_DIR' -> Will be used in $PROJECT_HOME/profiling/measurments/EXPERIMENT_DIR to store your results."
    echo "                                    If not set a new dynamic name will be generated. -p will be ignored."
    echo "                                    Set this to an existing EXPERIMENT_DIR in order to not generate a new folder."
    echo "-p| --prefix 'PREFIXNAME' -> Add a prefix to the dynamically generated experiment name"
    echo "-l| --load 'INT' -> How many events/s per LOAD node? Set a reasonable numer considiring the sizing of your LOAD Nodes.
						   -> <SPE>_CLUSTER_BENCH: Defines the load to be applied
						   -> <SPE>_CLUSTER_BENCH_LOOP: Defines the maximum load of the loop. Use -s to define start and -i for the load increase
						   -> <SPE>_MAX_SUST_THROUGHPUT: Not used, define start load with -s and load increase with -i"
    echo "-f| --frequency 'INT' -> Sampling rate for BPF. Default 99"
    echo "-d| --debug 'TRUE/FALSE' -> Print debug messages to EXPERIMENT_DIR/bench_debug.log"
    echo "-w| --warmup 'INT' -> Time of the warmup phase. This duration will not be measured (CPU/Throughput/Latency)"
    echo "-c| --cooldown 'INT' -> During cooldown only the loadgeneration has stopped, hence your SPE can finish its operation (will be measured)"
    echo ""
    echo ""
    echo "Supported OPERATIONS:"
    echo "FLINK_CLUSTER_BENCH: Run the spark benchmark application"
    echo "SPARK_CLUSTER_BENCH: Run the spark benchmark application"
    echo "CLUSTER_STOP_ALL: Stops all clusters and kills remaining scripts"
    echo "[START|STOP]_{INSTANCE}: Locally start/stop the respective instance (PROCESSING refers to the submission of the java application)"
    echo "[START|STOP]_{INSTANCE}_CLUSTER: Remotely start/stop the respective instance on the cluster"
    echo "INSTANCE = [REDIS|KAFKA|LOAD|FLINK|SPARK|FLINK_PROCESSING|SPARK_PROCESSING]"
    echo "HELP: print out this message"

    exit 1
  fi
  end=`date +%s`
  runtime=$((end-start))
  debug2 "The Operation $OPERATION took $runtime seconds"
}

while [ "$1" != "" ]; do
	case $1 in
		-o| --operation )		shift
      OPERATION=$1
      BENCHMARK_VARIANT=$OPERATION
      ;;
		-a| --application )		shift
      PAYLOAD_FLINK=$1
      PAYLOAD_SPARK=$PAYLOAD_FLINK
	  PAYLOAD_SPARK_CP=$PAYLOAD_FLINK
      ;;
		-t| --timer )		shift
      TEST_TIME=$1
      ;;
    -n| --numcamp )		shift
      NUMBER_OF_CAMPAIGNS=$1
      ;;
		-m| --metadata )		 shift
      INFO=$1
      ;;
		-b| --bpfprofiler )		 shift
      BPF_PROFILING=$1
      ;;
    -e| --experiment )		 shift
      PASSED_EXPERIMENT=$1
      ACTIVE_EXP="TRUE"
      ;;
	-p| --prefix )		shift
	  PREFIX=${1}
      EXPERIMENT_DIR="${PREFIX}_${EXPERIMENT_DIR}"
      ;;
	-l| --load )		shift
      LOAD=$1
	  TOTAL_LOAD=$((LOAD*4))
      ;;
		-f| --frequency )		shift
      HERTZ=$1
      ;;
	-s| --startload )		 shift
      START_LOAD=$1
      ;;	  
		-r| --runs )		 shift
      RUNS=$1
      ;;
		-d| --debug )		 shift
      DEBUG=$1
	  DEBUG_STDOUT=$1
      ;;
		-w| --warmup )		shift
      WARMUP_PHASE=$1
      ;;
    -c| --cooldown )   shift
      COOL_DOWN=$1
      ;;
    -i| --increase )   shift
      LOAD_INCREASE=$1
      ;;
		-h| --help )		shift
      HELP=true
      ;;
	esac
	shift
done
cd $PROJECT_HOME


if [[ $OPERATION == "" ]]; then
  OPERATION="HELP"
fi
EXPERIMENT_DIR="${EXPERIMENT_DIR}_${BENCHMARK_VARIANT}_Load${LOAD}_Duration${TEST_TIME}_Frequ${HERTZ}_Warmup${WARM_UP}"
if [[ $ACTIVE_EXP == "TRUE" ]]; then
  EXPERIMENT_DIR=$PASSED_EXPERIMENT
fi



readHostRoles
readClusterConf

check_file_structure
run "${OPERATION}"
