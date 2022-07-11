#################################################
# User defined variables
#################################################
PROJECT_HOME=/YSB-task-level
DOWNLOAD_DIRECTORY=$PROJECT_HOME/downloads

# Make sure these version are available for download
# e.g. REDIS_VERSION="6.0.10" translates to wget https://download.redis.io/releases/redis-6.0.10.tar.gz
KAFKA_VERSION="3.0.0"
KAFKA_SCALA_VERSION="2.12"
REDIS_VERSION="6.0.10"
FLINK_VERSION="1.14.3"
FLINK_SCALA_VERSION="2.12"

SPARK_VERSION="3.2.0"
SPARK_HADOOP_VERSION="2.7"

#################################################
# Internal variables -> Do not change!
#################################################
CLUSTER_FILEPATH="$PROJECT_HOME/conf/cluster.txt"
SLAVE_LIST="$PROJECT_HOME/conf/slaves.txt"
HOSTS_FILEPATH="$PROJECT_HOME/conf/hosts.txt"
ENABLEDCONF_FILEPATH="$PROJECT_HOME/conf/enabled"
TEMPLATECONF_FILEPATH="$PROJECT_HOME/conf/template"
KafkaPath="$PROJECT_HOME/kafka_$KAFKA_SCALA_VERSION-$KAFKA_VERSION"
RedisPath="$PROJECT_HOME/redis-6.0.10"
FlinkPath="$PROJECT_HOME/flink-$FLINK_VERSION"
SparkPath="spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}"
ProfilerPath="$PROJECT_HOME/profiling/scripts/sps_profiler.sh"

FlinkMaster="${ENABLEDCONF_FILEPATH}/flink/masters"
FlinkWorkers="${ENABLEDCONF_FILEPATH}/flink/workers"
FlinkConf="${ENABLEDCONF_FILEPATH}/flink/flink-conf.yaml"
FlinkProfile="${ENABLEDCONF_FILEPATH}/profile/flink_application_profile.txt"
SparkSlaves="${ENABLEDCONF_FILEPATH}/spark/slaves"
SparkConf="${ENABLEDCONF_FILEPATH}/spark/spark-defaults.conf"
SparkEnv="${ENABLEDCONF_FILEPATH}/spark/spark-env.sh"
SparkProfile="${ENABLEDCONF_FILEPATH}/profile/spark_application_profile.txt"
SparkCPProfile="${ENABLEDCONF_FILEPATH}/profile/spark_cp_application_profile.txt"
ClusterConf="${ENABLEDCONF_FILEPATH}/cluster/clusterConf.yaml"
LoadGen="${ENABLEDCONF_FILEPATH}/load/core.clj"
KafkaConf="${ENABLEDCONF_FILEPATH}/kafka/server.properties"
KafkaDeleteConf="${ENABLEDCONF_FILEPATH}/kafka/delete-ad-events.config"
RedisConf="${ENABLEDCONF_FILEPATH}/redis/redis.conf"

FlinkMasterDefault="${TEMPLATECONF_FILEPATH}/flink/flink-master-default"
FlinkWorkersDefault="${TEMPLATECONF_FILEPATH}/flink/flink-workers-default"
FlinkConfDefault="${TEMPLATECONF_FILEPATH}/flink/flink-conf-default.yaml"
FlinkProfileDefault="${TEMPLATECONF_FILEPATH}/profile/flink_application_profile.txt"
SparkSlavesDefault="${TEMPLATECONF_FILEPATH}/spark/spark-slaves-default"
SparkConfDefault="${TEMPLATECONF_FILEPATH}/spark/spark-defaults.conf"
SparkEnvDefault="${TEMPLATECONF_FILEPATH}/spark/spark-env-default.sh"
SparkProfileDefault="${TEMPLATECONF_FILEPATH}/profile/spark_application_profile.txt"
SparkCPProfileDefault="${TEMPLATECONF_FILEPATH}/profile/spark_cp_application_profile.txt"
ClusterConfDefault="${TEMPLATECONF_FILEPATH}/cluster/clusterConf-default.yaml"
LoadGenDefault="${TEMPLATECONF_FILEPATH}/load/core-default.clj"
KafkaConfDefault="${TEMPLATECONF_FILEPATH}/kafka/server-default.properties"
KafkaDeleteConfDefault="${TEMPLATECONF_FILEPATH}/kafka/delete-ad-events-default.config"
RedisConfDefault="${TEMPLATECONF_FILEPATH}/redis/redis-default.conf"


CORES=1
EXECUTORS=1
TASK_SLOTS=1
NODES=1
SMT=1
MEMORY=8192
declare -A HOST_ROLES
declare -A KAFKA_HOSTS
declare -a SLAVES
LOADING_REQ="true"

textReplace(){
  SEARCH=$1
  REPLACE=$2
  FILE=$3
  sed -i --follow-symlinks "s/^${SEARCH}.*/${REPLACE}/g" $FILE
}

