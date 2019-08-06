#!/bin/bash

bash ./pspgo-utils/build-normal/compile_install.sh

export MYSQL_USER=`whoami`
export MYSQL_BASE=`pwd`/local/mysql

bash pspgo-utils/build-normal/init_start_mysql.sh

bash pspgo-utils/build-normal/init-sysbench.sh

bash pspgo-utils/build-opt/train-sysbench.sh | tee /tmp/normal_result.txt

$MYSQL_BASE/bin/mysqladmin -u root --socket=$MYSQL_BASE/data/mysql.sock shutdown

