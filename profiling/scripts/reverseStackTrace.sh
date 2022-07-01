#!/bin/bash
awk 'BEGIN{DEL=";[ ]*"}
    {
        for (i=NF; i>0; i--) {
            printf "%s", $i;
            if (i>1) {
                printf "%s", "   ";
            }
        }
        printf "\n"
    }'