createDefaultConfigs(){
    rm -f $FlinkMasterDefault
    rm -f $FlinkWorkersDefault
    rm -f $FlinkConfDefault
	rm -f $FlinkProfile
    rm -f $SparkSlavesDefault
    rm -f $SparkConfDefault
    rm -f $SparkEnvDefault
	rm -f $SparkProfile
	rm -f $SparkCPProfile
    rm -f $ClusterConfDefault
    rm -f $KafkaConfDefault
    rm -f $RedisConfDefault

    # Replace versions in stream-bench2.sh
    sed -i "s/^KAFKA_VERSION=.*/KAFKA_VERSION=\"${KAFKA_VERSION}\"/g" $PROJECT_HOME/stream-bench2.sh
    sed -i "s/^KAFKA_SCALA_VERSION=.*/KAFKA_SCALA_VERSION=\"${KAFKA_SCALA_VERSION}\"/g" $PROJECT_HOME/stream-bench2.sh
    sed -i "s/^SPARK_VERSION=.*/SPARK_VERSION=\"${SPARK_VERSION}\"/g" $PROJECT_HOME/stream-bench2.sh
    sed -i "s/^SPARK_HADOOP_VERSION=.*/SPARK_HADOOP_VERSION=\"${SPARK_HADOOP_VERSION}\"/g" $PROJECT_HOME/stream-bench2.sh
    sed -i "s/^REDIS_VERSION=.*/REDIS_VERSION=\"${REDIS_VERSION}\"/g" $PROJECT_HOME/stream-bench2.sh
    sed -i "s/^FLINK_VERSION=.*/FLINK_VERSION=\"${FLINK_VERSION}\"/g" $PROJECT_HOME/stream-bench2.sh
    sed -i "s/^FLINK_SCALA_VERSION=.*/FLINK_SCALA_VERSION=\"${FLINK_SCALA_VERSION}\"/g" $PROJECT_HOME/stream-bench2.sh
    # Escape all '/' in PROJECT_HOME, otherwise sed can not process it
    PROJECT_HOME2=$(echo $PROJECT_HOME | sed 's_/_\\/_g')
    sed -i "s/^PROJECT_HOME=.*/PROJECT_HOME=${PROJECT_HOME2}/g" $PROJECT_HOME/stream-bench2.sh
    sed -i "s/^PROJECT_HOME=.*/PROJECT_HOME=${PROJECT_HOME2}/g" $PROJECT_HOME/profiling/scripts/sps_profiler.sh


    ##########
    #Create Default Configuration Files
    ##########
	echo "spark.executor.extraJavaOptions=-XX:-TieredCompilation -XX:CompileThreshold=1 -XX:+PreserveFramePointer" >> $SparkConfDefault
	echo "spark.driver.memory 16g" >> $SparkConfDefault
    echo "spark.executor.memory 8g" >> $SparkConfDefault
    echo "spark.executor.cores 8" >> $SparkConfDefault
    echo "spark.driver.cores 16" >> $SparkConfDefault
    echo "spark.default.parallelism 16" >> $SparkConfDefault
    echo "spark.task.cpus 8" >> $SparkConfDefault
    echo "spark.eventLog.enabled  false " >> $SparkConfDefault

    echo "env.java.opts: \"-XX:CompileThreshold=1 -XX:-TieredCompilation -XX:+PreserveFramePointer\"" >> $FlinkConfDefault
	echo "jobmanager.rpc.port: 6123" >> $FlinkConfDefault
    echo "jobmanager.memory.process.size: 1600m" >> $FlinkConfDefault
    echo "taskmanager.memory.process.size: 4096m" >> $FlinkConfDefault
    echo "taskmanager.numberOfTaskSlots: 8" >> $FlinkConfDefault
    echo "parallelism.default: 16" >> $FlinkConfDefault
    echo "jobmanager.execution.failover-strategy: region" >> $FlinkConfDefault

    # Create Kafka Conf File
    echo "delete.topic.enable=true"  >> $KafkaConfDefault
    echo "cleanup.policy=delete"  >> $KafkaConfDefault
    echo "broker.id=0"  >> $KafkaConfDefault
    echo "num.network.threads=16"  >> $KafkaConfDefault
    echo "num.io.threads=16"  >> $KafkaConfDefault
    echo "num.partitions=16"  >> $KafkaConfDefault
    echo "socket.send.buffer.bytes=2147483647"  >> $KafkaConfDefault
    echo "socket.receive.buffer.bytes=2147483647"  >> $KafkaConfDefault
    echo "socket.request.max.bytes=104857600"  >> $KafkaConfDefault
    echo "log.dirs=/tmp/kafka-logs"  >> $KafkaConfDefault
    echo "num.recovery.threads.per.data.dir=1"  >> $KafkaConfDefault
    echo "offsets.topic.replication.factor=1"  >> $KafkaConfDefault
    #echo "transaction.state.log.replication.factor=1"  >> $KafkaConfDefault
    #echo "transaction.state.log.min.isr=1"  >> $KafkaConfDefault
    #echo "log.flush.interval.ms=900000"  >> $KafkaConfDefault
    echo "log.retention.ms=300000"  >> $KafkaConfDefault
    #echo "queued.max.requests=999999"  >> $KafkaConfDefault
    #echo "log.retention.check.interval.ms=600000"  >> $KafkaConfDefault
    echo "zookeeper.connect=localhost:2181"  >> $KafkaConfDefault
    echo "zookeeper.connection.timeout.ms=6000"  >> $KafkaConfDefault
    echo "log.segment.bytes=1073741824"  >> $KafkaConfDefault
    #echo "group.initial.rebalance.delay.ms=0"  >> $KafkaConfDefault
    #echo "delete.topic.enable=true"  >> $KafkaConfDefault

    # Create Redis Default Conf
    echo "protected-mode no"  >> $RedisConfDefault
    echo "port 6379"  >> $RedisConfDefault
    echo "tcp-backlog 511"  >> $RedisConfDefault
    echo "timeout 0"  >> $RedisConfDefault
    echo "tcp-keepalive 300"  >> $RedisConfDefault
    echo "daemonize no"  >> $RedisConfDefault
    echo "supervised no"  >> $RedisConfDefault
    echo "pidfile /var/run/redis_6379.pid"  >> $RedisConfDefault
    # Loglevel: warning, notice, verbose, debug
    echo "loglevel notice"  >> $RedisConfDefault
    echo "logfile \"$PROJECT_HOME/log \""  >> $RedisConfDefault
    echo "always-show-logo no"  >> $RedisConfDefault
    echo "#Saving disabled"  >> $RedisConfDefault
    echo "#save 3600 200000"  >> $RedisConfDefault
    echo "stop-writes-on-bgsave-error no"  >> $RedisConfDefault
    echo "rdbcompression yes"  >> $RedisConfDefault
    echo "rdbchecksum no"  >> $RedisConfDefault
    echo "dbfilename dump.rdb"  >> $RedisConfDefault
    echo "dbfilename dump.rdb"  >> $RedisConfDefault
    echo "rdb-del-sync-files no"  >> $RedisConfDefault
    echo "dir ./"  >> $RedisConfDefault
    echo "replica-serve-stale-data yes"  >> $RedisConfDefault
    echo "replica-read-only yes"  >> $RedisConfDefault
    echo "repl-diskless-sync no"  >> $RedisConfDefault
    echo "repl-diskless-sync-delay 5"  >> $RedisConfDefault
    echo "repl-diskless-load disabled"  >> $RedisConfDefault
    echo "repl-disable-tcp-nodelay no"  >> $RedisConfDefault
    echo "replica-priority 100"  >> $RedisConfDefault
    echo "lazyfree-lazy-eviction no"  >> $RedisConfDefault
    echo "lazyfree-lazy-expire no"  >> $RedisConfDefault
    echo "lazyfree-lazy-server-del no"  >> $RedisConfDefault
    echo "replica-lazy-flush no"  >> $RedisConfDefault
    echo "lazyfree-lazy-user-del no"  >> $RedisConfDefault
    echo "io-threads 4"  >> $RedisConfDefault
    echo "oom-score-adj no"  >> $RedisConfDefault
    echo "appendonly no"  >> $RedisConfDefault
    echo "appendfilename \"appendonly.aof\""  >> $RedisConfDefault
    echo "appendfsync everysec"  >> $RedisConfDefault
    echo "no-appendfsync-on-rewrite no"  >> $RedisConfDefault
    echo "auto-aof-rewrite-percentage 100"  >> $RedisConfDefault
    echo "auto-aof-rewrite-min-size 64mb"  >> $RedisConfDefault
    echo "aof-load-truncated yes"  >> $RedisConfDefault
    echo "aof-use-rdb-preamble yes"  >> $RedisConfDefault
    echo "lua-time-limit 5000"  >> $RedisConfDefault
    echo "slowlog-log-slower-than 10000"  >> $RedisConfDefault
    echo "slowlog-max-len 128"  >> $RedisConfDefault
    # Latency Monitor
    echo "latency-monitor-threshold 0"  >> $RedisConfDefault
    echo "notify-keyspace-events \"\""  >> $RedisConfDefault
    echo "hash-max-ziplist-entries 512"  >> $RedisConfDefault
    echo "hash-max-ziplist-value 64"  >> $RedisConfDefault
    echo "list-max-ziplist-size -2"  >> $RedisConfDefault
    echo "list-compress-depth 0"  >> $RedisConfDefault
    echo "set-max-intset-entries 512"  >> $RedisConfDefault
    echo "zset-max-ziplist-entries 128"  >> $RedisConfDefault
    echo "zset-max-ziplist-value 64"  >> $RedisConfDefault
    echo "hll-sparse-max-bytes 3000"  >> $RedisConfDefault
    echo "stream-node-max-bytes 4096"  >> $RedisConfDefault
    echo "stream-node-max-entries 100"  >> $RedisConfDefault

    echo "activerehashing no"  >> $RedisConfDefault
    echo "# If unsure: use activerehashing=no if you have hard latency requirements and it is not a good thing in your environment that Redis can reply from time to time to queries with 2 milliseconds delay."  >> $RedisConfDefault
    echo "client-output-buffer-limit normal 0 0 0"  >> $RedisConfDefault
    echo "client-output-buffer-limit replica 256mb 64mb 60"  >> $RedisConfDefault
    echo "client-output-buffer-limit pubsub 32mb 8mb 60"  >> $RedisConfDefault
    echo "hz 10"  >> $RedisConfDefault
    echo "dynamic-hz yes"  >> $RedisConfDefault
    echo "aof-rewrite-incremental-fsync yes"  >> $RedisConfDefault
    echo "rdb-save-incremental-fsync yes"  >> $RedisConfDefault
    echo "jemalloc-bg-thread yes"  >> $RedisConfDefault


    readHostRoles

    for HOST in "${!HOST_ROLES[@]}"; do
      ROLE=${HOST_ROLES[$HOST]}
      if [[ $ROLE == *"MASTER"* ]]; then
        echo "$HOST:8081" >> $FlinkMasterDefault
        echo "jobmanager.rpc.address: $HOST" >> $FlinkConfDefault
        echo "export SPARK_MASTER_HOST='$HOST'" >> $SparkEnvDefault
        echo $HOST > $FlinkMasterDefault
      fi
      if [[ $ROLE == *"SLAVE"* ]]; then
        echo "$HOST" >> $FlinkWorkersDefault
        echo "$HOST" >> $SparkSlavesDefault
      fi
      if [[ $ROLE == *"KAFKA"* ]]; then
        echo "kafka.brokers:" >> $ClusterConfDefault
        echo "    - \"$HOST\""  >> $ClusterConfDefault
        echo "" >> $ClusterConfDefault
        echo "zookeeper.servers:" >> $ClusterConfDefault
        echo "    - \"$HOST\""  >> $ClusterConfDefault
        echo ""  >> $ClusterConfDefault
      fi
      if [[ $ROLE == *"REDIS"* ]]; then
        echo "redis.host: $HOST" >> $ClusterConfDefault
      fi
    done
    # Create Cluster Conf File
    echo "kafka.port: 9092"  >> $ClusterConfDefault
    echo "zookeeper.port: 2181"  >> $ClusterConfDefault
    echo "process.hosts: 2"  >> $ClusterConfDefault
    echo "process.cores: 8"  >> $ClusterConfDefault
    echo "process.parallelism: 16"  >> $ClusterConfDefault
    echo "kafka.partitions: 16"  >> $ClusterConfDefault
    echo "kafka.topic: \"ad-events\""  >> $ClusterConfDefault
    echo "spark.batchtime: 500"  >> $ClusterConfDefault
    echo ""  >> $ClusterConfDefault
    # copy default load clojure program
    cp $PROJECT_HOME/data/src/setup/core.clj $LoadGenDefault


    ##########
    # Enable default configuration
    ##########

    rm -f $FlinkMaster
    rm -f $FlinkWorkers
    rm -f $FlinkConf
	rm -f $FlinkProfile
    rm -f $SparkSlaves
    rm -f $SparkConf
    rm -f $SparkEnv
	rm -f $SparkProfile
	rm -f $SparkCPProfile
    rm -f $ClusterConf
    rm -f $LoadGen
    rm -f $KafkaConf
    rm -f $RedisConf

    ln -s $FlinkMasterDefault $FlinkMaster
    ln -s $FlinkWorkersDefault $FlinkWorkers
    ln -s $FlinkConfDefault $FlinkConf
	ln -s $FlinkProfileDefault $FlinkProfile
    ln -s $SparkSlavesDefault $SparkSlaves
    ln -s $SparkConfDefault $SparkConf
    ln -s $SparkEnvDefault $SparkEnv
	ln -s $SparkProfileDefault $SparkProfile
	ln -s $SparkCPProfileDefault $SparkCPProfile
    ln -s $ClusterConfDefault $ClusterConf
    ln -s $LoadGenDefault $LoadGen
    ln -s $KafkaConfDefault $KafkaConf
    ln -s $RedisConfDefault $RedisConf
}

