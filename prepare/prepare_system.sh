#!/bin/bash

CMDPATH="$( dirname "${BASH_SOURCE[0]}" )"

sudo $CMDPATH/install-devtoolset.sh
if [ $? -ne 0 ]; then echo "download devtoolset failed! Assert: non-0 exit status detected!"; exit 1; fi

sudo $CMDPATH/install-misc.sh
if [ $? -ne 0 ]; then echo "download depend package failed! Assert: non-0 exit status detected!"; exit 1; fi

sudo $CMDPATH/init_syslimit.sh
