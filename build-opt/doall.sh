#!/bin/bash

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )

bash $SELF_PATH/build_5.x_pgo.sh

if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi

bash $SELF_PATH/make_package.sh

