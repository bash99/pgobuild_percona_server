: ${MYSQL_USER:=`whoami`}

MYSQL_CNF_PATH=$MYSQL_BASE/etc/my.automem.cnf
MYSQL_DATA_PATH=$MYSQL_BASE/data
MYSQL_SOCK_PATH=$MYSQL_DATA_PATH/mysql.sock
MYSQL_CLI_PATH=$MYSQL_BASE/bin/mysql
: ${MYSQLD_PATH:=$MYSQL_BASE/bin/mysqld}
MYSQLD_WITHOPT="$MYSQLD_PATH --defaults-file=$MYSQL_CNF_PATH --basedir=$MYSQL_BASE --datadir=${MYSQL_DATA_PATH} --plugin-dir=$MYSQL_BASE/lib/mysql/plugin --user=$MYSQL_USER"
MYSQLADMIN_PATH=$MYSQL_BASE/bin/mysqladmin
MYSQL_LOG=$MYSQL_BASE/data/mysql.err.log
