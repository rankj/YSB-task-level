#!/bin/bash

rm -rf ./key_values.txt
rm -rf ./campaigns_values.txt
rm -rf ./ads_values.txt

REDIS_KEY_PATTERN="${REDIS_KEY_PATTERN:-*}"
for key in $(redis-cli --scan --pattern "$REDIS_KEY_PATTERN")
do
    type=$(redis-cli type $key)
    if [ $type = "list" ]
    then 
        printf "$key;\n$(redis-cli lrange $key 0 -1 | sed 's/^/  /')\n" >> ./list_key_values.txt
    elif [ $type = "hash" ]
    then
        printf "$key => \n$(redis-cli hgetall $key | sed 's/^/  /')\n"  >> ./hash_key_values.txt
    elif [ $type = "set" ]
    then # ads and campaigns are of type set. For both of them we create a dedicated file
        printf "$(redis-cli smembers $key)\n" >> ./${key}_values.txt
    else #regular keys and their values are stored in the file key_values.txt
        printf "$key;$(redis-cli get $key)\n" >> ./key_values.txt
    fi
done