# Copy config files to cluster machines
deployConfigs(){
    readHostRoles		
	for HOST in "${!HOST_ROLES[@]}"; do
      ROLE=${HOST_ROLES[$HOST]}
      if [[ $ROLE == *"ZK"* ]]; then
        textReplace "zookeeper.connect=" "zookeeper.connect=${HOST}:2181" $KafkaConf
      fi
    done
	BROKER=0
	counter=0
	len=${#KAFKA_HOSTS[@]}
    for HOST in "${!HOST_ROLES[@]}"; do
      ROLE=${HOST_ROLES[$HOST]}
      #ssh -n $HOST "mkdir -p $PROJECT_HOME/conf"
      #ssh -n $HOST "mkdir -p $PROJECT_HOME/utils"
      scp $PROJECT_HOME/stream-bench2.sh $HOST:$PROJECT_HOME/ &
      scp $PROJECT_HOME/conf/cluster.txt $HOST:$PROJECT_HOME/conf/ &
      scp -r $ClusterConf $HOST:$PROJECT_HOME/conf/ &
      if [[ $ROLE == *"MASTER"* || $ROLE == *"SLAVE"* ]]; then
        ssh -n $HOST "cd $PROJECT_HOME/flink-${FLINK_VERSION}/conf/; rm -f masters; rm -f workers; rm -f flink-conf.yaml;"
        ssh -n $HOST "cd $PROJECT_HOME/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}/conf/; rm -f slaves; rm -f spark-env.sh; rm -f spark-defaults.conf;"
        scp $ProfilerPath $HOST:$PROJECT_HOME/profiling/scripts/ &
        scp $FlinkMaster $HOST:$PROJECT_HOME/flink-${FLINK_VERSION}/conf/ &
        scp $FlinkWorkers $HOST:$PROJECT_HOME/flink-${FLINK_VERSION}/conf/ &
        scp $FlinkConf $HOST:$PROJECT_HOME/flink-${FLINK_VERSION}/conf/ &      
        scp $SparkSlaves $HOST:$PROJECT_HOME/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}/conf/slaves &
        scp $SparkConf $HOST:$PROJECT_HOME/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}/conf/spark-defaults.conf &
        scp $SparkEnv $HOST:$PROJECT_HOME/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}/conf/spark-env.sh &
      fi
      if [[ $ROLE == *"REDIS"* ]]; then
        scp $RedisConf $HOST:$RedisPath/ &
      fi
	  if [[ $ROLE == *"SLAVE"* ]]; then
        scp $PROJECT_HOME/conf/enabled/profile/flink_application_profile.txt $HOST:$PROJECT_HOME/profiling/config/flink_application_profile.txt &
		scp $PROJECT_HOME/conf/enabled/profile/spark_application_profile.txt $HOST:$PROJECT_HOME/profiling/config/spark_application_profile.txt &
		scp $PROJECT_HOME/conf/enabled/profile/spark_cp_application_profile.txt $HOST:$PROJECT_HOME/profiling/config/spark_cp_application_profile.txt &	
      fi
      if [[ $ROLE == *"KAFKA"* ]]; then
		echo "Assigning $HOST -> Broker ${BROKER}"
		cp $KafkaConf ${KafkaConf}_${HOST}
		textReplace "broker.id=" "broker.id=${BROKER}" ${KafkaConf}_${HOST}
		BROKER=$((BROKER+1))
        scp $KafkaDeleteConf $HOST:$PROJECT_HOME/utils/ &
        ssh -n $HOST "rm -f $PROJECT_HOME/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}/config/server.properties"
        scp ${KafkaConf}_${HOST} $HOST:$PROJECT_HOME/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}/config/server.properties &
      fi
      if [[ $ROLE == *"LOAD"* ]]; then
	   KAFKA_BROKER=${KAFKA_HOSTS[$counter]}
	   counter=$((counter+1))
	   counter=$((counter%len))
	   sed -n '$!N;s@kafka.brokers:\n    - "c06lp1"@kafka.brokers:\n    - "'"${KAFKA_BROKER}"'"@;P;D' $ClusterConf > ${ClusterConf}_${HOST}
       ssh -n $HOST "rm -f $PROJECT_HOME/data/src/setup/core.clj"
       scp $LoadGen $HOST:$PROJECT_HOME/data/src/setup/
       scp $ClusterConf $HOST:$PROJECT_HOME/conf/ &
      fi
    done
}

