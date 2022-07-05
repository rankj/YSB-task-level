#!/bin/bash
PROJECT_HOME=/YSB-task-level
OPERATION="HELP"
TIMER=300
WAIT_TIME=0
HERTZ=99
PROFILING_TIMER=180
BPF_PROFILING="TRUE"
BPF_NETWORK_TRACE="FALSE"
EXPERIMENT_DIR=""
TIME_OUT=600
NODE_ENVIRONMENT=""
APPLICATION_PROFILE=""
APPLICATION_PROFILE_FLINK="${PROJECT_HOME}/profiling/config/flink_application_profile.txt"
APPLICATION_PROFILE_SPARK="${PROJECT_HOME}/profiling/config/spark_application_profile.txt"
APPLICATION_PROFILE_SPARK_CP="${PROJECT_HOME}/profiling/config/spark_cp_application_profile.txt"
STACK_TRACE_FILE=""
RESULT=""
DEBUG="TRUE"
PASSWORD="ucchiwi1!"

declare -A ALL_PIDS # All PIDs belonging to the Stream Processing System on this host
declare -A APPL_PIDS # All PIDs that are responsible for executing the streaming application (.jar file)
declare -A PID_NAMES

# Interface: <ProcessName> <FilterName> <ArrayVariable>
analyze_scope(){
  # Use namerefs to pass the functions arguments (ALL_PIDS / APPL_PIDS) by reference
  local -n PIDS=$3

  PIDS=`ps -aef | grep ${2} | grep -v grep  | awk '{print $2}'`
  echo "$PIDS" > $PROJECT_HOME/last_results/${1}_scope.txt
  debug "analyze_scope: $PIDS"
}

#####   Debugging function, can be deactivated with DEBUG variable   #####
debug(){
MSG=${1}
TIMESTAMP=`date +%T.%N`
if [[ $DEBUG == "TRUE" ]]
then
  echo "[DEBUG] $HOSTNAME $TIMESTAMP: $MSG" >> $PROJECT_HOME/last_results/sps_profiler_debug.log
fi
}

