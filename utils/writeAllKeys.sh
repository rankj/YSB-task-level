#!/bin/bash

redis-cli flushall

while IFS= read -r value
do
  redis-cli sadd "campaigns" $value
done < ./campaigns_values.txt
while IFS= read -r value
do
  redis-cli sadd "ads" $value
done < ./ads_values.txt
while IFS=';' read -r key value
do
  redis-cli set $key $value
done < ./key_values.txt