deployFile(){
    readHostRoles
    FILE=${1}
    TARGET_PATH=${2}
    for HOST in "${!HOST_ROLES[@]}"; do
        if [[ $TARGET_PATH == "" ]]; then
          scp $FILE $HOST:$PROJECT_HOME/
        else
          ssh -n $HOST "mkdir -p $TARGET_PATH"
          scp $FILE $HOST:$TARGET_PATH/
        fi
    done
}

deployFrameworks(){
  #Deploy frameworks on cluster
  readHostRoles
  cd $PROJECT_HOME
   for HOST in "${!HOST_ROLES[@]}"; do
        ROLE=${HOST_ROLES[$HOST]}
        ssh -n $HOST "mkdir -p $PROJECT_HOME"

        if [[ $ROLE == *"MASTER"* ]]; then
          if [[ $(ssh -n $HOST "cd $PROJECT_HOME; ls | grep -c flink-${FLINK_VERSION}") == 0 ]]; then
            scp $DOWNLOAD_DIRECTORY/flink-${FLINK_VERSION}-bin-scala_${FLINK_SCALA_VERSION}.tgz $HOST:$PROJECT_HOME/
            ssh -n $HOST "cd $PROJECT_HOME; tar -xzvf flink-${FLINK_VERSION}-bin-scala_${FLINK_SCALA_VERSION}.tgz; rm flink-${FLINK_VERSION}-bin-scala_${FLINK_SCALA_VERSION}.tgz;"
          fi
          if [[ $(ssh -n $HOST "cd $PROJECT_HOME; ls | grep -c spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}") == 0 ]]; then
            scp $DOWNLOAD_DIRECTORY/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz $HOST:$PROJECT_HOME/
            ssh -n $HOST "cd $PROJECT_HOME; tar -xzvf spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz; rm spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz"
          fi
          scp -r ./streaming-benchmark-common/ $HOST:$PROJECT_HOME
          scp -r ./flink-benchmarks/ $HOST:$PROJECT_HOME
          scp -r ./spark-benchmarks/ $HOST:$PROJECT_HOME

        # In case our node is MASTER_SLAVE -> only the the first "if" clause will be considered
        elif [[ $ROLE == *"SLAVE"* ]]; then
          if [[ $(ssh -n $HOST "cd $PROJECT_HOME; ls | grep -c flink-${FLINK_VERSION}") == 0 ]]; then
            scp $DOWNLOAD_DIRECTORY/flink-${FLINK_VERSION}-bin-scala_${FLINK_SCALA_VERSION}.tgz $HOST:$PROJECT_HOME/
            ssh -n $HOST "cd $PROJECT_HOME; tar -xzvf flink-${FLINK_VERSION}-bin-scala_${FLINK_SCALA_VERSION}.tgz; rm flink-${FLINK_VERSION}-bin-scala_${FLINK_SCALA_VERSION}.tgz;"
          fi
          if [[ $(ssh -n $HOST "cd $PROJECT_HOME; ls | grep -c spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}") == 0 ]]; then
            scp $DOWNLOAD_DIRECTORY/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz $HOST:$PROJECT_HOME/
            ssh -n $HOST "cd $PROJECT_HOME; tar -xzvf spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz; rm spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz"
          fi
        fi

        if [[ $ROLE == *"REDIS"* ]]; then
          if [[ $(ssh -n $HOST "cd $PROJECT_HOME; ls | grep -c redis-${REDIS_VERSION}") == 0 ]]; then
            scp $DOWNLOAD_DIRECTORY/redis-${REDIS_VERSION}.tar.gz $HOST:$PROJECT_HOME/
            ssh -n $HOST "cd $PROJECT_HOME; tar -xzvf redis-${REDIS_VERSION}.tar.gz; rm redis-${REDIS_VERSION}.tar.gz"
            #ssh -n $HOST "source /etc/profile; cd $PROJECT_HOME/redis-${REDIS_VERSION}; make"
            #echo "Redis build completed"
            ssh -n $HOST "ln -s $PROJECT_HOME/redis-${REDIS_VERSION}/src/redis-cli /usr/bin/redis-cli"
            scp -r $PROJECT_HOME/utils $HOST:$PROJECT_HOME/
			echo "[DEPLOY] please compile Redis manually on host $HOST !!!"
			echo "[DEPLOY] cd $PROJECT_HOME/redis-${REDIS_VERSION}; make"   
          fi
        fi

        if [[ $ROLE == *"KAFKA"* ]]; then
          if [[ $(ssh -n $HOST "cd $PROJECT_HOME; ls | grep -c kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}") == 0 ]]; then
            scp $PROJECT_HOME/downloads/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz $HOST:$PROJECT_HOME/
            ssh -n $HOST "cd $PROJECT_HOME; tar -xzvf kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz; rm kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz"
          fi
        fi

        if [[ $ROLE == *"LOAD"* ]]; then
          if [[ $(ssh -n $HOST "cd $PROJECT_HOME; ls | grep -c data") == 0 ]]; then
            scp -r data $HOST:$PROJECT_HOME/
          fi
        fi
      done
}


