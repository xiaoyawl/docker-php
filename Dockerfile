FROM benyoo/centos:7.2.1511.20160910

MAINTAINER from www.dwhd.org by lookback (mondeolove@gmail.com)
ENV SWOOLE_V=${SWOOLE_V:-1.7.19} \
	MEMCACHE_V=${MEMCACHE_V:-2.2.7} \
	MEMCACHED_V=${MEMCACHED_V:-2.2.0} \
	REDIS_V=${REDIS_V:-3.1.0} \
	XDEBUG_V=${XDEBUG_V:-2.5.0} \
	EVENT_V=${EVENT_V:-2.2.1} \
	RUN_USER=www

RUN set -x && \
	TEMP_DIR=/tmp/php && SWOOLE_DIR=${TEMP_DIR}/swoole && MEMCACHE_DIR=${TEMP_DIR}/memcache && \
	MEMCACHED_DIR=${TEMP_DIR}/memcached && REDIS_DIR=${TEMP_DIR}/redis && \
	XDEBUF_DIR=${TEMP_DIR}/xdebug && EVENT_DIR=${TEMP_DIR}/event && \
	PECL_URL="https://pecl.php.net/get" && \
	PHPIZE="gcc gcc-c++ make autoconf" && \
	PHP_LIB="firebird-libfbclient libc-client libmcrypt-devel" && \
	RPM_INSTALL="dt-php dt-php-bcmath dt-php-cli dt-php-common dt-php-dba dt-php-devel dt-php-embedded" && \
	RPM_INSTALL="${RPM_INSTALL} dt-php-enchant dt-php-fpm dt-php-gd dt-php-imap dt-php-interbase dt-php-intl dt-php-mbstring" && \
	RPM_INSTALL="${RPM_INSTALL} dt-php-mcrypt dt-php-mysqlnd dt-php-odbc dt-php-opcache dt-php-pdo dt-php-phpdbg dt-php-process" && \
	RPM_INSTALL="${RPM_INSTALL} dt-php-pspell dt-php-recode dt-php-snmp dt-php-soap dt-php-xml dt-php-xmlrpc" && \
	echo -e "[dt-php-5.6]\nname=PHP for Enterprise Linux 7\nbaseurl=http://mirrors.dtops.cc/build_rpm/php5.6\nenabled=1\n" > /etc/yum.repos.d/dt-php.repo && \
	yum install -y epel-release $PHPIZE && \
	yum install -y $RPM_INSTALL $PHP_LIB --nogpgcheck && \
#Mkdir Dir
	mkdir -p ${TEMP_DIR} ${SWOOLE_DIR} ${MEMCACHE_DIR} ${MEMCACHED_DIR} ${REDIS_DIR} ${XDEBUF_DIR} ${EVENT_DIR} && \
#Create User
	groupadd -g 400 -r ${RUN_USER} && \
        useradd -u 400 -r -s /sbin/nologin -g 400 -M -c 'php' ${RUN_USER} && \
#Install Swoole
	curl -Lk ${PECL_URL}/swoole-${SWOOLE_V}.tgz|tar -xz -C ${SWOOLE_DIR} --strip-components=1 && \
	cd ${SWOOLE_DIR} && \
	phpize && ./configure && \
	make -j "$(getconf _NPROCESSORS_ONLN)" && make install && \
	#/usr/lib64/php/modules/
#Install Memcache
	curl -Lk ${PECL_URL}/memcache-${MEMCACHE_V}.tgz|tar -xz -C ${MEMCACHE_DIR} --strip-components=1 && \
	cd ${MEMCACHE_DIR} && \
	yum install -y zlib-devel && \
	phpize && ./configure && \
	make -j "$(getconf _NPROCESSORS_ONLN)" && make install && \
#Install Memcached
	curl -Lk ${PECL_URL}/memcached-${MEMCACHED_V}.tgz|tar -xz -C ${MEMCACHED_DIR} --strip-components=1 && \
	cd ${MEMCACHED_DIR} && \
	yum install -y libmemcached-devel && \
	phpize && ./configure && \
	make -j "$(getconf _NPROCESSORS_ONLN)" && make install && \
#Install Redis
	curl -Lk ${PECL_URL}/redis-${REDIS_V}.tgz|tar -xz -C ${REDIS_DIR} --strip-components=1 && \
	cd ${REDIS_DIR} && \
	phpize && ./configure && \
	make -j "$(getconf _NPROCESSORS_ONLN)" && make install && \
#Install Xdebug
	curl -Lk ${PECL_URL}/xdebug-${XDEBUG_V}.tgz|tar -xz -C ${XDEBUF_DIR} --strip-components=1 && \
	cd ${XDEBUF_DIR} && \
	phpize && ./configure && \
	make -j "$(getconf _NPROCESSORS_ONLN)" && make install && \
#Install Event
	curl -Lk ${PECL_URL}/event-${EVENT_V}.tgz|tar -xz -C ${EVENT_DIR} --strip-components=1 && \
	cd  ${EVENT_DIR} && \
	yum install -y libevent-devel openssl-devel && \
	phpize && ./configure && \
	make -j "$(getconf _NPROCESSORS_ONLN)" && make install && \
#clean OS
	yum remove -y $PHPIZE && \
	yum clean all && \
	rm -rf ${TEMP_DIR}

COPY entrypoint.sh /entrypoint.sh
ADD php-fpm.conf /etc/php-fpm.conf

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
