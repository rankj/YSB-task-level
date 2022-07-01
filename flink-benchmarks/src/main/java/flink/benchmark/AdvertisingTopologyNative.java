/**
 * Copyright 2015, Yahoo Inc.
 * Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.
 */
package flink.benchmark;

import benchmark.common.advertising.RedisAdCampaignCache;
import benchmark.common.advertising.CampaignProcessorCommon;
import benchmark.common.Utils;
import org.apache.flink.api.common.functions.*;
import org.apache.flink.api.java.tuple.Tuple2;
import org.apache.flink.api.java.tuple.Tuple3;
import org.apache.flink.api.java.tuple.Tuple4;
import org.apache.flink.api.java.tuple.Tuple5;
import org.apache.flink.api.java.tuple.Tuple7;
import org.apache.flink.api.java.utils.ParameterTool;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.CheckpointingMode;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.connectors.kafka.FlinkKafkaConsumer;
import org.apache.flink.streaming.util.serialization.SimpleStringSchema;
import org.apache.flink.util.Collector;
import org.apache.flink.streaming.api.windowing.assigners.TumblingEventTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.api.common.functions.AggregateFunction;
import org.apache.flink.api.common.functions.RichFlatMapFunction;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.eventtime.SerializableTimestampAssigner;
import java.time.Duration;
import org.json.JSONObject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import redis.clients.jedis.Jedis;
import java.util.UUID;

import java.util.*;

/**
 * To Run:  flink run target/flink-benchmarks-0.1.0-AdvertisingTopologyNative.jar  --confPath "../conf/benchmarkConf.yaml"
 */
public class AdvertisingTopologyNative {

    private static final Logger LOG = LoggerFactory.getLogger(AdvertisingTopologyNative.class);


    public static void main(final String[] args) throws Exception {

        ParameterTool parameterTool = ParameterTool.fromArgs(args);

        Map conf = Utils.findAndReadConfigFile(parameterTool.getRequired("confPath"), true);
        int kafkaPartitions = ((Number)conf.get("kafka.partitions")).intValue();
        int hosts = ((Number)conf.get("process.hosts")).intValue();
        int cores = ((Number)conf.get("process.cores")).intValue();

        ParameterTool flinkBenchmarkParams = ParameterTool.fromMap(getFlinkConfs(conf));

        LOG.info("conf: {}", conf);
        LOG.info("Parameters used: {}", flinkBenchmarkParams.toMap());

        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.getConfig().setGlobalJobParameters(flinkBenchmarkParams);

		// Set the buffer timeout (default 100)
        // Lowering the timeout will lead to lower latencies, but will eventually reduce throughput.
        env.setBufferTimeout(flinkBenchmarkParams.getLong("flink.buffer-timeout", 100));

        if(flinkBenchmarkParams.has("flink.checkpoint-interval")) {
            // enable checkpointing for fault tolerance
            env.enableCheckpointing(flinkBenchmarkParams.getLong("flink.checkpoint-interval", 1000));
        }
        // set default parallelism for all operators (recommended value: number of available worker CPU cores in the cluster (hosts * cores))
        env.setParallelism(hosts*cores);

        DataStream<String> messageStream = env
                .addSource(new FlinkKafkaConsumer<>(
                        flinkBenchmarkParams.getRequired("topic"),
                        new SimpleStringSchema(),
                        flinkBenchmarkParams.getProperties()));

        messageStream
                .rebalance()
                // Parse the String as JSON
                .flatMap(new DeserializeBolt())

                //Filter the records if event type is "view"
                .filter(new EventFilterBolt())

                // project the event
                .<Tuple2<String, String>>project(2, 5)

                // perform join with redis data
                .flatMap(new RedisJoinBolt())

                // set pre-window timestamp
                .map(new EnrichBolt())

                // process campaign
                .assignTimestampsAndWatermarks(
                    WatermarkStrategy.<Tuple4<String,String,String,Long>>forMonotonousTimestamps().withTimestampAssigner(new MyTimeStampAssigner())
                )
                .keyBy(0)
                .window(TumblingEventTimeWindows.of(Time.seconds(10)))
                .aggregate(new MyAggregateFunction())
                .flatMap(new RedisSinkBolt());

        env.execute();
    }
    public static class EnrichBolt implements
            MapFunction<Tuple3<String,String,String>, Tuple4<String, String, String, Long>> {

        @Override
        public Tuple4<String, String, String, Long> map(Tuple3<String,String,String> input)
                throws Exception {
            return new Tuple4<String,String,String,Long>(
                input.getField(0),
                input.getField(1),
                input.getField(2),
                System.currentTimeMillis()-Long.parseLong(input.getField(2))
            );
        }
    }

