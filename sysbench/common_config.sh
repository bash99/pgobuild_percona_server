## below is settings works for training
## do more plan and test before change it
export table_size=2000000
export table_count=16
export oltp_threads=16
export max_point_select_time=50
export max_oltp_time=160

: ${dbeng:=innodb}

## common PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$MYSQL_BASE/lib/

: ${SYSBENCH_BASE:=$MYSQL_BASE/sysbench}
SYSBENCH_LUA_DIR=$SYSBENCH_BASE/share/sysbench/

SYSBENCH_OPT="--table-size=${table_size} --tables=${table_count} --threads=${oltp_threads} --max-requests=0 --report-interval=5 --db-driver=mysql --mysql_storage_engine=${dbeng} --mysql-db=sbtest_${dbeng} --mysql-user=sbtest --mysql-password=sbtest12 --mysql-socket=$MYSQL_BASE/data/mysql.sock --mysql-ignore-errors=1062,1213"
SYSBENCH_BIN=$SYSBENCH_BASE/bin/sysbench

