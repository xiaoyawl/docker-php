FROM benyoo/centos:7.2.1511.20160910

MAINTAINER from www.dwhd.org by lookback (mondeolove@gmail.com)
ENV VERSION=${VERSION:-5.6.30} \
	SWOOLE_V=${SWOOLE_V:-1.7.19} \
	MEMCACHE_V=${MEMCACHE_V:-2.2.7} \
	MEMCACHED_V=${MEMCACHED_V:-2.2.0} \
	REDIS_V=${REDIS_V:-3.1.0} \
	XDEBUG_V=${XDEBUG_V:-2.5.0} \
	EVENT_V=${EVENT_V:-2.2.1} \
	RUN_USER=www \
	INSTALL_DIR=/usr/local/php \
	TEMP_DIR=/tmp/php

RUN set -x && \
#Define variable
	PHP_URL="https://secure.php.net/get/php-${VERSION}.tar.xz/from/this/mirror" && \
	PHPIZE_DEPS="gcc gcc-c++ make autoconf" && \
	PHPIZE_DEPS="${PHPIZE_DEPS} libxml2-devel openssl-devel curl-devel libjpeg-devel" && \
	PHPIZE_DEPS="${PHPIZE_DEPS} libxslt-devel libpng-devel libXpm-devel freetype-devel libicu-devel libmcrypt-devel" && \
	PHP_EXTRA_CONFIGURE_ARGS="--enable-fpm --with-fpm-user=${RUN_USER} --with-fpm-group=${RUN_USER}" && \
#Add run user
	groupadd -g 400 -r ${RUN_USER} && \
	useradd -u 400 -r -s /sbin/nologin -g 400 -M -c 'php' ${RUN_USER} && \
#Make temp directory
	mkdir -p ${TEMP_DIR} && \
#Down source file
	curl -Lk "${PHP_URL}" | tar xJ -C ${TEMP_DIR} --strip-components=1 && \
	cd ${TEMP_DIR}/ && \
	rpm --rebuilddb && \
#Resolve dependencies
	yum install epel-release -y && \
	yum install -y $PHPIZE_DEPS && \
#Build php
	./configure --prefix=${INSTALL_DIR} \
		--with-config-file-path=${INSTALL_DIR}/etc \
		--with-config-file-scan-dir=${INSTALL_DIR}/etc/php.d \
		${PHP_EXTRA_CONFIGURE_ARGS} \
		--with-gd \
		--with-pic \
		--with-xsl \
		--with-iconv \
		--with-iconv-dir=/usr/local \
		--with-mysql=mysqlnd \
		--with-mysqli=mysqlnd \
		--with-pdo-mysql=mysqlnd \
		--with-freetype-dir \
		--with-jpeg-dir \
		--with-png-dir \
		--with-zlib \
		--with-zlib-dir \
		--with-libxml-dir=/usr \
		--with-curl \
		--with-mcrypt \
		--with-openssl \
		--with-mhash \
		--with-xmlrpc \
		--with-gettext \
		--with-layout=GNU \
		--with-xpm-dir \
		--enable-ftp \
		--enable-zip \
		--enable-xml \
		--enable-cli \
		--enable-exif \
		--enable-intl \
		--enable-soap \
		--enable-pcntl \
		--enable-shmop \
		--enable-bcmath \
		--enable-shared \
		--enable-opcache \
		--enable-sysvsem \
		--enable-mbregex \
		--enable-sockets \
		--enable-mbstring \
		--enable-gd-jis-conv \
		--enable-gd-native-ttf \
		--enable-inline-optimization \
		--disable-fileinfo \
		--disable-rpath \
		--disable-ipv6 \
		--disable-debug && \
	make -j$(getconf _NPROCESSORS_ONLN) && \
	make install && \
#Copy php.ini confige file
	/bin/cp php.ini-production ${INSTALL_DIR}/etc/php.ini && \
#Install memcache extended
	printf "\n" | ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/memcache-${MEMCACHE_V}.tgz && \
#Install memcached extended
	yum install -y libmemcached-devel && \
	printf "\n" | ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/memcached-${MEMCACHED_V}.tgz && \
#Install redis extended
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/redis-${REDIS_V}.tgz && \
#Install swoole extended
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/swoole-${SWOOLE_V}.tgz && \
#Install xdebug extended
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/xdebug-${XDEBUG_V}.tgz && \
#Install event extended
	yum install -y libevent-devel && \
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/event-${EVENT_V}.tgz && \
#Clean OS
	yum remove -y gcc gcc-c++ make autoconf && \
	yum clean all && \
	rm -rf ${TEMP_DIR} /tmp/*

COPY entrypoint.sh /entrypoint.sh
ADD php-fpm.conf ${INSTALL_DIR}/etc/php-fpm.conf
ENV PATH=${INSTALL_DIR}/bin:${INSTALL_DIR}/sbin:$PATH

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
