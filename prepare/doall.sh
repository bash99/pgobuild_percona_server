#!/bin/bash

CMDPATH="$( dirname "${BASH_SOURCE[0]}" )"

sudo bash $CMDPATH/install-devtoolset.sh
sudo bash $CMDPATH/install-misc.sh
bash $CMDPATH/download-source.sh
sudo bash $CMDPATH/init_syslimit.sh
