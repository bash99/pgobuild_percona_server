export MYSQL_BASE=`pwd`/local/mysql

$MYSQL_BASE/bin/mysql -uroot --socket=$MYSQL_BASE/data/mysql.sock <<EOF
create user sbtest@localhost identified by 'sbtest12';
create database sbtest;
grant all on sbtest.* to sbtest@localhost;
EOF

#echo "if sysbench complain it can not found oltp, set SYSBENCH_LUA_DIR to where you can found the oltp.lua file!"
git clone --depth 1 https://github.com/akopytov/sysbench -b 0.5 sysbench
./autogen.sh 
./configure --with-mysql=$MYSQL_BASE
make -j 5
make install prefix=$MYSQL_BASE/sysbench

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$MYSQL_BASE/lib/
export SYSBENCH_LUA_DIR=$MYSQL_BASE/sysbench/share/sysbench/

$MYSQL_BASE/sysbench/bin/sysbench --test=$SYSBENCH_LUA_DIR/oltp.lua --oltp-table-size=2000000 --oltp-tables-count=16 --num-threads=1  --report-interval=5 --db-driver=mysql --mysql-table-engine=innodb --mysql-user=sbtest --mysql-password=sbtest12 --mysql-socket=$MYSQL_BASE/data/mysql.sock --rand-seed=`cat /dev/urandom | tr -dc '0-9' | fold -w 3 | head -n 1` prepare

