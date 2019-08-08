#!/bin/bash

: ${1?"Usage: $0 MYSQL_BASE_PATH"}
MYSQL_BASE=$1

SELF_PATH=$( dirname "${BASH_SOURCE[0]}" )
. $SELF_PATH/common.sh

rm -f ~/.my.cnf
MYPASS=`dd status=none bs=128 count=1 if=/dev/urandom | base64 | tr -dc 'a-zA-Z1-9' | fold -w 12 | less | head -n 1`_3

if [ -f "$MYSQL_BASE/scripts/mysql_install_db" ]; then ## old mysql 5.6
  PASS_LOG=~/.mysql_secret
  PASS_SQL="SET PASSWORD FOR 'root'@'localhost' = PASSWORD('$MYPASS')"
else
  PASS_LOG=$MYSQL_LOG
  PASS_SQL="ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYPASS'"
fi
RAND_PASS=`egrep -e "temporary password|random password" $PASS_LOG | rev | cut -d ' ' -f 1 | rev`

echo $MYSQL_CLI_PATH -uroot --connect-expired-password --socket=$MYSQL_SOCK_PATH -p"$RAND_PASS" -e "$PASS_SQL"
$MYSQL_CLI_PATH -uroot --connect-expired-password --socket=$MYSQL_SOCK_PATH -p"$RAND_PASS" -e "$PASS_SQL" \
&& echo "mysql password changed to $MYPASS, will write to ~/.my.cnf" && \
printf "[client]\n\tpassword=$MYPASS" > ~/.my.cnf && \
chmod 600 ~/.my.cnf
