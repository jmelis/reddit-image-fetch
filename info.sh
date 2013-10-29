#!/bin/bash

DIRNAME=`dirname $0`

ID=$(basename $1)
ID=${ID%.*}

sqlite3 -line $DIRNAME/reddit.db "select * from image where id='$ID'"
