#!/bin/bash

#rm -rf ./key_values.txt
#rm -rf ./campaigns_values.txt
#rm -rf ./ads_values.txt
#rm -rf redis_store
#mkdir redis_store
#cd ./redis_store
REDIS_KEY_PATTERN="${REDIS_KEY_PATTERN:-*}"
rm -rf keys.txt
rm -rf values.txt
rm -rf key_values.txt
rm -rf redis_store.tmp
rm -rf ads_values.txt
rm -rf campaigns_values.txt
mkdir redis_store.tmp
redis-cli smembers ads >> ./redis_store.tmp/ads.txt 2>&1 &
redis-cli smembers campaigns >> ./redis_store.tmp/campaigns.txt 2>&1 &

cd redis_store.tmp
for key in $(redis-cli --scan --pattern "$REDIS_KEY_PATTERN")
do
    echo "$key" >> keys.txt 
done
sed -i '/campaigns/d' ./keys.txt 
sed -i '/ads/d' ./keys.txt
sed -i 's/[[:blank:]]//g' ./keys.txt

split --lines 25000 keys.txt keys_

for i in $(ls keys_*); do
  sub=${i#*_}
  sed -i '1 i\redis-cli mget ' ${i}
  tr '\n' ' ' < ${i} > mget-${i}
  chmod +x mget-${i}
  ./mget-${i} >> ./values_${sub} 2>&1 &
done

wait < <(jobs -p)
cat values* >> values.txt
#
sed -i 's/\([^ ]*\)/"\1"/g' values.txt
sed -i 's/^/ /' values.txt
#mv values.txt ../values.txt

paste keys.txt values.txt > key_values.txt
#rm -rf keys.txt
#rm -rf values.txt


#cat ./redis_store.tmp/values_* > values.txt
# remove horizontal blanks from keys.txt file
# prepare redis-cli megt command to read all keys
#sed -i '1 i\redis-cli mget ' keys_part_aa
#remove 
#sed -i '/redis-cli mget /d' keys.txt 
# remove linebreak in file 
#chmod +x redis-keys-mget
#split -n 8 ./keys.txt keys_part_
#rm keys.txt
#for i in $(ls); do "cat $i | perl dosomething > ../splitfiles_processed/$i &"; done