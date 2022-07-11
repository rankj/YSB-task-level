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
import org.apache.spark.api.java.function.FilterFunction;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
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
import java.net.InetAddress;
import java.net.URL;
import org.yaml.snakeyaml.Yaml;
import org.yaml.snakeyaml.constructor.SafeConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.util.HashMap;
import java.net.UnknownHostException;
import org.apache.spark.sql.streaming.StreamingQuery;


public class SparkContinuousProcessing {
    //private static Broadcast<String> jedis_server;
    //private static JedisPool pool = null;
    private static final Logger LOG = LoggerFactory.getLogger(SparkContinuousProcessing.class);
    public static void main(final String[] args) throws Exception {
        Map conf = Utils.findAndReadConfigFile(args[0], true);
        int kafkaPartitions = ((Number)conf.get("kafka.partitions")).intValue();
        int hosts = ((Number)conf.get("process.hosts")).intValue();
        int cores = ((Number)conf.get("process.cores")).intValue();
        int jedisPort = ((Number)conf.get("redis.port")).intValue();
        Map<String, String> sparkConfig = getSparkConfs(conf);
        RedisAdCampaignCacheSpark redisAdCampaignCache = new RedisAdCampaignCacheSpark(sparkConfig.get("jedis_server"),jedisPort);
        HashMap<String, String> redisCache=redisAdCampaignCache.prepare();
        SparkSession spark = SparkSession
            .builder()
            .appName("JavaAdvertisingTopology")
            .getOrCreate();
        JavaSparkContext sc=new JavaSparkContext(spark.sparkContext());
        Broadcast<HashMap<String, String>>broadcastedRedisCache=sc.broadcast(redisCache);
        Dataset<Row> messages = spark
            .readStream()
            .format("kafka")
            .option("kafka.bootstrap.servers", sparkConfig.get("bootstrap.servers"))
            .option("subscribe", sparkConfig.get("topic"))
            .option("failOnDataLoss", "false")
            .load();
        Dataset<String> kafkaData = messages.selectExpr("CAST(value AS STRING)").as(Encoders.STRING());
        Dataset<AdsEvent> dataDeserialized=kafkaData.map(new DeserializeClass(),Encoders.bean(AdsEvent.class))
            .filter(new FilterClass());
        Dataset<ProjectedEvent> dataProjected=dataDeserialized.map(new ProjectionClass(), Encoders.bean(ProjectedEvent.class));
        Dataset<JoinedEvent> dataJoined=dataProjected.map(new MapFunction<ProjectedEvent,JoinedEvent>(){
            public JoinedEvent call(ProjectedEvent event){
                return queryRedis(event,broadcastedRedisCache);
            }
            },Encoders.bean(JoinedEvent.class));
        Dataset<CalculatedEvent> dataEnriched=dataJoined.map(new EnrichClass(), Encoders.bean(CalculatedEvent.class));
        StreamingQuery query=dataEnriched.writeStream().foreach(
                new ForeachWriter<CalculatedEvent>() {
                    private JedisPooled jedis;
                    private HashMap<String, HashMap<String, WindowClass>> timeBucketMap;
                    private String partition;
            
                    public boolean open(long partitionId, long version) {
                        jedis = new JedisPooled(sparkConfig.get("jedis_server"),jedisPort);
                        if(jedis==null){
                            return false;
                        }
                        timeBucketMap=new HashMap<String, HashMap<String, WindowClass>>();
                        partition=String.valueOf(partitionId);
                        return true;
                    }
                    public void process(CalculatedEvent event) {
                        processingFunc(event, jedis, timeBucketMap, partition);
                    }
                    public void close(Throwable errorOrNull) {
                        closeFunction(jedis, timeBucketMap,partition);
                    }
                }
            )
            .trigger(Trigger.Continuous(sparkConfig.get("checkpoint_interval")))
            .start();
        query.awaitTermination();
        //spark.streams().awaitAnyTermination();
    }