    public static class MyTimeStampAssigner implements SerializableTimestampAssigner<Tuple4<String,String,String,Long>>{
        static long NO_TIMESTAMP=0L;

        @Override
        public long extractTimestamp(Tuple4<String,String,String,Long> input,long recordTimestamp){
            return Long.parseLong((String)input.getField(2),10);
        }
    }

    public static class RedisSinkBolt extends RichFlatMapFunction<Tuple5<String,String,String,String,String>, String> {
        
        Jedis jedis;

        @Override
        public void open(Configuration parameters) {
            //initialize jedis
            ParameterTool parameterTool = (ParameterTool) getRuntimeContext().getExecutionConfig().getGlobalJobParameters();
            parameterTool.getRequired("jedis_server");
            LOG.info("Opening connection with Jedis to {}", parameterTool.getRequired("jedis_server"));
            jedis = new Jedis(parameterTool.getRequired("jedis_server"), 6379);
        }

        @Override
        public void flatMap(Tuple5<String,String,String,String,String> var, Collector<String> out)
            throws Exception {

            String windowUUID = UUID.randomUUID().toString();
            jedis.hset((String)var.getField(0),(String)var.getField(3), windowUUID);
            
            String windowListUUID = jedis.hmget((String)var.getField(0), "windows").get(0);
            if (windowListUUID == null) {
                windowListUUID = UUID.randomUUID().toString();
                jedis.hset((String)var.getField(0), "windows", windowListUUID);
            }
            jedis.lpush(windowListUUID, (String)var.getField(3));

            jedis.hset(windowUUID,"seen_count",(String)var.getField(1));
            jedis.hset(windowUUID,"avg_pre_window_latency",(String)var.getField(2));
            jedis.hset(windowUUID,"last_event_time",(String)var.getField(4));
            jedis.hset(windowUUID, "time_updated",Long.toString(System.currentTimeMillis()));
            jedis.lpush("time_updated", Long.toString(System.currentTimeMillis()));
        }
    }

    private static class MyAggregateFunction
        implements AggregateFunction<Tuple4<String,String,String,Long>, Tuple5<String,Integer,Long,Long,Long>, Tuple5<String,String,String,String,String>> {
        @Override
        public Tuple5<String,Integer,Long,Long,Long> createAccumulator() {
            return new Tuple5<String,Integer,Long,Long,Long>("",0,0L,0L,0L);
        }

        @Override
        public Tuple5<String,Integer,Long,Long,Long> add(Tuple4<String,String,String,Long> input, Tuple5<String,Integer,Long,Long,Long> acc) {
            acc.setField((Integer)acc.getField(1)+1,1);
            if(((Long)acc.getField(2)).compareTo(0L)==0){
                acc.setField(input.getField(3),2);
            }else{
                acc.setField((((Long)acc.getField(2)*(new Long(((Integer)acc.getField(1)-1)))) + (Long)input.getField(3))/(new Long((Integer)acc.getField(1))),2);
            }
            if(acc.getField(0).equals("")){
                acc.setField(input.getField(0),0);
                Long time_divisor = 10000L;
                acc.setField((Long.parseLong(input.getField(2))/time_divisor)*time_divisor,3);
            }
            if((Long.valueOf(input.getField(2))).compareTo((Long)acc.getField(4))>0){
                acc.setField(Long.parseLong(input.getField(2)),4);
            }
            return acc;
        }

        @Override
        public Tuple5<String,String,String,String,String> getResult(Tuple5<String,Integer,Long,Long,Long> input) {
            return new Tuple5<String,String,String,String,String> (
                input.getField(0),
                input.getField(1).toString(),
                Long.toString((Long)input.getField(2)),
                Long.toString((Long)input.getField(3)),
                Long.toString((Long)input.getField(4))
            );
        }

        @Override
        public Tuple5<String,Integer,Long,Long,Long> merge(Tuple5<String,Integer,Long,Long,Long> a, Tuple5<String,Integer,Long,Long,Long> b) {
            if((((String)a.getField(0)).compareTo(((String)b.getField(0))))==0 && ((Long.toString((Long)a.getField(3))).compareTo(Long.toString((Long)b.getField(3))))==0){
                Long lastevent;
                if(((Long)a.getField(4)).compareTo(((Long)b.getField(4)))<=0){
                    lastevent=((Long)b.getField(4));
                }else{
                    lastevent=((Long)a.getField(4));
                }
                return new Tuple5<String,Integer,Long,Long,Long> (
                    a.getField(0),
                    (Integer)a.getField(1)+(Integer)b.getField(1),
                    (((Long)a.getField(2)*(new Long((Integer)a.getField(1))))+((Long)b.getField(2)*(new Long((Integer)b.getField(1)))))/((new Long((Integer)a.getField(1)))+(new Long((Integer)b.getField(1)))),
                    (Long)a.getField(3),
                    lastevent
                );
            }else{
                return a;
            }
        }
    }