downloadFrameworks(){
  mkdir -p $DOWNLOAD_DIRECTORY && cd $DOWNLOAD_DIRECTORY

  #Download Frameworks
  wget -N https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz
  wget -N https://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz
  wget -N https://archive.apache.org/dist/flink/flink-${FLINK_VERSION}/flink-${FLINK_VERSION}-bin-scala_${FLINK_SCALA_VERSION}.tgz
  wget -N https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz

  #Check Downloads
  if [ -f "kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz" ]; then
      echo "[INFO] kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz available."
  else
      echo "[ERROR] kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz couldn't be downloaded"
  fi
  if [ -f "redis-${REDIS_VERSION}.tar.gz" ]; then
      echo "[INFO] redis-${REDIS_VERSION}.tar.gz available."
  else
      echo "[ERROR] redis-${REDIS_VERSION}.tar.gz couldn't be downloaded"
  fi
  if [ -f "flink-${FLINK_VERSION}-bin-scala_${FLINK_SCALA_VERSION}.tgz" ]; then
      echo "[INFO] flink-${FLINK_VERSION}-bin-scala_${FLINK_SCALA_VERSION}.tgz available."
  else
      echo "[ERROR] flink-${FLINK_VERSION}-bin-scala_${FLINK_SCALA_VERSION}.tgz couldn't be downloaded"
  fi
  if [ -f "spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz" ]; then
      echo "[INFO] spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz available."
  else
      echo "[ERROR] spark-${SPARK_VERSION}-bin-hadoop${SPARK_HADOOP_VERSION}.tgz couldn't be downloaded"
  fi
}



