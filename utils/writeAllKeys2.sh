#!/bin/bash

echo "flushing redis"
redis-cli flushall

cd redis_store.tmp
split --lines 25000 campaigns.txt campaigns_
split --lines 25000 ads.txt ads_
split --lines 12500 key_values.txt keyValues_

echo "writing campaigns"
#write campaigns
for i in $(ls campaigns_*); do
  sed -i '1 i\redis-cli sadd campaigns ' ${i}
  tr '\n' ' ' < ${i} > sadd-${i}
  chmod +x sadd-${i}
  ./sadd-${i}
done

#write ads
echo "writing ads"
for i in $(ls ads_*); do
  sed -i '1 i\redis-cli sadd ads ' ${i}
  tr '\n' ' ' < ${i} > sadd-${i}
  chmod +x sadd-${i}
  ./sadd-${i}
done

#write keys
echo "writing keys"
for i in $(ls keyValues_*); do
  sed -i '1 i\redis-cli mset ' ${i}
  tr '\n' ' ' < ${i} > mset-${i}
  chmod +x mset-${i}
  ./mset-${i}
done

wait < <(jobs -p)
echo "done"