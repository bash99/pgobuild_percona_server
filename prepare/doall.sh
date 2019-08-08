#!/bin/bash

CMDPATH="$( dirname "${BASH_SOURCE[0]}" )"

bash $CMDPATH/install-devtoolset.sh
bash $CMDPATH/install-misc.sh
bash $CMDPATH/download-source.sh
bash $CMDPATH/init_syslimit.sh
