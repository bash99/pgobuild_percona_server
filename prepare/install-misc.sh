yum install epel-release -y \
&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 430BDF5C56E7C94E848EE60C1C4CBDCDCD2EFD2A \
&& gpg --export --armor 430BDF5C56E7C94E848EE60C1C4CBDCDCD2EFD2A > ${GNUPGHOME}/RPM-GPG-KEY-Percona \
&& yum -y install -y jemalloc pxz numactl-devel rh-mysql57-mecab-devel bzip2 cmake libaio-devel \
      ncurses-devel readline-devel libcurl-devel pam-devel bison-devel bison tmux bc patch
