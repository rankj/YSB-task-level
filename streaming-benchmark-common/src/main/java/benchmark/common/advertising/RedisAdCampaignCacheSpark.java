/**
 * Copyright 2015, Yahoo Inc.
 * Licensed under the terms of the Apache License 2.0. Please see LICENSE file in the project root for terms.
 */
package benchmark.common.advertising;

import redis.clients.jedis.Jedis;
import java.util.HashMap;
import java.util.Set;

public class RedisAdCampaignCacheSpark{
    private Jedis jedis;

    public RedisAdCampaignCacheSpark(String redisServerHostname, int port) {
        jedis = new Jedis(redisServerHostname, port);
    }

    public HashMap<String, String> prepare() {
        HashMap<String, String> ad_to_campaign = new HashMap<String, String>();
        Set<String>keys=jedis.smembers("ads");
        for(String k:keys){
            if(!k.equals("campaigns") && !k.equals("ads")){
                ad_to_campaign.put(k,jedis.get(k));
            }
        }
        return ad_to_campaign;
    }
}
