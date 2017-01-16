FROM benyoo/alpine:3.4.20160812
#FROM registry.ds.com/benyoo/alpine:3.4

MAINTAINER from www.dwhd.org by lookback (mondeolove@gmail.com)

ARG VERSION=${VERSION:-5.6.29}
ARG SHA256=${SHA256:-0ff352a433f73e2c82b0d5b283b600402518569bf72a74e247f356dacbf322a7}
ARG SWOOLE_VERSION=${SWOOLE_VERSION:-1.8.9}

ENV INSTALL_DIR=/usr/local/php \
	TEMP_DIR=/tmp/php

RUN set -x && \
# Change Mirrors
	LOCAL_MIRRORS=${LOCAL_MIRRORS:-http://mirrors.ds.com/alpine} && \
	NET_MIRRORS=${NET_MIRRORS:-http://dl-cdn.alpinelinux.org/alpine} && \
	#LOCAL_MIRRORS_HTTP_CODE=$(curl -LI -m 10 -o /dev/null -sw %{http_code} ${LOCAL_MIRRORS}) && \
	PHP_URL="https://secure.php.net/get/php-${VERSION}.tar.xz/from/this/mirror" && \
	LIBICONV_VERSION=1.14 && \
	LIBICONV_DIR=/tmp/libiconv && \
#Mkdir TEMP_DIR
	mkdir -p ${LIBICONV_DIR} ${TEMP_DIR} /tmp/memcached && cd /tmp && \
#Edit mirror url
	#if [ "${LOCAL_MIRRORS_HTTP_CODE}" == "200" ]; then \
	#	echo -e "${LOCAL_MIRRORS}/v3.4/main\n${LOCAL_MIRRORS}/v3.4/community" > /etc/apk/repositories; else \
	#	echo -e "${NET_MIRRORS}/v3.4/main\n${NET_MIRRORS}/v3.4/community" > /etc/apk/repositories; fi && \
#Upgrade OS and install
	apk --update --no-cache upgrade && \
	apk --update --no-cache add build-base libxml2-dev openssl-dev curl-dev libjpeg-turbo-dev libpng-dev libmcrypt-dev icu-dev \
		imap-dev freetype-dev gettext-dev libxslt-dev libxpm-dev m4 autoconf libaio-dev git linux-headers cyrus-sasl-dev libsasl tar xz && \
#Add run php user&group
	addgroup -g 400 -S www && \
	adduser -u 400 -S -H -s /sbin/nologin -g 'PHP' -G www www && \
#Download File
	curl -Lk "${PHP_URL}" | tar xJ -C ${TEMP_DIR} --strip-components=1 && \
	curl -SL http://ftp.gnu.org/pub/gnu/libiconv/libiconv-${LIBICONV_VERSION}.tar.gz | tar -xz -C ${LIBICONV_DIR} --strip-components=1 && \
#Install libiconv
	rm /usr/bin/iconv && \
	curl -Lk https://github.com/mxe/mxe/raw/7e231efd245996b886b501dad780761205ecf376/src/libiconv-1-fixes.patch > libiconv-1-fixes.patch && \
	cd ${LIBICONV_DIR} && \
	patch -p1 < ../libiconv-1-fixes.patch && \
	./configure --prefix=/usr/local && \
	make -j "$(getconf _NPROCESSORS_ONLN)" && \
	make install && \
#Install PHP
	cd ${TEMP_DIR}/ && \
	./configure --prefix=${INSTALL_DIR} --with-config-file-path=${INSTALL_DIR}/etc \
		--with-config-file-scan-dir=${INSTALL_DIR}/etc/php.d --with-fpm-user=php --with-fpm-group=php --enable-fpm --enable-opcache \
		--disable-fileinfo --with-mysql=mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --with-iconv --with-iconv-dir=/usr/local \
		--with-freetype-dir --with-jpeg-dir --with-png-dir --with-zlib --with-zlib-dir --with-libxml-dir=/usr --enable-xml --disable-rpath \
		--enable-bcmath --enable-shmop --enable-exif --enable-sysvsem --enable-inline-optimization --with-curl --enable-mbregex --enable-mbstring \
		--with-mcrypt --with-gd --enable-gd-native-ttf --enable-gd-jis-conv --with-openssl --with-mhash --enable-pcntl --enable-sockets \
		--with-xmlrpc --enable-ftp --enable-intl --with-xsl --with-gettext --enable-zip --enable-soap --disable-ipv6 --disable-debug \
		--with-layout=GNU --with-pic --enable-cli --with-xpm-dir --enable-shared --with-imap --enable-memcache \
		--with-iconv-dir=/usr/local && \
		#--enable-cgi
	make -j$(getconf _NPROCESSORS_ONLN) && \
	make install && \
	[ ! -e "${INSTALL_DIR}/etc/php.d" ] && mkdir -p ${INSTALL_DIR}/etc/php.d && \
	/bin/cp php.ini-production ${INSTALL_DIR}/etc/php.ini && \
#Install libmemcached memcache-3.0.8
	apk add --no-cache php5-memcache libmemcached-dev && \
	mv /usr/lib/php5/modules/memcache.so ${INSTALL_DIR}/lib/php/20131226/memcache.so && \
#Install memcached-2.2.0
	curl -Lk http://pecl.php.net/get/memcached-2.2.0.tgz|tar xz -C /tmp/memcached --strip-components=1 && \
	cd /tmp/memcached && \
	${INSTALL_DIR}/bin/phpize && \
	./configure --with-php-config=${INSTALL_DIR}/bin/php-config --disable-memcached-sasl && \
	make -j $(awk '/processor/{i++}END{print i}' /proc/cpuinfo) && \
	make install && \
#Install redis-2.2.8
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/redis-2.2.8.tgz && \
#Install swoole
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/swoole-${SWOOLE_VERSION}.tgz && \
#Install xdebug
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/xdebug-2.5.0.tgz && \
#Uninstalll Build software an clean OS
	apk del --no-cache build-base tar wget curl git m4 autoconf libaio-dev git linux-headers && \
	rm -rf /var/cache/apk/* /tmp/*

ENV PATH=${INSTALL_DIR}/bin:$PATH
ENV PATH=${INSTALL_DIR}/sbin:$PATH \
	TERM=linux

COPY entrypoint.sh /entrypoint.sh
ADD php-fpm.conf ${INSTALL_DIR}/etc/php-fpm.conf

ENTRYPOINT ["/entrypoint.sh"]

CMD ["php-fpm"]