initializeProject(){
  #Deploy the initial project structure including BPF, perf scripts, java mapping agent, ...
  readHostRoles
  cd $PROJECT_HOME/spark-benchmarks/target/
  zip -F spark-cp-jar.zip --out spark-cp-jar-merged.zip
  zip -F spark-structured-jar.zip --out spark-structured-jar-merged.zip
  unzip spark-cp-jar-merged.zip
  unzip spark-structured-jar-merged.zip
  sleep 2
  rm spark-cp-jar-merged.zip
  rm spark-structured-jar-merged.zip
  cd $PROJECT_HOME
  
  for HOST in "${!HOST_ROLES[@]}"; do
    ROLE=${HOST_ROLES[$HOST]}
    echo "[INFO] initialize Host $HOST with Role $ROLE"
          ssh -n $HOST "mkdir -p $PROJECT_HOME/conf"
          ssh -n $HOST "mkdir -p $PROJECT_HOME/profiling"
          echo "[INFO] Copy stream-bench2.sh and clusterConf.yaml"
          scp ./stream-bench2.sh $HOST:$PROJECT_HOME/
          scp -r ./conf/clusterConf.yaml $HOST:$PROJECT_HOME/conf/
		  scp -r ./profiling/scripts $HOST:$PROJECT_HOME/profiling/
    if [[ $ROLE == *"MASTER"* || $ROLE == *"SLAVE"* ]]; then
        echo "[INFO] Copy profiling folder and setup java"
        scp -r ./profiling/config $HOST:$PROJECT_HOME/profiling/
        USER=$(whoami)
        PLATFORM=""
        if [ $USER == "root" ]; then
          ssh -n $HOST "apt-get install -y openjdk-8-jdk openjdk-8-dbg zip git;"
         # Determine JAVA_HOME on target Host
          JAVA_BIN_PATH=$(ssh -n $HOST "readlink -f $(which java)")
          JAVA_PATH_FRAGMENTS=$(echo $JAVA_BIN_PATH | tr "/" "\n")
          TARGET_JAVA_HOME=""
          FOLDER_TO_GREP=""
          for FRAGMENT in $JAVA_PATH_FRAGMENTS
          do
            TARGET_JAVA_HOME="$TARGET_JAVA_HOME/$FRAGMENT"
             if [[ $FRAGMENT == *"jdk"* ]]; then
              FOLDER_TO_GREP=$FRAGMENT
                break;
             fi
          done
         if [[ $(ssh -n $HOST "cd /usr/lib/jvm; ls | grep -c $FOLDER_TO_GREP ;") == 1 ]]; then
            ssh -n $HOST "echo 'export JAVA_HOME=$TARGET_JAVA_HOME' >> ~/.bashrc; source ~/.bashrc;"
          elif [[ $(ssh -n $HOST "cd /usr/lib/jvm; ls | grep -c java-8-openjdk-ppc64el ;") == 1 ]]; then
            ssh -n $HOST "echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-ppc64el/' >> ~/.bashrc; source ~/.bashrc;"
            PLATFORM="ppc64el"
          elif [[ $(ssh -n $HOST "cd /usr/lib/jvm; ls | grep -c java-8-openjdk-amd64 ;") == 1 ]]; then
            ssh -n $HOST "echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/' >> ~/.bashrc; source ~/.bashrc;"
            PLATFORM="amd"
          else
            echo "Pls set JAVA_HOME manually. Could not find java installation path."
          fi
          echo "[INFO] Installing bpftrace and setup perf-map-agent and FlameGraph"
          ssh -n $HOST "apt-get install -y linux-tools-common linux-tools-$KernelVersion;"
          #ssh -n $HOST "snap -S install --devmode bpftrace; snap connect bpftrace:system-trace;"
          ssh -n $HOST "apt install -y cmake;"
          ssh -n $HOST "apt-get install -y build-essential;"
          ssh -n $HOST "cd $PROJECT_HOME/profiling ; git clone https://github.com/jvm-profiling-tools/perf-map-agent.git;"
          #ssh -n $HOST "cd $PROJECT_HOME/profiling/perf-map-agent; ${PLATFORM}/; cmake .; make ;"
          ssh -n $HOST "cd $PROJECT_HOME/profiling/; git clone https://github.com/brendangregg/FlameGraph.git"
        else
          echo "[INFO] Copy profiling folder and setup java"
          echo "In order to download the various utilities such as jdk, bpftrace, cmake, ... you need to provide your sudoers password"
          IFS= read -rsp 'Please enter the password for Host $HOST of your user $USER: ' PASSWORD
          ssh -n $HOST "echo $PASSWORD | sudo -S apt-get install -y openjdk-8-jdk openjdk-8-dbg zip git;"
          ssh -n $HOST "apt-get install -y openjdk-8-jdk openjdk-8-dbg zip git;"
          if [[ $(ssh -n $HOST "cd /usr/lib/jvm; ls | grep -c java-8-openjdk-ppc64el ;") == 1 ]]; then
            ssh -n $HOST "echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-ppc64el/' >> ~/.bashrc; source ~/.bashrc;"
            PLATFORM="ppc64el"
          elif [[ $(ssh -n $HOST "cd /usr/lib/jvm; ls | grep -c java-8-openjdk-amd64 ;") == 1 ]]; then
            ssh -n $HOST "echo 'export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/' >> ~/.bashrc; source ~/.bashrc;"
            PLATFORM="amd"
          else
            echo "Pls set JAVA_HOME manually. Could not find java installation path."
          fi
          echo "[INFO] Installing bpftrace and setup perf-map-agent and FlameGraph"
          ssh -n $HOST "echo $PASSWORD | sudo -S apt-get install -y linux-tools-common linux-tools-$KernelVersion;"
          #ssh -n $HOST "echo $PASSWORD | sudo snap -S install --devmode bpftrace; echo $PASSWORD | sudo -S snap connect bpftrace:system-trace;"
          ssh -n $HOST "echo $PASSWORD | sudo -S apt install -y cmake;"
          ssh -n $HOST "echo $PASSWORD | sudo -S apt-get install -y build-essential;"
          ssh -n $HOST "cd $PROJECT_HOME/profiling ; git clone https://github.com/jvm-profiling-tools/perf-map-agent.git;"
          #ssh -n $HOST "cd $PROJECT_HOME/profiling/perf-map-agent; export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-${PLATFORM}/; cmake .; make ;"
          ssh -n $HOST "echo $PASSWORD | cd $PROJECT_HOME/profiling/; git clone https://github.com/brendangregg/FlameGraph.git"
          # Hardcode JAVA_HOME in perf-map-agent.sh
          #ssh -n $HOST "sed -i '1iJAVA_HOME=$TARGET_JAVA_HOME' $PROJECT_HOME/profiling/perf-map-agent/bin/create-java-perf-map.sh"
        fi


    fi
    if [[ $ROLE == *"LOAD"* ]]; then
      USER=$(whoami)
      echo "[INFO] Copy clojure load generator and install Leiningen"
      if [[ $USER == "root" ]]; then
        ssh -n $HOST "apt install -y leiningen;"
      else
        echo "In order to download the various utilities such as jdk, bpftrace, cmake, ... you need to provide your sudoers password"
        IFS= read -rsp 'Please enter the password for Host $HOST of your user $USER: ' PASSWORD
        ssh -n $HOST "echo $PASSWORD | sudo -S apt install -y leiningen;"
      fi

    fi

  done
}


