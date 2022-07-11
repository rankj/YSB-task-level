/**
 * Copyright 2015, Yahoo Inc.
 * Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.
 */
package spark.benchmark;

import java.io.Serializable;
//import benchmark.common.advertising.CampaignProcessorCommon;
import benchmark.common.advertising.RedisAdCampaignCacheSpark;
import redis.clients.jedis.Jedis;
import redis.clients.jedis.JedisPooled;
import benchmark.common.Utils;
import benchmark.common.advertising.RedisAdCampaignCache;
import org.apache.spark.api.java.JavaSparkContext;
import org.apache.spark.SparkConf;
import org.apache.spark.broadcast.Broadcast;
import org.apache.spark.sql.functions;
import org.apache.spark.sql.SparkSession;
import org.apache.spark.sql.Dataset;
import org.apache.spark.sql.Row;
import org.apache.spark.sql.streaming.Trigger;
import org.apache.spark.sql.Encoders;
import org.apache.spark.api.java.function.FlatMapFunction;
import org.apache.spark.sql.streaming.StreamingQuery;
import org.json.JSONObject;
import org.apache.spark.api.java.function.MapFunction;
import org.apache.spark.sql.ForeachWriter;
import java.util.UUID;
import java.time.Duration;
import java.util.*;
import org.apache.spark.sql.types.TimestampType;
import java.sql.Timestamp;
import java.io.EOFException;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.URL;
import org.yaml.snakeyaml.Yaml;
import org.yaml.snakeyaml.constructor.SafeConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class SparkCPImplementierung {
    //private static Broadcast<String> jedis_server;
    //private static JedisPool pool = null;
    private static final Logger LOG = LoggerFactory.getLogger(SparkCPImplementierung.class);
    public static void main(final String[] args) throws Exception {
        Map conf = Utils.findAndReadConfigFile(args[0], true);
        int kafkaPartitions = ((Number)conf.get("kafka.partitions")).intValue();
        int hosts = ((Number)conf.get("process.hosts")).intValue();
        int cores = ((Number)conf.get("process.cores")).intValue();
        RedisAdCampaignCacheSpark redisAdCampaignCache = new RedisAdCampaignCacheSpark("131.159.8.103",6379);
        HashMap<String, String> redisCache=redisAdCampaignCache.prepare();
        Map<String, String> sparkConfig = getSparkConfs(conf);
        SparkSession spark = SparkSession
            .builder()
            .appName("JavaAdvertisingTopology")
            .getOrCreate();
        JavaSparkContext sc=new JavaSparkContext(spark.sparkContext());
        Broadcast<HashMap<String, String>>broadcastedRedisCache=sc.broadcast(redisCache);
        Dataset<Row> messages = spark
            .readStream()
            .format("kafka")
            .option("kafka.bootstrap.servers", "131.159.8.103:9092")
            .option("subscribe", "ad-events")
            //.option("kafka.bootstrap.servers", sparkConfig.get("bootstrap.servers"))
            //.option("subscribe", sparkConfig.get("topic"))
            .load();
        Dataset<String> kafkaData = messages.selectExpr("CAST(value AS STRING)").as(Encoders.STRING());
        Dataset<AdsEvent> dataDeserialized=kafkaData.map(new DeserializeClass(),Encoders.bean(AdsEvent.class)).filter("event_type = 'view'");
        Dataset<ProjectedEvent> dataProjected=dataDeserialized.map(new ProjectionClass(), Encoders.bean(ProjectedEvent.class));
        Dataset<JoinedEvent> dataJoined=dataProjected.map(new MapFunction<ProjectedEvent,JoinedEvent>(){
            public JoinedEvent call(ProjectedEvent event){
                return queryRedis(event,broadcastedRedisCache);
            }
            },Encoders.bean(JoinedEvent.class));
        Dataset<CalculatedEvent> dataEnriched=dataJoined.map(new EnrichClass(), Encoders.bean(CalculatedEvent.class));
        Dataset<Row>dataWindowed=dataEnriched.groupBy(
            functions.window(functions.to_timestamp(functions.col("timestamp_eventtime")), "10 seconds"),functions.col("campaign_id"))
            .agg(
                functions.max(functions.col("event_time")).as("max_event_time"),
                functions.count(functions.col("event_time")).as("count"),
                functions.mean(functions.col("pre_window_time")).as("avg_pre_window_latency"),
                functions.min(functions.col("window_time")).as("window_time"))
            .select(functions.col("max_event_time"),functions.col("campaign_id"),functions.col("count"),functions.col("avg_pre_window_latency"),functions.col("window_time"));
        dataWindowed.writeStream().foreach(new newRedisSinkClass())
            .trigger(Trigger.ProcessingTime(3000)) //noch variabel machen
            .outputMode("update").start();
        spark.streams().awaitAnyTermination();
    }
    private static class newRedisSinkClass extends ForeachWriter<Row> {
        JedisPooled jedis;
        public boolean open(long partitionId, long version) {
            jedis = new JedisPooled("131.159.8.103", 6379);
            if(jedis==null){
                return false;
            }
            return true;
        }
        public void process(Row event) {
            String campaign=(String) event.get(event.fieldIndex("campaign_id"));
            String window_time=Long.toString((Long)event.get(event.fieldIndex("window_time")));
            String last_event_time=Long.toString((Long)event.get(event.fieldIndex("max_event_time")));
            String avg_pre_window_latency=Long.toString(((Double)event.get(event.fieldIndex("avg_pre_window_latency"))).longValue());
            String count=Long.toString((Long)event.get(event.fieldIndex("count")));
            String windowUUID= jedis.hmget(campaign, window_time).get(0);
            if(windowUUID==null){
                windowUUID=UUID.randomUUID().toString();
                jedis.hset(campaign,window_time,windowUUID);
                String windowListUUID = jedis.hmget(campaign, "windows").get(0);
                if (windowListUUID == null) {
                    windowListUUID = UUID.randomUUID().toString();
                    jedis.hset(campaign, "windows", windowListUUID);
                }
                jedis.lpush(windowListUUID,window_time);
            }
            jedis.hset(windowUUID,"seen_count",count);
            jedis.hset(windowUUID,"avg_pre_window_latency",avg_pre_window_latency);
            jedis.hset(windowUUID,"last_event_time",last_event_time);
            jedis.hset(windowUUID, "time_updated",Long.toString(System.currentTimeMillis()));
            jedis.lpush("time_updated", Long.toString(System.currentTimeMillis()));
        }
        public void close(Throwable errorOrNull) {
            jedis.close();
        }
    }
    private static JoinedEvent queryRedis(ProjectedEvent event, Broadcast<HashMap<String, String>>br){
        String ad_id=event.getAd_id();
        String event_time=event.getEvent_time();
        String campaign_id = br.value().get(ad_id);
        if(campaign_id!=null){
            return new JoinedEvent(campaign_id, ad_id, event_time);
        }else{
            campaign_id.equals("dsa");
            return null;
        }
        
    }
    private static class DeserializeClass implements MapFunction<String,AdsEvent>{
        public AdsEvent call(String input){
            JSONObject parser = new JSONObject(input);
            return new AdsEvent(
                parser.getString("user_id"),
                parser.getString("page_id"),
                parser.getString("ad_id"),
                parser.getString("ad_type"),
                parser.getString("event_type"),
                parser.getString("event_time"),
                parser.getString("ip_address"));
        }
    }
    private static Map<String, String> getSparkConfs(Map conf) {
        String kafkaBrokers = getKafkaBrokers(conf);
        String zookeeperServers = getZookeeperServers(conf);

        Map<String, String> sparkConfs = new HashMap<String, String>();
        sparkConfs.put("topic", getKafkaTopic(conf));
        sparkConfs.put("bootstrap.servers", kafkaBrokers);
        sparkConfs.put("zookeeper.connect", zookeeperServers);
        sparkConfs.put("jedis_server", getRedisHost(conf));
        sparkConfs.put("group.id", "myGroup");

        return sparkConfs;
    }
    private static class ProjectionClass implements MapFunction<AdsEvent,ProjectedEvent>{
        public ProjectedEvent call(AdsEvent event){
            return new ProjectedEvent(event.getAd_id(), event.getEvent_time());
        }
    }
    public static class AdsEvent implements Serializable {
        private String user_id;
        private String page_id;
        private String ad_id;
        private String ad_type;
        private String event_type;
        private String event_time;
        private String ip_address;
        
        public AdsEvent(String user_id, String page_id, String ad_id, String ad_type,String event_type,String event_time,String ip_address){this.user_id=user_id;this.page_id=page_id;this.ad_id=ad_id;this.ad_type=ad_type;this.event_time=event_time;this.event_type=event_type;this.ip_address=ip_address;};
        public AdsEvent(){this.user_id="test";this.page_id="test";this.ad_id="test";this.ad_type="test";this.event_time="test";this.event_type="test";this.ip_address="test";}
        public String getUser_id() {return user_id;}
        public void setUser_id(String user_id) {this.user_id = user_id;}
        public String getPage_id() {return page_id;}
        public void setPage_id(String page_id) {this.page_id = page_id;}
        public String getAd_id() {return ad_id;}
        public void setAd_id(String ad_id) {this.ad_id = ad_id;}
        public String getAd_type() {return ad_type;}
        public void setAd_type(String ad_type) {this.ad_type = ad_type;}
        public String getEvent_type() {return event_type;}
        public void setEvent_type(String event_type) {this.event_type = event_type;}
        public String getEvent_time() {return event_time;}
        public void setEvent_time(String event_time) {this.event_time = event_time;}
        public String getIp_address() {return ip_address;}
        public void setIp_address(String ip_address) {this.ip_address = ip_address;}
    }
    public static class ProjectedEvent implements Serializable {
        private String ad_id;
        private String event_time;
        
        public ProjectedEvent(String ad_id, String event_time){this.ad_id=ad_id;this.event_time=event_time;}
        public String getAd_id() {return ad_id;}
        public void setAd_id(String ad_id) {this.ad_id = ad_id;}
        public String getEvent_time() {return event_time;}
        public void setEvent_time(String event_time) {this.event_time = event_time;}
    }
    public static class JoinedEvent implements Serializable {
        private String campaign_id;
        private String ad_id;
        private String event_time;
        
        public JoinedEvent(String campaign_id, String ad_id, String event_time){this.campaign_id=campaign_id;this.ad_id=ad_id;this.event_time=event_time;}
        public String getCampaign_id() {return campaign_id;}
        public void setCampaign_id(String campaign_id) {this.campaign_id=campaign_id;}
        public String getAd_id() {return ad_id;}
        public void setAd_id(String ad_id) {this.ad_id = ad_id;}
        public String getEvent_time() {return event_time;}
        public void setEvent_time(String event_time) {this.event_time = event_time;}
    }
    public static class CalculatedEvent implements Serializable {
        private String campaign_id;
        private String ad_id;
        private Long event_time;
        private Long window_time;
        private Long pre_window_time;
        private Timestamp timestamp_eventtime;
        
        public CalculatedEvent(String campaign_id, String ad_id, Long event_time, Long window_time, Long pre_window_time, Timestamp timestamp_eventtime){this.campaign_id=campaign_id;this.ad_id=ad_id;this.event_time=event_time;this.window_time=window_time;this.setPre_window_time(pre_window_time);this.setTimestamp_eventtime(timestamp_eventtime);}
        public Long getPre_window_time() {return pre_window_time;}
        public void setPre_window_time(Long pre_window_time) {this.pre_window_time = pre_window_time;}
        public String getCampaign_id() {return campaign_id;}
        public void setCampaign_id(String campaign_id) {this.campaign_id=campaign_id;}
        public String getAd_id() {return ad_id;}
        public void setAd_id(String ad_id) {this.ad_id = ad_id;}
        public Long getEvent_time() {return event_time;}
        public void setEvent_time(Long event_time) {this.event_time = event_time;}
        public Long getWindow_time() {return window_time;}
        public void setWindow_time(Long window_time) {this.window_time = window_time;}
        public Timestamp getTimestamp_eventtime() {return timestamp_eventtime;}
        public void setTimestamp_eventtime(Timestamp timestamp_eventtime) {this.timestamp_eventtime = timestamp_eventtime;}
    }
    private static class EnrichClass implements MapFunction<JoinedEvent,CalculatedEvent>{
        Long time_divisor = 10000L;
        public CalculatedEvent call(JoinedEvent input){
            return new CalculatedEvent(input.getCampaign_id(), input.getAd_id(), Long.parseLong(input.getEvent_time()), time_divisor * (Long.parseLong(input.getEvent_time())/time_divisor) ,System.currentTimeMillis()-Long.parseLong(input.getEvent_time()),new Timestamp(Long.parseLong(input.getEvent_time())));
        }
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


