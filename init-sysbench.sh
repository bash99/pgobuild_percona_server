create user sbtest@localhost identified by 'sbtest12';
create database sbtest;
grant all on sbtest.* to sbtest@localhost;

echo "if sysbench complain it can not found oltp, set SYSBENCH_LUA_DIR to where you can found the oltp.lua file!"
sysbench --test=${SYSBENCH_LUA_DIR}oltp.lua --oltp-table-size=2000000 --oltp-tables-count=16 --num-threads=1  --report-interval=5 --db-driver=mysql --mysql-table-engine=innodb --mysql-user=sbtest --mysql-password=sbtest12 --rand-seed=`cat /dev/urandom | tr -dc '0-9' | fold -w 3 | head -n 1` prepare

