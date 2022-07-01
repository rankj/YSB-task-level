#!/bin/bash
# Reference: https://unix.stackexchange.com/questions/20965/how-should-i-determine-the-current-network-utilization
# Copyright: Chris Down https://unix.stackexchange.com/users/10762/chris-down

TIME_OUT=${2}

EXPERIMENT_DIR=${3}

_die() {
    printf '%s\n' "$@"
    exit 1
}

_interface=$1

[[ ${_interface} ]] || _die 'Usage: ifspeed [interface] [time_out] [directory]'
grep -q "^ *${_interface}:" /proc/net/dev || _die "Interface ${_interface} not found in /proc/net/dev"

_interface_bytes_in_old=$(awk "/^ *${_interface}:/"' { if ($1 ~ /.*:[0-9][0-9]*/) { sub(/^.*:/, "") ; print $1 } else { print $2 } }' /proc/net/dev)
_interface_bytes_out_old=$(awk "/^ *${_interface}:/"' { if ($1 ~ /.*:[0-9][0-9]*/) { print $9 } else { print $10 } }' /proc/net/dev)

LAPSED=0
STARTTIME=$(date +%s)
while (( $TIME_OUT > $LAPSED ))
do
    _interface_bytes_in_new=$(awk "/^ *${_interface}:/"' { if ($1 ~ /.*:[0-9][0-9]*/) { sub(/^.*:/, "") ; print $1 } else { print $2 } }' /proc/net/dev)
    _interface_bytes_out_new=$(awk "/^ *${_interface}:/"' { if ($1 ~ /.*:[0-9][0-9]*/) { print $9 } else { print $10 } }' /proc/net/dev)
    
    #printf '%s: %s\n' 'Bytes in/sec'  "$(( _interface_bytes_in_new - _interface_bytes_in_old ))" \
    #                  'Bytes out/sec' "$(( _interface_bytes_out_new - _interface_bytes_out_old ))"

    # printf '%s: %s\n' 'Kilobytes in/sec'  "$(( ( _interface_bytes_in_new - _interface_bytes_in_old ) / 1024 ))" \
    #                   'Kilobytes out/sec' "$(( ( _interface_bytes_out_new - _interface_bytes_out_old ) / 1024 ))"

    # printf '%s: %s\n' 'Megabits in/sec'  "$(( ( _interface_bytes_in_new - _interface_bytes_in_old ) / 131072 ))" \
    #                   'Megabits out/sec' "$(( ( _interface_bytes_out_new - _interface_bytes_out_old ) / 131072 ))"
    
     printf '%s\n' "$(( _interface_bytes_in_new - _interface_bytes_in_old ))" >> "$EXPERIMENT_DIR/network_in.txt"
     printf '%s\n' "$(( _interface_bytes_out_new - _interface_bytes_out_old ))"  >> "$EXPERIMENT_DIR/network_out.txt"
    _interface_bytes_in_old=${_interface_bytes_in_new}
    _interface_bytes_out_old=${_interface_bytes_out_new}
    sleep 1
    ENDTIME=$(date +%s)
    LAPSED=$(($ENDTIME - $STARTTIME))
    #TIME_OUT=$(($TIME_OUT-1))
    
    
    
done

echo "Exiting after $LAPSED seconds"


