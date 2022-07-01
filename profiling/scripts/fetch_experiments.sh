#!/bin/bash
CLUSTER_FILEPATH=${1}
PROJECT_HOME=${2}

fetch_experiment_results(){
 TARGET=$1
 COMMAND=$2
 shift 
 scp $TARGET:${PROJECT_HOME}/last_results/experiment_results.txt ${PROJECT_HOME}/last_results/${TARGET}_experiment_results.txt
}

# Ensure that on all Hosts, the experiment_results.txt file is ready
CLUSTER=`cat $CLUSTER_FILEPATH`
while IFS= read -r node
do
        
  HOST=`echo $node | awk '{print $1}'`
  ROLE=`echo $node | awk '{print $2}'`
  echo "ROLE=$ROLE on HOST=$HOST"
  if [[ $ROLE == *"MASTER"* || $ROLE == *"SLAVE"* ]]; then
    ssh $HOST "${PROJECT_HOME}/profiling/scripts/check_file_readiness.sh ${PROJECT_HOME}/last_results/experiment_results.txt END_OF_RESULT"
  fi
done <<< "$CLUSTER" 

CLUSTER=""

# Copy consolidate all experiments.txt files
CLUSTER=`cat $CLUSTER_FILEPATH`
while IFS= read -r node
do
        
  HOST=`echo $node | awk '{print $1}'`
  ROLE=`echo $node | awk '{print $2}'`
  echo "ROLE=$ROLE on HOST=$HOST"
  if [[ $ROLE == *"MASTER"* || $ROLE == *"SLAVE"* ]]; then
    fetch_experiment_results $HOST "GET_NODE_RESULTS"
  fi
done <<< "$CLUSTER" 