keyExchange(){
prepareHostsFile
# Check if sshpass is installed
echo "Setting up passwordless access to clusternodes:"
cat $HOSTS_FILEPATH
echo ""
  SSHPASS_FLAG=`which sshpass`
  if [ "$SSHPASS_FLAG" == "" ]; then
    echo "###################################"
    echo "#             SSHPASS             #"
    echo "###################################"
    echo "The keyexchange requires sshpass to be installed on this system (not on the remote hosts)"
    echo "Please install sshpass:"
    echo "  -Debian/Ubuntu: apt-get install sshpass"
    echo "  -SUSE/SLES: zypper install sshpass"
    echo "  -CentOS/RHEL: yum install sshpass"
    echo "  -Fedora: dnf install sshpass "
    echo ""
    echo "Exiting"
    exit
  fi

# Check if private and public key exists in ~/.ssh/ -> generate a keypair if not
if ! [[ -f ~/.ssh/id_rsa && -f ~/.ssh/id_rsa.pub ]]; then
    echo "The key-pair ~/.ssh/id_rsa.pub and ~/.ssh/id_rsa does not exist"
    echo "generating a new keypair"
    ssh-keygen -q -t rsa -N '' <<< $'\ny' >/dev/null 2>&1
fi

# Get credentials for initial SSH login
  unset -v password # make sure it's not exported
  set +o allexport  # make sure variables are not automatically exported
  echo "Please enter the credentials to be used for initial login (identical login for all nodes required)"
  IFS= read -rp 'Please enter your SSH user : ' USER
  IFS= read -rsp 'Please enter your SSH password: ' PW

# Exchange Keys
  while read -r line
  do
    concat="$USER"@"$line"
    	echo "$concat"

    	sshpass -p $PW ssh-copy-id -f -o StrictHostKeyChecking=no -i ~/.ssh/id_rsa.pub $concat
    	case $? in
    		0)
    			echo Key\ successfully\ added\ to\ $line
    			;;
    		1)
                            ;;
    		2)
                            ;;
    		3)
                            echo General\ runtime\ error\ for\ $line
                            ;;
    		4)
                            ;;
    		5)
                            echo Invalid\ password\ for\ $line
                            ;;
    		6)
                            ;;
      esac
      # Add Hosts to known_hosts file in order to prevent the warning prompt upon first connection attempt
      ssh-keyscan -H $line >> ~/.ssh/known_hosts
	  scp ~/.ssh/id_rsa $line:~/.ssh/id_rsa
	  
  done < <(grep . "${HOSTS_FILEPATH}")
  
# Known Hosts
  while read -r line
  do
     scp ~/.ssh/known_hosts $line:~/.ssh/known_hosts
	 
  done < <(grep . "${HOSTS_FILEPATH}")

}


# Deploy Priv Key on Master Node (required if MASTER is not on this host)
deployPrivKey(){
    readHostRoles
    cd $PROJECT_HOME
    for HOST in "${!HOST_ROLES[@]}"; do
      ROLE=${HOST_ROLES[$HOST]}

      if [[ $ROLE == *"MASTER"* || $ROLE == *"SLAVE"* ]]; then
        scp ~/.ssh/id_rsa $HOST:~/.ssh/
            # Nested loop to add all other slave/master nodes to the known_hosts list
            for NODE in "${!HOST_ROLES[@]}"; do
              NODEROLE=${HOST_ROLES[$NODE]}

              if [[ $NODEROLE == *"MASTER"* || $ROLE == *"SLAVE"* ]]; then
                ssh -n $HOST "ssh-keyscan -H $NODE >> ~/.ssh/known_hosts"
              fi
            done
      fi
    done

}


printHostRoles(){
  readHostRoles
  for host in "${!HOST_ROLES[@]}"; do
    echo "Host: ${host} Role: ${HOST_ROLES[$host]}"
    ROLE=${HOST_ROLES[$host]}
    if [[ $ROLE == *"MASTER"* ]]; then
              echo "Welcome MASTER!!!"
    elif [[ $ROLE == *"SLAVE"* ]]; then
              echo "Just another SLAVE"
    fi


  done
}
prepareHostsFile(){
  # Creates the hosts.txt file which contains a list of all cluster nodes based on the cluster.txt
  # This file is only required to serve as input for the keyExchange()
> $HOSTS_FILEPATH
> "${HOSTS_FILEPATH}.tmp"

  while read -r line
  do
    local HOST=`echo $line | awk '{print $1}'`
    echo $HOST >> "${HOSTS_FILEPATH}.tmp"
  done < <(grep . "${CLUSTER_FILEPATH}")
  #}< $CLUSTER_FILEPATH

  #remove duplicate lines
  awk '!seen[$0]++' "${HOSTS_FILEPATH}.tmp" > $HOSTS_FILEPATH
  rm "${HOSTS_FILEPATH}.tmp"
}



setSlaves(){
  sed -i '/SLAVE/d' $CLUSTER_FILEPATH
  ACTIVE_SLAVES=0

  while IFS= read -r node || [ -n "$node" ];
  do
    echo "$node SLAVE" >> $CLUSTER_FILEPATH
    ACTIVE_SLAVES=$((ACTIVE_SLAVES+1))
    SLAVES+=($node)
    if (( ACTIVE_SLAVES == NODES )); then
      break
    fi
  done < $SLAVE_LIST


}