    public static class DeserializeBolt implements
            FlatMapFunction<String, Tuple7<String, String, String, String, String, String, String>> {

        @Override
        public void flatMap(String input, Collector<Tuple7<String, String, String, String, String, String, String>> out)
                throws Exception {
            JSONObject obj = new JSONObject(input);
            Tuple7<String, String, String, String, String, String, String> tuple =
                    new Tuple7<String, String, String, String, String, String, String>(
                            obj.getString("user_id"),
                            obj.getString("page_id"),
                            obj.getString("ad_id"),
                            obj.getString("ad_type"),
                            obj.getString("event_type"),
                            obj.getString("event_time"),
                            obj.getString("ip_address"));
            out.collect(tuple);
        }
    }

    public static class EventFilterBolt implements
            FilterFunction<Tuple7<String, String, String, String, String, String, String>> {
        @Override
        public boolean filter(Tuple7<String, String, String, String, String, String, String> tuple) throws Exception {
            return tuple.getField(4).equals("view");
        }
    }

    public static final class RedisJoinBolt extends RichFlatMapFunction<Tuple2<String, String>, Tuple3<String, String, String>> {

        RedisAdCampaignCache redisAdCampaignCache;

        @Override
        public void open(Configuration parameters) {
            //initialize jedis
            ParameterTool parameterTool = (ParameterTool) getRuntimeContext().getExecutionConfig().getGlobalJobParameters();
            parameterTool.getRequired("jedis_server");
            LOG.info("Opening connection with Jedis to {}", parameterTool.getRequired("jedis_server"));
            this.redisAdCampaignCache = new RedisAdCampaignCache(parameterTool.getRequired("jedis_server"));
            this.redisAdCampaignCache.prepare();
        }

        @Override
        public void flatMap(Tuple2<String, String> input,
                            Collector<Tuple3<String, String, String>> out) throws Exception {
            String ad_id = input.getField(0);
            String campaign_id = this.redisAdCampaignCache.execute(ad_id);
            if(campaign_id == null) {
                return;
            }

            Tuple3<String, String, String> tuple = new Tuple3<String, String, String>(
                    campaign_id,
                    (String) input.getField(0),
                    (String) input.getField(1));
            out.collect(tuple);
        }
    }

    private static Map<String, String> getFlinkConfs(Map conf) {
        String kafkaBrokers = getKafkaBrokers(conf);
        String zookeeperServers = getZookeeperServers(conf);

        Map<String, String> flinkConfs = new HashMap<String, String>();
        flinkConfs.put("topic", getKafkaTopic(conf));
        flinkConfs.put("bootstrap.servers", kafkaBrokers);
        flinkConfs.put("zookeeper.connect", zookeeperServers);
        flinkConfs.put("jedis_server", getRedisHost(conf));
        flinkConfs.put("group.id", "myGroup");

        return flinkConfs;
    }

    private static String getZookeeperServers(Map conf) {
        if(!conf.containsKey("zookeeper.servers")) {
            throw new IllegalArgumentException("Not zookeeper servers found!");
        }
        return listOfStringToString((List<String>) conf.get("zookeeper.servers"), String.valueOf(conf.get("zookeeper.port")));
    }

    private static String getKafkaBrokers(Map conf) {
        if(!conf.containsKey("kafka.brokers")) {
            throw new IllegalArgumentException("No kafka brokers found!");
        }
        if(!conf.containsKey("kafka.port")) {
            throw new IllegalArgumentException("No kafka port found!");
        }
        return listOfStringToString((List<String>) conf.get("kafka.brokers"), String.valueOf(conf.get("kafka.port")));
    }

    private static String getKafkaTopic(Map conf) {
        if(!conf.containsKey("kafka.topic")) {
            throw new IllegalArgumentException("No kafka topic found!");
        }
        return (String)conf.get("kafka.topic");
    }

    private static String getRedisHost(Map conf) {
        if(!conf.containsKey("redis.host")) {
            throw new IllegalArgumentException("No redis host found!");
        }
        return (String)conf.get("redis.host");
    }

    public static String listOfStringToString(List<String> list, String port) {
        String val = "";
        for(int i=0; i<list.size(); i++) {
            val += list.get(i) + ":" + port;
            if(i < list.size()-1) {
                val += ",";
            }
        }
        return val;
    }
}
