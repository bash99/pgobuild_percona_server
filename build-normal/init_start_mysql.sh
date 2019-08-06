export MYSQL_USER=`whoami`
export MYSQL_BASE=`pwd`/local/mysql
rm -rf $MYSQL_BASE/data

mkdir -p $MYSQL_BASE/data
mkdir -p $MYSQL_BASE/etc

bash pspgo-utils/build-normal/init_conf.sh $MYSQL_BASE/data

LD_PRELOAD="/usr/lib64/libjemalloc.so.1" MALLOC_CONF="lg_dirty_mult:-1" $MYSQL_BASE/bin/mysqld --defaults-file=$MYSQL_BASE/etc/my.automem.cnf --basedir=$MYSQL_BASE --datadir=$MYSQL_BASE/data --plugin-dir=$MYSQL_BASE/lib/mysql/plugin --user=$MYSQL_USER  --initialize
LD_PRELOAD="/usr/lib64/libjemalloc.so.1" MALLOC_CONF="lg_dirty_mult:-1" $MYSQL_BASE/bin/mysqld --defaults-file=$MYSQL_BASE/etc/my.automem.cnf --basedir=$MYSQL_BASE --datadir=$MYSQL_BASE/data --plugin-dir=$MYSQL_BASE/lib/mysql/plugin --user=$MYSQL_USER &

sleep 10 && bash pspgo-utils/build-normal/init_setpass.sh