readHostRoles(){
  {
    if $LOADING_REQ; then
      LOADING_REQ="false"
	  counter=0
      while IFS= read -r line || [ -n "$line" ];
      do
        local HOST=`echo $line | awk '{print $1}'`
        local ROLE=`echo $line | awk '{print $2}'`
        HOST_ROLES[$HOST]="$ROLE"
		if [[ $ROLE == *"KAFKA"* ]]; then
			KAFKA_HOSTS[$counter]="$HOST"
			counter=$((counter+1))			
		fi
      done
  fi
  } < $CLUSTER_FILEPATH
}
setParallelism()
  {
        while [ "$1" != "" ]; do
            case $1 in
              	 -c| --cores )                  shift
                                                CORES=${1}
                                                ;;
              	 -e| --executors )              shift
                                                EXECUTORS=${1}
                                                ;;
              	 -n| --nodes )                  shift
                                                NODES=${1}
                                                ;;
              	 -s| --smt )                    shift
                                                SMT=${1}
                                                ;;
              	 -m| --memory )                 shift
                                                MEMORY=${1}
                                                ;;												
                 -h| --help )                  HELP="true"
                                                ;;
            esac
            shift
        done

        if [ "$SMT" == "" ] || [ "$CORES" == "" ] || [ "$NODES" == "" ] || [ "$HELP" == "true" ]; then
          echo "Usage: deploy.sh setParallelism -c <NumberOfCores> -n <NumberOfNodes> -s <SMT Level>"
          echo "Example: deploy.sh setParallelism -c 2 -e 2 -n 2 -s 8"
          echo "2x slaves that use SMT-8 with 2 cores each. We will operate 2x executors on each node -> 4x"
          exit
        fi
        parallelism=$((CORES * NODES * SMT)) # 4 
        parallelismPerNode=$((CORES * SMT)) #1
        numberOfTaskSlots=$((parallelismPerNode / EXECUTORS))
		processHosts=$((NODES))
        if [ $numberOfTaskSlots = 0 ]; then
          numberOfTaskSlots=1;
          if [ $EXECUTORS -gt 1 ]; then
			processHosts=$((NODES * EXECUTORS))
          #  parallelism=$EXECUTORS
          fi
        fi
        executorCores=$((CORES * SMT / EXECUTORS))

        # Set active worker nodes in cluster.txt according to $NODES
        setSlaves

        


        # clusterConf.yaml
		MEMORY_GB=$((MEMORY/1024))
		
        textReplace "process.hosts:" "process.hosts: $processHosts" $ClusterConf
        textReplace "process.cores:" "process.cores: $parallelismPerNode" $ClusterConf
        textReplace "process.parallelism:" "process.parallelism: $parallelism" $ClusterConf
        textReplace "kafka.partitions:" "kafka.partitions: $parallelism" $ClusterConf

        #Configure Spark
        #echo "spark.deploy.defaultCores" >> $SparkConfDefault #Alway use all available cores -> default behaviour
        textReplace "spark.executor.memory " "spark.executor.memory ${MEMORY_GB}g" $SparkConf
        textReplace "spark.default.parallelism" "spark.default.parallelism $parallelism" $SparkConf
        #textReplace "spark.executor.cores" "spark.executor.cores $EXECUTORS" $SparkConf
        textReplace "spark.executor.cores" "spark.executor.cores $executorCores" $SparkConf
        textReplace "spark.task.cpus" "spark.task.cpus 1" $SparkConf


        #Configure Flink
        # flink-conf.yaml
		textReplace "taskmanager.memory.process.size: " "taskmanager.memory.process.size: ${MEMORY}m" $FlinkConf
        textReplace "parallelism.default:" "parallelism.default: $parallelism" $FlinkConf
        textReplace "taskmanager.numberOfTaskSlots:" "taskmanager.numberOfTaskSlots: $numberOfTaskSlots" $FlinkConf
		
          > $FlinkWorkers
          > $SparkSlaves
          for slave in "${SLAVES[@]}"
          do
            counter=0
            while (( counter < EXECUTORS))
            do
               echo $slave >> $FlinkWorkers
               echo $slave >> $SparkSlaves
               counter=$((counter+1))
            done
          done
        #Configure Kafka
        textReplace "num.partitions" "num.partitions=$parallelism" $KafkaConf
		threads=$((parallelism*2))
		textReplace "num.network.threads=" "num.network.threads=$threads" $KafkaConf
		textReplace "num.io.threads=" "num.io.threads=$parallelism" $KafkaConf
        echo "{
                \"partitions\": [" > $KafkaDeleteConf

        counter=1
        while (( counter < parallelism ))
        do
          partition=$((counter-1))
          echo "    {
                      \"topic\": \"ad-events\",
                      \"partition\": $partition,
                      \"offset\": -1
                    },"  >> $KafkaDeleteConf
          counter=$((counter+1))
        done
        partition=$((counter-1))
        echo "    {
                      \"topic\": \"ad-events\",
                      \"partition\": $partition,
                      \"offset\": -1
                    }"  >> $KafkaDeleteConf
        echo "  ],
            \"version\": 1
}" >> $KafkaDeleteConf




        deployConfigs
		
		sleep 15 



        #textReplace "" "" $LoadGen
        #echo "spark.task.cpus 1" >> $SparkConfDefault
}

setParameter(){
          #TODO
          if [ "$1" == "" ] || [ "$2" == "" ]; then
            echo "Usage: setParameter <Parameter> <ConfFile>"
            echo "Example: setParameter 'spark.driver.memory 8g' 'flink/flink-conf.yaml"
            exit
          fi
}

setSMTLevel(){

          echo "Setting SMT Level to: $SMT"
          readHostRoles
           for HOST in "${!HOST_ROLES[@]}"; do
                ROLE=${HOST_ROLES[$HOST]}
                if [[ $ROLE == *"SLAVE"* ]]; then
                    echo "Connecting to $HOST"
					ssh -n $HOST "echo 0 > /proc/sys/kernel/perf_cpu_time_max_percent"
					if [ $SMT != 0 ] ;then ssh -n $HOST "ppc64_cpu --smt=$SMT" ;fi
                fi
           done
}

helpFunction(){
  echo "
    USAGE:
    deploy.sh <function>

    <function>:
      - keyExchange           (0. Exchange SSH Keys to enable passwordless access to worker nodes - requires sshpass)
      - initializeProject     (1. Initialize the project structure and performance tools on all worker nodes. This will configure java and bpftrace on all worker nodes)
      - downloadFrameworks    (2. Download redis, kafka, flink, spark, etc. locally on this node)
      - deployFrameworks      (3. Deploy frameworks on the respective nodes)
      - createDefaultConfigs  (4. (Re-)Generates a set of default config settings and links them as enabled)
      - deployConfigs         (5. Deploy all enabled config settings in PROJECT_HOME/conf/enabled/ )

      - setParallelism        (6. Set parallelization level. All configs will be updated and deployed such as number of workers
                                  and kafka partitions: deploy.sh setParallelism -c <NumberOfCores> -n <NumberOfNodes> -s <SMT Level>
                                  Please note that the number of cores/executors/SMT need to reflect a single node.
                                  E.g. if you have 2 nodes with 1 CPU each you would specify -c 1)

      - testInstallation      (Test the installation)
      - helpFunction          (Prints this help screen)
      - setSMTLevel INT       (Set SMT level on all slaves to INT)
  "
}

if [[ $1 = "" ]];
then
  helpFunction
else
  $@
fi