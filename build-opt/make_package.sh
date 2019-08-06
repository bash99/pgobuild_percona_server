cd ps-5.7_opt

# clean results
rm -rf _CPack_Packages/Linux/TGZ/* _CPack_Packages/Linux/usr
mkdir -p _CPack_Packages/Linux/TGZ
#./scripts/make_binary_distribution

export PKGNAME=`grep CPACK_PACKAGE_FILE_NAME CPackConfig.cmake | cut -d '"' -f 2`
make DESTDIR=_CPack_Packages/Linux/ install -j $(nproc)
mv _CPack_Packages/Linux/usr/local/mysql _CPack_Packages/Linux/TGZ/$PKGNAME
cd _CPack_Packages/Linux/TGZ/$PKGNAME
mv bin/mysqld ../
strip --strip-debug bin/* lib/*.so lib/*.a 
#lib/mysql/plugin/*.so ./mysql-test/lib/My/SafeProcess/my_safe_process
grep -rinl profile-gen . | xargs -n 64 perl -pi -e "s/--profile-generate //g"
grep -rinl profile-use . | xargs -n 64 perl -pi -e "s/profile-use -fprofile-correction //g"
mv ../mysqld bin/
mv mysql-test ..
cd .. 
#tar zcf pgoed_$PKGNAME.tar.gz $PKGNAME
tar cf - $PKGNAME | pxz -4 > pgoed_$PKGNAME.tar.xz
cd $PKGNAME && strip --strip-debug bin/mysqld lib/mysql/plugin/*.so && cd ..
tar cf - $PKGNAME | pxz -4 > mini_pgoed_$PKGNAME.tar.xz