#####   Set process names for ALL_PIDS
set_pid_names(){
  for pid in $ALL_PIDS
    do
      NAME=`ps -aef | grep $pid | grep -v grep`
      NAME=${NAME//[$'\n']}
      PID_NAMES[$pid]="$NAME"
    done
}

#####    Prepare Bpftrace Scripts for APPL_PIDS, workload and stacktrace, Interface: APPL_PIDS and TIMER  #####
prepare_tracers(){
debug "prepare_tracers"
echo "$APPL_PIDS" | while IFS= read -r pid
do 
  echo "kr:sock_recvmsg / retval > 0 && pid == ${pid} / { @[ comm] = sum(retval); } interval:s:${TIMER} {exit(); }" > $PROJECT_HOME/last_results/${pid}_workload_trace.bt
  echo "profile:hz:${HERTZ} /pid == ${pid}/ { @[ustack] = count(); } interval:s:${PROFILING_TIMER} {exit(); }" > $PROJECT_HOME/last_results/${pid}_stacktrace.bt
  #bpftrace --unsafe -e 'profile:hz:99 /pid == 685/ { @[ustack] = count(); } interval:s:30 { exit(); } END { system("jperfmap 685 --unfold_all"); }'
  #bpftrace --unsafe -e 'profile:hz:99 /pid == 685/ { @[ustack] = count(); } END { system("jperfmap 685 --unfold_all"); }
     #
done
}

#####   Perf tracing for ALL_PIDS, Interface: ALL_PIDS and TIMER   #####
perf_stat(){
  for pid in ${ALL_PIDS[@]}; do
    perf stat -o $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt -p ${pid} -a sleep ${TIMER} &
    debug "perf_stat perf stat -o $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt -p ${pid} -a sleep ${TIMER} &"
    #$PROJECT_HOME/profiling/scripts/cpu_util.sh -p ${pid} -o $PROJECT_HOME/last_results/${pid}_top.txt -d ${TIMER} &
  done
}

### Write progress status ####
progress(){
  STATE=${1}
  TIMESTAMP=`date +%T.%N`
  touch  $PROJECT_HOME/last_results/progress.txt
  echo "${1} : $TIMESTAMP" >> $PROJECT_HOME/last_results/progress.txt
}

#####   Workload tracing   #####
trace_network_workload(){
  echo "$APPL_PIDS" | while IFS= read -r pid
  do
    bpftrace --unsafe $PROJECT_HOME/last_results/${pid}_workload_trace.bt >  $PROJECT_HOME/last_results/${pid}_workload_result.txt 2>&1 &
    debug "trace_network_workload bpftrace --unsafe $PROJECT_HOME/last_results/${pid}_workload_trace.bt >  $PROJECT_HOME/last_results/${pid}_workload_result.txt 2>&1 &"
  done
}

#####   Stacktrace sampling for APPL_PIDS   #####
stacktrace_sampling(){
  #$PROJ_HOME/profiling/FlameGraph/jmaps
  sleep $WAIT_TIME
  export BPFTRACE_MAP_KEYS_MAX=65536
  echo "$APPL_PIDS" | while IFS= read -r pid
  do
    debug "PID = $pid"
    if [[ $pid != "" ]]
    then
      debug "start stacktrace sampling for $pid"
      debug "Start JMAPS"
      debug "JAVA_HOME = $JAVA_HOME"
      debug "${PROJECT_HOME}/profiling/perf-map-agent/bin/create-java-perf-map.sh ${pid} unfoldall"
      echo "Starting perf-map.sh"
      ${PROJECT_HOME}/profiling/perf-map-agent/bin/create-java-perf-map.sh ${pid} unfoldall >> ${PROJECT_HOME}/last_results/java_perf_map.log
      PERF_MAP_TIMER=$((PROFILING_TIMER-5))
      echo "Starting perf-map.sh in background"
      (sleep $PERF_MAP_TIMER; ${PROJECT_HOME}/profiling/perf-map-agent/bin/create-java-perf-map.sh ${pid} unfoldall msig)&
      debug "START BPFTRACE for PID $pid"
      bpftrace --unsafe $PROJECT_HOME/last_results/${pid}_stacktrace.bt -o $PROJECT_HOME/last_results/${pid}_stacktrace_result.txt &
      debug "bpftrace --unsafe $PROJECT_HOME/last_results/${pid}_stacktrace.bt -o $PROJECT_HOME/last_results/${pid}_stacktrace_result.txt &"
    fi
  done
}

#####   Compute Flamegraphs   #####
flamegraph(){
  echo "$APPL_PIDS" | while IFS= read -r pid
  do
    if [[ $pid != "" ]]
    then
      debug "waiting until stacktrace_result.txt is written"
      wait_until_file_is_written "$PROJECT_HOME/last_results/${pid}_stacktrace_result.txt" "]:"
      wait_until_file_is_written2 "$PROJECT_HOME/last_results/${pid}_stacktrace_result.txt"
      debug "stacktrace_result.txt completed. Start FlameGraph Generation"
      #Check if parts of the stacktrace could not be resolved
      if grep -q "0x2000" "$PROJECT_HOME/last_results/${pid}_stacktrace_result.txt"; then
        mv $PROJECT_HOME/last_results/${pid}_stacktrace_result.txt $PROJECT_HOME/last_results/${pid}_stacktrace_result.bak
        #cp /tmp/perf-${pid}.map $PROJECT_HOME/last_results/perf-${pid}.map
        sed 's/^./0x&/' /tmp/perf-${pid}.map > $PROJECT_HOME/last_results/perf-${pid}.map
        awk 'NR==FNR {adr[$1]=$2; next} {for (i=1; i<=NF; i++) if ($i in adr) $i=adr[$i]; print}' $PROJECT_HOME/last_results/perf-${pid}.map $PROJECT_HOME/last_results/${pid}_stacktrace_result.bak > $PROJECT_HOME/last_results/${pid}_stacktrace_result.txt
      fi
      ${PROJECT_HOME}/profiling/FlameGraph/stackcollapse-bpftrace.pl $PROJECT_HOME/last_results/${pid}_stacktrace_result.txt > $PROJECT_HOME/last_results/${pid}_stacktrace_result.collapsed.txt
	  sed '/^    0x200.........;/d'  $PROJECT_HOME/last_results/${pid}_stacktrace_result.collapsed.txt >  $PROJECT_HOME/last_results/${pid}_stacktrace_result.collapsed.txt.tmp
	  rm $PROJECT_HOME/last_results/${pid}_stacktrace_result.collapsed.txt
	  mv $PROJECT_HOME/last_results/${pid}_stacktrace_result.collapsed.txt.tmp $PROJECT_HOME/last_results/${pid}_stacktrace_result.collapsed.txt
      ${PROJECT_HOME}/profiling/FlameGraph/flamegraph.pl --color=java --hash < $PROJECT_HOME/last_results/${pid}_stacktrace_result.collapsed.txt > $PROJECT_HOME/last_results/${pid}_stacktrace_flamegraph.svg
    fi
  done
}

# Check if specific file exists, {1} = File
wait_until_file_exists() {
while [ ! -f "${1}" ]
do
  debug "waiting for file ${1} to be created"
  sleep 5
done
debug "[SUCCESS] File ${1} found"
}

# Check if specific word is written in file, {1} = File, {2} = Word to check
wait_until_file_is_written() {
FOUND=`grep "${2}" "${1}" | grep -v grep`
debug "wait_until_file_is_written: grepping for ${2} in file ${1}"
local
RETRY=0
  while [ "$FOUND" == "" ]
  do

    if (( $RETRY >= $TIME_OUT )); then
      debug "ERROR: sps_profiler.sh - Waiting for matching Word ${2} in file ${1} but it didn't appear after $TIME_OUT seconds"
      echo "ERROR: sps_profiler.sh - Waiting for matching Word ${2} in file ${1} but it didn't appear after $TIME_OUT seconds"
      break;
    fi
    RETRY=$(($RETRY+5))
    sleep 5
    FOUND=`grep "${2}" "${1}" | grep -v grep`
  done
  echo "File ${1} found"
}

# Check if file size is growing (if there is no predefined word for which we can search)
wait_until_file_is_written2() {
  FILE=${1}
  FILESIZE_1=`wc -c <"${FILE}"`
  sleep 5
  FILESIZE_2=`wc -c <"${FILE}"`
  debug "wait_until_file_is_written2: Checking size of ${FILE}"
  local RETRY=0
  debug "Checking Filesize of $FILE"
  debug "Compare $FILESIZE_2 > $FILESIZE_1"
  while [ $FILESIZE_2 != $FILESIZE_1 ]
  do
    FILESIZE_1=$FILESIZE_2
    sleep 5
    FILESIZE_2=`wc -c <"${FILE}"`
  done
}

#####   Collect results of network_traffic.sh and loadavg.sh -> NODE_ENVIRONMENT   #####
consolidate_resource_environment() {
  CPU_COUNT=`lscpu | grep -m1 "CPU(s):" | awk '{print $NF}'`
  # result of loadavg.sh
  #wait_until_file_exists ${PROJECT_HOME}/last_results/cpu_avg.txt
  #CPU_AVG=`cat ${PROJECT_HOME}/last_results/cpu_avg.txt`
  #debug "CPU_AVG = $CPU_AVG"
  #debug "cat ${PROJECT_HOME}/last_results/network_in.txt | awk '{s+=$1} END {print s}"
  # result of network_traffic.sh
 wait_until_file_exists ${PROJECT_HOME}/last_results/network_in.txt
  NETWORK_IN=`cat ${PROJECT_HOME}/last_results/network_in.txt | awk '{s+=$1} END {print s}'`

  #debug "NETWORK_IN = $NETWORK_IN"
  NETWORK_OUT=`cat ${PROJECT_HOME}/last_results/network_out.txt | awk '{s+=$1} END {print s}'`
  #NODE_ENVIRONMENT="#Cores;${CPU_COUNT};TOTAL_NETWORK_IN;${NETWORK_IN};TOTAL_NETWORK_OUT;${NETWORK_OUT}"
  NODE_ENVIRONMENT="#Cores;${CPU_COUNT};TOTAL_NETWORK_IN;${NETWORK_IN};TOTAL_NETWORK_OUT;${NETWORK_OUT}"
  #NODE_ENVIRONMENT="#Cores;${CPU_COUNT}"
 
}

#####   Collect results of perf, calls calculate-application-profile, writes everything in experiment_results.txt   #####
consolidate_cpu_measurment() {
  sleep 3
  debug "consolidate_cpu_measurment"
  echo "$ALL_PIDS" | while IFS= read -r pid
  do
    RESULT=""
    local PID_NAME=${PID_NAMES[$pid]}
    RESULT="PID=;$pid;$PID_NAME"
    #local CPU_UTIL_TOP=`tail -n 1 $PROJECT_HOME/last_results/${pid}_top.txt | awk '{print $9}'`
    local CPU_UTIL_TOP="0"
	local CPU_MS=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep cpu-clock | awk '{print $1}'`
    local CPU_UTIL=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep cpu-clock | grep -o -P '\d\.\d{3} CPUs utilized'`
    local CPU_INSTR=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep instructions | awk '{print $1}'`
    local CPU_CYCLES=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep cycles | head -n 1 | awk '{print $1}'`
    local CPU_STALLED_FRONT=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep stalled-cycles-frontend | awk '{print $1}'`
    local CPU_STALLED_BACK=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep stalled-cycles-backend | awk '{print $1}'`
    local CONTEXT_SWITCHES=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep context-switches | awk '{print $1}'`
    local CPU_MIGRATIONS=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep cpu-migrations | awk '{print $1}'`
    local CPU_PAGE_FAULTS=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep page-faults | awk '{print $1}'`
    local BRANCHES=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep branches  | head -n 1 | awk '{print $1}'`
    local BRANCH_MISSES=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep branch-misses | awk '{print $1}'`
    local PERF_TIME_ELAPSED=`cat $PROJECT_HOME/last_results/${pid}_perf_stat_result.txt | grep 'seconds time elapsed' | awk '{print $1}'`
    RESULT="${RESULT};CPU-util-top;${CPU_UTIL_TOP};CPU-clock;${CPU_MS};CPU-util-cores;${CPU_UTIL};Instructions;${CPU_INSTR};CPU-cycl;${CPU_CYCLES};CPU-stalled-frontcycl;${CPU_STALLED_FRONT};CPU-stalled-backcycl;${CPU_STALLED_BACK};Branches;${BRANCHES};Branch-misses;${BRANCH_MISSES};Context-Switches;${CONTEXT_SWITCHES};CPU-migrations;${CPU_MIGRATIONS};CPU-page-faults;${CPU_PAGE_FAULTS};Elapsed-time;${PERF_TIME_ELAPSED};"
    debug "Result for PID $pid = $RESULT"
    #check if process was profiled
    if [[ $APPL_PIDS == *"${pid}"* && $BPF_PROFILING == "TRUE" ]]; then
      debug "Calculate application profile for $pid"
      calculate_application_profile ${pid}
    else
      # To get a consistent CSV of equal length we need to fill up the missing columns for pids that were not profiled
      OPERATORS=`cat $APPLICATION_PROFILE`
      for operator in $OPERATORS
      do
        RESULT="${RESULT};;"
      done
      #For TOTAL_COUNT and WORKLOAD
      RESULT="${RESULT};;"
    fi
    echo "${NODE_ENVIRONMENT};${RESULT}NEXT" >> $PROJECT_HOME/last_results/../experiment_results.txt
  done
  echo -n "_END_OF_RESULT" >> $PROJECT_HOME/last_results/../experiment_results.txt
}

calculate_application_profile (){
  debug "calculate_application_profile"
  pid=${1}
    # Calculate total samples
    local TOTALCOUNT=`cat $PROJECT_HOME/last_results/${pid}_stacktrace_result.collapsed.txt | awk '{print $NF}' | awk '{s+=$1} END {print s}'`

    # Load perf-stat Results

    $PROJECT_HOME/profiling/scripts/reverseStackTrace.sh < $PROJECT_HOME/last_results/${pid}_stacktrace_result.collapsed.txt > $PROJECT_HOME/last_results/${pid}_stacktrace_result.reversed.txt

    declare -A OPERATOR_COUNT

    #Initialize Operators
    OPERATORS=`cat $APPLICATION_PROFILE`
    for operator in $OPERATORS
    do
      OPERATOR_COUNT[$operator]="0"
    done
    #
    wait_until_file_exists "${PROJECT_HOME}/last_results/${pid}_perf_stat_result.txt"
    wait_until_file_is_written "$PROJECT_HOME/last_results/${pid}_perf_stat_result.txt" "cpu-clock"
    # Loop through application profile
    while IFS=  read -r line
      do
      FIRST_WORD="true" #TODO isStackTraceCount
      FOUND="false"
        for word in $line
        do
          if [[ "$FIRST_WORD" == "true" ]]; then
            STACK_COUNT=$word

            STACK_COUNT="$(echo -e "${STACK_COUNT}" | tr -d '[:space:]')"
            FIRST_WORD="false"
          fi
          for operator in "${!OPERATOR_COUNT[@]}"
          do
            if [[ $word =~ $operator ]]; then
              FOUND="true"
              COUNT=${OPERATOR_COUNT[$operator]}
              COUNT=$(($COUNT+$STACK_COUNT))
              OPERATOR_COUNT[$operator]="$COUNT"
              break
            fi
          done
          if [[ "$FOUND" == "true" ]]; then
            break
          fi
        done
          if [[ "$FOUND" == "false" ]]; then
            # This stacktrace didn't contain an operation that was defined in the application profile
            # Log this stacktrace to file for manual inspection (extend application profile)
            echo $line >> $PROJECT_HOME/last_results/stacktraces_not_matched_by_profile.txt
          fi
    done < $PROJECT_HOME/last_results/${pid}_stacktrace_result.reversed.txt
    RESULT="${RESULT}Total_Count;$TOTALCOUNT;"
    for operator in "${!OPERATOR_COUNT[@]}"; do
     RESULT="${RESULT}$operator;${OPERATOR_COUNT[$operator]};"
     #SAMPLES=${OPERATOR_COUNT[$operator]}
     #OP_PERCENTAGE=$(awk -v v1=$SAMPLES -v v2=$TOTALCOUNT 'BEGIN { rounded = sprintf("%.3f", v1/v2); print rounded }')
     #RESULT="${RESULT}$operator;${SAMPLES};${OP_PERCENTAGE};"
    done
    #WORKLOAD=`cat $PROJECT_HOME/last_results/${pid}_workload_result.txt | grep -e "Executor" -e "Kafka" | grep -v grep | awk '{print $NF}'`
    #RESULT="${RESULT}Workload;$WORKLOAD;"
}
stacktrace_deep_split(){
    
    FILE=$(basename "$STACK_TRACE_FILE")
    DIRECTORY=$(dirname "$STACK_TRACE_FILE")
    PIDNR=$(echo "$FILE" | tr -dc '0-9')
    #echo "File = $FILE"
    #echo "Directory = $DIRECTORY"
    #echo "pid = $PIDNR"
    #exit
    
    mkdir -p $DIRECTORY/deep_split
    echo "[DEEP_SPLIT] Generating deep_split in directory $DIRECTORY/deep_split of stacktrace $STACK_TRACE_FILE according to $APPLICATION_PROFILE"
    
    ${PROJECT_HOME}/profiling/FlameGraph/stackcollapse-bpftrace.pl $STACK_TRACE_FILE > $DIRECTORY/deep_split/${PIDNR}_stacktrace_result.collapsed
    
    # Calculate total samples
    local TOTALCOUNT=`cat deep_split/${PIDNR}_stacktrace_result.collapsed | awk '{print $NF}' | awk '{s+=$1} END {print s}'`
    echo "[DEEP_SPLIT] Totalcount = $TOTALCOUNT"
    # Load perf-stat Results
    
    echo "[DEEP_SPLIT] $PROJECT_HOME/profiling/scripts/reverseStackTrace.sh < $DIRECTORY/deep_split/${PIDNR}_stacktrace_result.collapsed > $DIRECTORY/deep_split/${PIDNR}_stacktrace_result.reversed"
    $PROJECT_HOME/profiling/scripts/reverseStackTrace.sh < $DIRECTORY/deep_split/${PIDNR}_stacktrace_result.collapsed > $DIRECTORY/deep_split/${PIDNR}_stacktrace_result.reversed
    

    #Initialize Operators
    declare -A OPERATOR_COUNT
    OPERATORS=`cat $APPLICATION_PROFILE`
    for operator in $OPERATORS
    do
      OPERATOR_COUNT[$operator]="0"
    done
    echo "loop through application profile"
    # Loop through application profile
    while IFS=  read -r line
      do
      FIRST_WORD="true" #TODO isStackTraceCount
      FOUND="false"
        for word in $line
        do
          if [[ "$FIRST_WORD" == "true" ]]; then
            STACK_COUNT=$word
            STACK_COUNT="$(echo -e "${STACK_COUNT}" | tr -d '[:space:]')"
            FIRST_WORD="false"
          fi
          for operator in "${!OPERATOR_COUNT[@]}"
          do
            if [[ $word =~ $operator ]]; then
              FOUND="true"
              #echo "found $operator"
              #echo "COUNT=${OPERATOR_COUNT[$operator]}"
              COUNT=${OPERATOR_COUNT[$operator]}
              #echo "STACK_COUNT=$STACK_COUNT"
              #echo "COUNT=$(($COUNT+$STACK_COUNT))"
              COUNT=$(($COUNT+$STACK_COUNT))
              OPERATOR_COUNT[$operator]="$COUNT"
              #echo "writing $DIRECTORY/deep_split/$operator_${STACK_TRACE_FILE}.reversed"
              echo $line >> $DIRECTORY/deep_split/${operator}_${PIDNR}_stacktrace_result.reversed
              break
            fi
          done
          if [[ "$FOUND" == "true" ]]; then
            break
          fi
        done
          if [[ "$FOUND" == "false" ]]; then
            # This stacktrace didn't contain an operation that was defined in the application profile
            # Log this stacktrace to file for manual inspection (extend application profile)
            echo $line >> $DIRECTORY/deep_split/NOT_MATCHED_${PIDNR}_stacktrace_result.reversed
          fi
    done < $DIRECTORY/deep_split/${PIDNR}_stacktrace_result.reversed
    RESULT="Total_Count;$TOTALCOUNT;"
    for operator in "${!OPERATOR_COUNT[@]}"; do
     RESULT="${RESULT}$operator;${OPERATOR_COUNT[$operator]};"
     if [ ${OPERATOR_COUNT[$operator]} != 0 ]; then
        $PROJECT_HOME/profiling/scripts/reverseStackTrace.sh < $DIRECTORY/deep_split/${operator}_${PIDNR}_stacktrace_result.reversed > $DIRECTORY/deep_split/${operator}_${PIDNR}_stacktrace_result.collapsed
        ${PROJECT_HOME}/profiling/FlameGraph/flamegraph.pl --color=java --hash < $DIRECTORY/deep_split/${operator}_${PIDNR}_stacktrace_result.collapsed > $DIRECTORY/deep_split/${operator}_${PIDNR}_flamegraph.svg
     fi
    done
    echo $RESULT > $DIRECTORY/deep_split/${PIDNR}_result.txt
    $PROJECT_HOME/profiling/scripts/reverseStackTrace.sh < $DIRECTORY/deep_split/NOT_MATCHED_${PIDNR}_stacktrace_result.reversed > $DIRECTORY/deep_split/NOT_MATCHED_${PIDNR}_stacktrace_result.collapsed
    ${PROJECT_HOME}/profiling/FlameGraph/flamegraph.pl --color=java --hash < $DIRECTORY/deep_split/NOT_MATCHED_${PIDNR}_stacktrace_result.collapsed > $DIRECTORY/deep_split/NOT_MATCHED_${PIDNR}_flamegraph.svg
    #WORKLOAD=`cat $PROJECT_HOME/last_results/${pid}_workload_result.txt | grep -e "Executor" -e "Kafka" | grep -v grep | awk '{print $NF}'`
    #RESULT="${RESULT}Workload;$WORKLOAD;"
}
recalculate_application_profile (){
  # Get all matching directories
  DIRECTORIES=""
  if [ "$FILTER" = "" ]; then
      DIRECTORIES=$(ls $MEASURMENT_FOLDER)
  else
      DIRECTORIES=$(ls $MEASURMENT_FOLDER | grep $FILTER)
  fi
  MEASURMENTS=($DIRECTORIES)
  
  #Initialize Operators
  declare -A OPERATOR_COUNT
  OPERATORS=`cat $APPLICATION_PROFILE`
  for operator in $OPERATORS
  do
    OPERATOR_COUNT[$operator]="0"
  done
  
  # Loop through directories one by one and get all stacktraces in their
  
  for measurment in "${MEASURMENTS[@]}"
  do
      echo "recalculate stacktraces in $measurment"
      cd $MEASURMENT_FOLDER/$measurment/tmp/
      STACKTRACES=$(ls | grep _stacktrace_result.txt)
      STACKTRACE_ARRAY=($STACKTRACES) 
      
      for stacktrace in "${STACKTRACE_ARRAY[@]}"
      do
        PIDNR=$(echo "$stacktrace" | tr -dc '0-9')
        echo "collapsed stacktrace is ${PIDNR}_stacktrace_result.collapsed.txt"
        echo "reversed stacktrace is ${PIDNR}_stacktrace_result.reversed.txt"
        
        # For each stacktrace calculate the application profile
        local TOTALCOUNT=`cat ${PIDNR}_stacktrace_result.collapsed.txt | awk '{print $NF}' | awk '{s+=$1} END {print s}'`
          for operator in $OPERATORS
          do
            OPERATOR_COUNT[$operator]="0"
          done  
        while IFS=  read -r line
      do
      FIRST_WORD="true"
      FOUND="false"
        for word in $line
        do
          if [[ "$FIRST_WORD" == "true" ]]; then
            STACK_COUNT=$word

            STACK_COUNT="$(echo -e "${STACK_COUNT}" | tr -d '[:space:]')"
            FIRST_WORD="false"
          fi
          for operator in "${!OPERATOR_COUNT[@]}"
          do
            if [[ $word =~ $operator ]]; then
              FOUND="true"
              COUNT=${OPERATOR_COUNT[$operator]}
              COUNT=$(($COUNT+$STACK_COUNT))
              OPERATOR_COUNT[$operator]="$COUNT"
              break
            fi
          done
          if [[ "$FOUND" == "true" ]]; then
            break
          fi
        done
          if [[ "$FOUND" == "false" ]]; then
            # This stacktrace didn't contain an operation that was defined in the application profile
            # Log this stacktrace to file for manual inspection (extend application profile)
            echo $line >> ./RECALCULATED_stacktraces_not_matched_by_profile.txt
          fi
    done < ./${PIDNR}_stacktrace_result.reversed.txt
    RESULT="EXPERIMENT_ID;${measurment};PID;${PIDNR};Total_Count;$TOTALCOUNT"
    for operator in "${!OPERATOR_COUNT[@]}"; do
     RESULT="${RESULT};$operator;${OPERATOR_COUNT[$operator]}"
    done
    echo $RESULT >> $MEASURMENT_FOLDER/RECALCULATED_results.txt   
  done

  done

}
run() {
  OPERATION=$1
  start=`date +%s`
  debug "Starting Operation $OPERATION"

  #####   Indentify ALL_PIDS and APPL_PIDS for Spark   #####
  if [ "ANALYZE_SCOPE_SPARK" = "$OPERATION" ];
  then
    analyze_scope "spark" "org.apache.spark" ALL_PIDS
    analyze_scope "executor" "org.apache.spark.executor" APPL_PIDS
    set_pid_names
  #####   Indentify ALL_PIDS and APPL_PIDS for Flink   #####
  elif [ "ANALYZE_SCOPE_FLINK" = "$OPERATION" ];
  then
    analyze_scope "flink" "org.apache.flink" ALL_PIDS
    analyze_scope "taskexecutor" "org.apache.flink.runtime.taskexecutor" APPL_PIDS
    set_pid_names
  #####   Prepare bpf tracing scripts   #####
  elif [ "PREPARE_TRACERS" = "$OPERATION" ]; then
    prepare_tracers
  #####   Start of performance measurement, i.a. perf stat (ALL_PIDS) and workload tracing (APPL_PIDS)   #####
  elif [ "START_PERFORMANCE_MEASURMENT" = "$OPERATION" ];
  then
    # Find active network device by ensuring that these have an inet IP as well as a broadcast address (to exclude lo). Only use the first match
    NETWORK_DEVICE=$(ip addr show | awk '/inet.*brd/{print $NF; exit}')
    $PROJECT_HOME/profiling/scripts/network_traffic.sh $NETWORK_DEVICE $TIMER "$PROJECT_HOME/last_results" &
    debug "$PROJECT_HOME/profiling/scripts/network_traffic.sh $NETWORK_DEVICE $TIMER '$PROJECT_HOME/last_results' &"
    #$PROJECT_HOME/profiling/scripts/loadavg.sh $TIMER "$PROJECT_HOME/last_results" &
    #debug "$PROJECT_HOME/profiling/scripts/loadavg.sh $TIMER '$PROJECT_HOME/last_results' &"

    perf_stat
    if [ "TRUE" = "$BPF_NETWORK_TRACE" ]; then
      trace_network_workload
    fi
  #####   Stacktrace sampling (APPL_PIDS)   #####
  elif [ "START_PROFILING" = "$OPERATION" ]; then
    if [ "TRUE" = "$BPF_PROFILING" ]; then
      stacktrace_sampling
    fi
  #####   Aggregation of results   #####
  elif [ "RESULT_AGGREGATION" = "$OPERATION" ]; then
									
    consolidate_resource_environment
    if [ "TRUE" = "$BPF_PROFILING" ]; then
      flamegraph
    fi
    consolidate_cpu_measurment
	
	rm -f $PROJECT_HOME/last_results/*.reversed.txt
	rm -f $PROJECT_HOME/last_results/*.collapsed.txt
	rm -f $PROJECT_HOME/last_results/*_result.bak
	rm -f $PROJECT_HOME/last_results/*.map
    progress "FINISHED_RESULT_AGGREGATION"

  #####   Global Perf Stat   #####
  elif [ "GLOBAL_PERF_STAT" = "$OPERATION" ]; then
      perf stat -o ${PROJECT_HOME}/last_results/global_perf_stat_result.txt -a sleep $TIMER &
      $PROJECT_HOME/profiling/scripts/loadavg.sh $TIMER "$PROJECT_HOME/last_results" &

  #####   Spark Performance Measurement Profile   #####
  elif [ "PROFILE_SPARK" = "$OPERATION" ];
  then
    run "ANALYZE_SCOPE_SPARK"
    run "PREPARE_TRACERS"
    run "START_PERFORMANCE_MEASURMENT"
    run "START_PROFILING"
    sleep ${PROFILING_TIMER}
    APPLICATION_PROFILE=$APPLICATION_PROFILE_SPARK
    run "RESULT_AGGREGATION" #"$PROJECT_HOME/profiling/config/spark_application_profile.txt"
    echo "FINISHED SPARK PROFILING"
  #####   Spark CP Performance Measurement Profile   #####
  elif [ "PROFILE_SPARK_CP" = "$OPERATION" ];
  then
    run "ANALYZE_SCOPE_SPARK"
    run "PREPARE_TRACERS"
    run "START_PERFORMANCE_MEASURMENT"
    run "START_PROFILING"
    sleep ${PROFILING_TIMER}
    APPLICATION_PROFILE=$APPLICATION_PROFILE_SPARK_CP
    run "RESULT_AGGREGATION" #"$PROJECT_HOME/profiling/config/spark_application_profile.txt"
    echo "FINISHED SPARK PROFILING"
  #####   Flink Performance Measurement Profile   #####
  elif [ "PROFILE_FLINK" = "$OPERATION" ];
  then
    run "ANALYZE_SCOPE_FLINK"
    run "PREPARE_TRACERS"
    run "START_PERFORMANCE_MEASURMENT" #STARTS PMC COLLECTION
    run "START_PROFILING" #ONLY STARTS PROFILING IF BPF_TRACE=TRUE
    sleep ${PROFILING_TIMER}
    APPLICATION_PROFILE=$APPLICATION_PROFILE_FLINK
    run "RESULT_AGGREGATION" #"$PROJECT_HOME/profiling/config/flink_application_profile.txt"
  elif [ "STACKTRACE_DEEP_SPLIT" = "$OPERATION" ]; then
    #./sps_profiler.sh -o STACKTRACE_DEEP_SPLIT -s 148003_stacktrace_result.txt -a /root/YSB/sps_cpu_bench_internal/profiling/config/flink_application_profile.txt
    if [ "$STACK_TRACE_FILE" = "" ]; then
      echo "Please provide a stacktrace via the -s option"
      echo "The file need to be placed into the same directory"
    elif [ "$APPLICATION_PROFILE" = "" ]; then
      echo "Please provide an application profile via the -a option"
      echo "Example $PROJECT_HOME/profiling/config/flink_application_profile.txt"
    else
      stacktrace_deep_split
    fi
  elif [ "RECALCULATE_APPLICATION_PROFILE" = "$OPERATION" ]; then
    #./sps_profiler.sh -o STACKTRACE_DEEP_SPLIT -s 148003_stacktrace_result.txt -a /root/YSB/sps_cpu_bench_internal/profiling/config/flink_application_profile.txt
    if [ "$MEASURMENT_FOLDER" = "" ]; then
      echo "Please provide the directory of your measurments via -m / --measurment option"
      echo "You may ad an additional filter via --filter if you only want to calculate the application profile for dedicated experiments"
    elif [ "$APPLICATION_PROFILE" = "" ]; then
      echo "Please provide an application profile via the -a option"
      echo "Example $PROJECT_HOME/profiling/config/flink_application_profile.txt"
    else
      recalculate_application_profile
    fi    
  else
    if [ "HELP" != "$OPERATION" ];
    then
      echo "UNKOWN OPERATION '$OPERATION'"
      echo
    fi
    echo "Supported operations:"
    echo
    echo "Helper: operations:"
    echo "ANALYZE_SCOPE_SPARK: Indentify all interesting PIDs for Spark"
    echo "ANALYZE_SCOPE_FLINK: Indentify all interesting PIDs for Flink"
    echo "PREPARE_TRACERS: Prepare bpf tracing scripts"
    echo "START_PERFORMANCE_MEASURMENT: Start of performance measurement"
    echo "START_PROFILING: Stacktrace sampling"
    echo "RESULT_AGGREGATION: Aggregation of results"
    echo
    echo "Main operations:"
    echo "PROFILE_SPARK: Spark Performance Measurement Profile"
    echo "PROFILE_FLINK: Flink Performance Measurement Profile"
    echo
    echo "HELP: print out this message"
    echo
    exit 1
  fi
  end=`date +%s`
  runtime=$((end-start))
  debug "The Operation $OPERATION took $runtime seconds"
}
#########################################
# MAIN METHOD
#########################################
while [ "$1" != "" ]; do
  case $1 in
      	-o| --operation )               shift
                                        OPERATION=${1}
                                        ;;
        -f| --frequency )               shift
                                        HERTZ=${1}
                                        ;;
        -b| --bpfprofiling )            shift
                                        BPF_PROFILING=${1}
                                        ;;
        -w| --waittime )                shift
                                        WAIT_TIME=${1}
                                        debug "$WAIT_TIME"
                                        ;;
        -p| --project )                 shift
                                        PROJECT_HOME=${1}
                                        ;;
        -d| --duration )                shift
                                        TIMER=${1}
                                        ;;
        -a| --appprofile )                shift
                                        APPLICATION_PROFILE=${1}
                                        ;;
        -s| --stacktracefile )          shift
                                        STACK_TRACE_FILE=${1}
                                        ;;
        -m| --measurment     )          shift
                                        MEASURMENT_FOLDER=${1}
                                        ;;   
        -filt| --filter     )          shift
                                        FILTER=${1}
                                        ;;                                                                             
        -h| --help )                    HELP="true"
        ;;
    esac
    shift
done
if [ "$OPERATION" == "" ]; then
  OPERATION="HELP"
fi
# Required to launch bpftrace
export PATH=$PATH:/snap/bin/

# ToDo Buffer of 120s to write the stacktraces. If Payload is stopped beforehand the stacktraces wont be written!!!
# However, this is highly error-prone if 120s is sufficient for long benchmark runs
# You can optionally specify that the profiling starts at a later point in time
# Since there will be a small delay until the profiling starts we will add -1 second
PROFILING_TIMER=$((TIMER-WAIT_TIME-1))
debug "Profiling Timer = $PROFILING_TIMER, WAIT_TIME = $WAIT_TIME"
if [ "$PROJECT_HOME/last_results" == "" ]; then
  TIMESTAMP=$(date +%Y%m%d_%k%M%S)
  PROJECT_HOME/last_results="$(echo -e "${TIMESTAMP}" | tr -d '[:space:]')"
fi
cd $PROJECT_HOME/profiling/scripts
run "${OPERATION}"
