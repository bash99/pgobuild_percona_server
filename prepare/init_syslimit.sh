#!/bin/bash

perl -pi -e "s/# End of file//" /etc/security/limits.conf
cat >>/etc/security/limits.conf <<EOF
*		hard	nofile	102400
*		soft	nofile	102400
mysql		soft	memlock	unlimited
mysql		hard	memlock	unlimited
root		soft    memlock	unlimited
root		hard    memlock	unlimited
# End of file
EOF

sysctl -w fs.file-max=100000
sysctl -w vm.swappiness=10