    private static void closeFunction(JedisPooled jedis, HashMap<String, HashMap<String, WindowClass>> timeBucketMap,String partition){
        WindowClass window;
        for(String i:timeBucketMap.keySet()){
            HashMap<String, WindowClass>bucketMap=timeBucketMap.get(i);
            for(String j:bucketMap.keySet()){
                window=bucketMap.get(j);
                if(window.windowUUID==null){
                    String nodeWindowUUID=jedis.hget(partition, j);
                    if(nodeWindowUUID==null){
                        nodeWindowUUID=UUID.randomUUID().toString();
                        jedis.hset(partition,j,nodeWindowUUID);
                    }
                    window.windowUUID= UUID.randomUUID().toString();
                    jedis.hset(nodeWindowUUID,i,window.windowUUID);
                }
                jedis.hset(window.windowUUID,"seen_count",Long.toString(window.seenCount));
                jedis.hset(window.windowUUID,"avg_pre_window_latency",Long.toString(window.avgPreWindowLatency));
                jedis.hset(window.windowUUID,"last_event_time",Long.toString(window.lastEventTime));
                jedis.hset(window.windowUUID,"time_updated",Long.toString(System.currentTimeMillis()));
                jedis.lpush("time_updated", Long.toString(System.currentTimeMillis()));
            }
        }
        jedis.close();
    }
    private static WindowClass redisGetWindow(String windowTime, String campaign, JedisPooled jedis, String partition){
        String nodeWindowUUID=jedis.hget(partition, campaign);
        String windowUUID=null;
        if(nodeWindowUUID!=null){
            windowUUID=jedis.hget(nodeWindowUUID,windowTime);
        }
        if(windowUUID==null){
            WindowClass window=new WindowClass(windowTime,0L,0L,0L,null,0L);
            return window;
        }else{
            Long seen_count=Long.parseLong(jedis.hget(windowUUID,"seen_count"));
            Long avgPreWindowLatency=Long.parseLong(jedis.hget(windowUUID,"avg_pre_window_latency"));
            Long lastEventTime=Long.parseLong(jedis.hget(windowUUID,"last_event_time"));
            Long updatedAt=Long.parseLong(jedis.hget(windowUUID,"time_updated"));

            WindowClass window=new WindowClass(windowTime,seen_count,avgPreWindowLatency,lastEventTime,windowUUID,updatedAt);
            return window;
        }
    }
    private static void processingFunc(CalculatedEvent event, JedisPooled jedis, HashMap<String, HashMap<String, WindowClass>> timeBucketMap, String partition){
        String campaign=event.getCampaign_id();
        String time_bucket=Long.toString((event.getEvent_time()/10000L)*10000L);

        HashMap<String,WindowClass> campaignWindowMap = timeBucketMap.get(time_bucket);
        if(campaignWindowMap==null){
            WindowClass window=redisGetWindow(time_bucket, campaign, jedis, partition);
            window.addCalculatedEvent(event);
            campaignWindowMap=new HashMap<String, WindowClass>();
            campaignWindowMap.put(campaign,window);
            timeBucketMap.put(time_bucket,campaignWindowMap);
        }else{
            WindowClass window=campaignWindowMap.get(campaign);
            if(window==null){ 
                window=redisGetWindow(time_bucket, campaign, jedis, partition);
                window.addCalculatedEvent(event);
                campaignWindowMap.put(campaign,window);
            }else{
                window.addCalculatedEvent(event);
            }
        }
    }
    private static class FilterClass implements FilterFunction<AdsEvent>{
        public boolean call(AdsEvent input){
            return input.getEvent_type().equals("view");
        }
    }
    public static class WindowClass {
        public String timestamp;
        public Long seenCount;
        public Long avgPreWindowLatency;
        public Long lastEventTime;
        public String windowUUID;
        public Long updatedAt;

