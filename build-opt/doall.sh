#!/bin/bash

bash pspgo-utils/build-opt/build_5.x_pgo.sh

if [ $? -ne 0 ]; then echo "Assert: non-0 exit status detected!"; exit 1; fi

bash pspgo-utils/build-opt/make_package.sh

