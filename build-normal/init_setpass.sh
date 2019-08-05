rm -f ~/.my.cnf
export MYPASS=`dd status=none bs=128 count=1 if=/dev/urandom | base64 | tr -dc 'a-zA-Z1-9' | fold -w 12 | less | head -n 1`_3
MYSQL_LOG=$MYSQL_BASE/data/mysql.err.log
$MYSQL_BASE/bin/mysql -uroot --connect-expired-password --socket=$MYSQL_BASE/data/mysql.sock -p`grep "temporary password" $MYSQL_LOG | rev | cut -d ' ' -f 1 | rev` -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYPASS'" \
&& echo "mysql password changed to $MYPASS, will write to ~/.my.cnf"
printf "[client]\n\tpassword=$MYPASS" > ~/.my.cnf
chmod 600 ~/.my.cnf