        public WindowClass(String timestamp,Long seenCount,Long avgPreWindowLatency,Long lastEventTime,String windowUUID, Long updatedAt){
            this.timestamp=timestamp;
            this.seenCount=seenCount;
            this.avgPreWindowLatency=avgPreWindowLatency;
            this.lastEventTime=lastEventTime;
            this.windowUUID=windowUUID;
            this.updatedAt=updatedAt;
        }
        public void addCalculatedEvent(CalculatedEvent calEvent){
            if(lastEventTime<calEvent.getEvent_time()){
                lastEventTime=calEvent.getEvent_time();
            }
            seenCount++;
            avgPreWindowLatency=(avgPreWindowLatency*(seenCount-1)+calEvent.getPre_window_time())/seenCount;
            updatedAt=System.currentTimeMillis();
        }
    }

    private static JoinedEvent queryRedis(ProjectedEvent event, Broadcast<HashMap<String, String>>br){
        String ad_id=event.getAd_id();
        String event_time=event.getEvent_time();
        String campaign_id = br.value().get(ad_id);
        if(campaign_id!=null){
            return new JoinedEvent(campaign_id, ad_id, event_time);
        }else{
            throw new IllegalArgumentException("Join not possible!");
        }
        
    }
    private static class DeserializeClass implements MapFunction<String,AdsEvent>{
        private static final ObjectMapper objectMapper = new ObjectMapper();

        public AdsEvent call(String input) throws IOException{
            JsonNode jsonNode = objectMapper.readTree(input);
            return new AdsEvent(
                jsonNode.get("user_id").asText(),
                jsonNode.get("page_id").asText(),
                jsonNode.get("ad_id").asText(),
                jsonNode.get("ad_type").asText(),
                jsonNode.get("event_type").asText(),
                jsonNode.get("event_time").asText(),
                jsonNode.get("ip_address").asText());
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
        sparkConfs.put("checkpoint_interval", getCheckpointInterval(conf));
        sparkConfs.put("group.id", "myGroup");

        return sparkConfs;
    }
    private static class ProjectionClass implements MapFunction<AdsEvent,ProjectedEvent>{
        public ProjectedEvent call(AdsEvent event){
            return new ProjectedEvent(event.getAd_id(), event.getEvent_time());
        }
    }
    private static class EnrichClass implements MapFunction<JoinedEvent,CalculatedEvent>{
        Long time_divisor = 10000L;
        public CalculatedEvent call(JoinedEvent input){
            //return new CalculatedEvent(input.getCampaign_id(), input.getAd_id(), Long.parseLong(input.getEvent_time()), time_divisor * (Long.parseLong(input.getEvent_time())/time_divisor) ,System.currentTimeMillis()-Long.parseLong(input.getEvent_time()),new Timestamp(Long.parseLong(input.getEvent_time())));
            Long temp= Long.parseLong(input.getEvent_time());
            return new CalculatedEvent(input.getCampaign_id(), input.getAd_id(), temp, System.currentTimeMillis()-temp);
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
        private Long pre_window_time;
        
        public CalculatedEvent(String campaign_id, String ad_id, Long event_time, Long pre_window_time){this.campaign_id=campaign_id;this.ad_id=ad_id;this.event_time=event_time;this.setPre_window_time(pre_window_time);}
        public CalculatedEvent(){this.campaign_id="test";this.ad_id="test";this.event_time=1234L;this.setPre_window_time(1234L);};
        public Long getPre_window_time() {return pre_window_time;}
        public void setPre_window_time(Long pre_window_time) {this.pre_window_time = pre_window_time;}
        public String getCampaign_id() {return campaign_id;}
        public void setCampaign_id(String campaign_id) {this.campaign_id=campaign_id;}
        public String getAd_id() {return ad_id;}
        public void setAd_id(String ad_id) {this.ad_id = ad_id;}
        public Long getEvent_time() {return event_time;}
        public void setEvent_time(Long event_time) {this.event_time = event_time;}
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
    private static String getCheckpointInterval(Map conf) {
        if(!conf.containsKey("spark.checkpoint.interval")) {
            throw new IllegalArgumentException("No checkpoint interval found!");
        }
        return (String)conf.get("spark.checkpoint.interval");
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