## below is settings works for training
## do more plan and test before change it
: ${table_size:=2000000}
: ${table_count:=16}
: ${oltp_threads:=16}
: ${warmup_time:=40}
: ${max_point_select_time:=50}
: ${standalone_point_select_time:=60}
: ${max_oltp_time:=160}

: ${dbeng:=innodb}

## common PATH
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:$MYSQL_BASE/lib/"

: ${SYSBENCH_BASE:=$MYSQL_BASE/sysbench}
SYSBENCH_LUA_DIR=$SYSBENCH_BASE/share/sysbench/

: ${MYSQL_SOCKET:=$MYSQL_BASE/data/mysql.sock}
: ${MYSQL_HOST:=localhost}
: ${MYSQL_PORT:=3306}

if [ -n "${MYSQL_SOCKET:-}" ]; then
  MYSQL_CONN_OPT="--mysql-socket=$MYSQL_SOCKET"
else
  MYSQL_CONN_OPT="--mysql-host=$MYSQL_HOST --mysql-port=$MYSQL_PORT"
fi

SYSBENCH_OPT="--table-size=${table_size} --tables=${table_count} --threads=${oltp_threads} --max-requests=0 --report-interval=5 --db-driver=mysql --mysql_storage_engine=${dbeng} --mysql-db=sbtest_${dbeng} --mysql-user=sbtest --mysql-password=sbtest12 ${MYSQL_CONN_OPT} --mysql-ignore-errors=1062,1213"
SYSBENCH_BIN=$SYSBENCH_BASE/bin/sysbench
