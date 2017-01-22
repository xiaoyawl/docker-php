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
	PHP_URL="https://secure.php.net/get/php-${VERSION}.tar.xz/from/this/mirror" && \
	PHPIZE_DEPS="gcc gcc-c++ make autoconf" && \
	PHPIZE_DEPS="${PHPIZE_DEPS} libxml2-devel openssl-devel curl-devel libjpeg-devel" && \
	PHPIZE_DEPS="${PHPIZE_DEPS} libxslt-devel libpng-devel libXpm-devel freetype-devel libicu-devel libmcrypt-devel" && \
	PHP_EXTRA_CONFIGURE_ARGS="--enable-fpm --with-fpm-user=${RUN_USER} --with-fpm-group=${RUN_USER}" && \
	groupadd -g 400 -r ${RUN_USER} && \
	useradd -u 400 -r -s /sbin/nologin -g 400 -M -c 'php' ${RUN_USER} && \
	mkdir -p ${TEMP_DIR} && \
	curl -Lk "${PHP_URL}" | tar xJ -C ${TEMP_DIR} --strip-components=1 && \
	cd ${TEMP_DIR}/ && \
	rpm --rebuilddb && \
	yum install epel-release -y && \
	yum install -y $PHPIZE_DEPS && \
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
	printf "\n" | ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/memcache-${MEMCACHE_V}.tgz && \
	yum install -y libmemcached-devel && \
	printf "\n" | ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/memcached-${MEMCACHED_V}.tgz && \
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/redis-${REDIS_V}.tgz && \
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/swoole-${SWOOLE_V}.tgz && \
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/xdebug-${XDEBUG_V}.tgz && \
	yum install -y libevent-devel && \
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/event-${EVENT_V}.tgz && \
	yum remove -y gcc gcc-c++ make autoconf && \
	yum clean all && \
	rm -rf ${TEMP_DIR}

COPY entrypoint.sh /entrypoint.sh
ADD php-fpm.conf /etc/php-fpm.conf

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
