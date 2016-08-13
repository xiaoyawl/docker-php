FROM benyoo/alpine:3.4.20160812
#FROM registry.ds.com/benyoo/alpine:3.4

MAINTAINER from www.dwhd.org by lookback (mondeolove@gmail.com)

ARG VERSION=${VERSION:-5.6.24}
ARG SHA256=${SHA256:-ed7c38c6dac539ade62e08118258f4dac0c49beca04d8603bee4e0ea6ca8250b}

ENV INSTALL_DIR=/usr/local/php \
	TEMP_DIR=/tmp/php

RUN set -x && \
#Mkdir TEMP_DIR
	[ ! -d ${TEMP_DIR} ] && mkdir -p ${TEMP_DIR} && \
#Upgrade OS and install 
	apk --update --no-cache upgrade && \
	apk --update --no-cache add build-base libxml2-dev openssl-dev curl-dev libjpeg-turbo-dev libpng-dev libmcrypt-dev icu-dev \
		#imap-dev freetype-dev gettext-dev libxslt-dev libxpm-dev m4 autoconf libevent-dev && \
		imap-dev freetype-dev gettext-dev libxslt-dev libxpm-dev m4 autoconf && \
#Add run php user&group
	addgroup -g 400 -S www && \
	adduser -u 400 -S -H -s /sbin/nologin -g 'PHP' -G www www && \
#Install PHP
	curl -Lk http://www.php.net/distributions/php-${VERSION}.tar.xz|tar xJ -C ${TEMP_DIR} && \
	cd ${TEMP_DIR}/php-${VERSION}/ && \
	./configure --prefix=${INSTALL_DIR} --with-config-file-path=${INSTALL_DIR}/etc \
		--with-config-file-scan-dir=${INSTALL_DIR}/etc/php.d --with-fpm-user=php --with-fpm-group=php --enable-fpm --enable-opcache \
		--disable-fileinfo --with-mysql=mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --with-iconv --with-iconv-dir=/usr/local \
		--with-freetype-dir --with-jpeg-dir --with-png-dir --with-zlib --with-zlib-dir --with-libxml-dir=/usr --enable-xml --disable-rpath \
		--enable-bcmath --enable-shmop --enable-exif --enable-sysvsem --enable-inline-optimization --with-curl --enable-mbregex --enable-mbstring \
		--with-mcrypt --with-gd --enable-gd-native-ttf --enable-gd-jis-conv --with-openssl --with-mhash --enable-pcntl --enable-sockets \
		--with-xmlrpc --enable-ftp --enable-intl --with-xsl --with-gettext --enable-zip --enable-soap --disable-ipv6 --disable-debug \
		--with-layout=GNU --with-pic --enable-cli --with-xpm-dir --enable-shared --with-imap --enable-memcache && \
		#--enable-cgi
	make -j $(awk '/processor/{i++}END{print i}' /proc/cpuinfo) && \
	make install && \
	[ ! -e "${INSTALL_DIR}/etc/php.d" ] && mkdir -p ${INSTALL_DIR}/etc/php.d && \
	/bin/cp php.ini-production ${INSTALL_DIR}/etc/php.ini && \
#Install zendopcache-7.0.5
#	curl -Lk https://pecl.php.net/get/zendopcache-7.0.5.tgz|tar xz -C ${TEMP_DIR} && \
#	cd ${TEMP_DIR}/zendopcache-7.0.5 && \
#	${INSTALL_DIR}/bin/phpize && \
#	./configure --with-php-config=${INSTALL_DIR}/bin/php-config && \
#Install memcached-1.4.28
#	curl -Lk http://www.memcached.org/files/memcached-1.4.28.tar.gz|tar xz -C ${TEMP_DIR} && \
#	cd ${TEMP_DIR}/memcached-1.4.28 && \
#	adduser -S -s /sbin/nologin -H memcached && \
#	./configure --prefix=/usr/local/memcached && \
#	make -j $(awk '/processor/{i++}END{print i}' /proc/cpuinfo) && \
#	make install && \
#Install memcache-3.0.8
#	curl -Lk http://pecl.php.net/get/memcache-3.0.8.tgz|tar xz -C ${TEMP_DIR} && \
#	cd ${TEMP_DIR}/memcache-3.0.8 && \
#	${INSTALL_DIR}/bin/phpize && \
#	./configure --with-php-config=${INSTALL_DIR}/bin/php-config && \
#	make -j $(awk '/processor/{i++}END{print i}' /proc/cpuinfo) && \
#	make install && \
#Install libmemcached memcache-3.0.8
	apk add --no-cache php5-memcache libmemcached-dev && \
	mv /usr/lib/php5/modules/memcache.so ${INSTALL_DIR}/lib/php/20131226/memcache.so && \
#Install memcached-2.2.0
	curl -Lk http://pecl.php.net/get/memcached-2.2.0.tgz|tar xz -C ${TEMP_DIR} && \
	cd ${TEMP_DIR}/memcached-2.2.0 && \
	${INSTALL_DIR}/bin/phpize && \
	./configure --with-php-config=${INSTALL_DIR}/bin/php-config --disable-memcached-sasl && \
	make -j $(awk '/processor/{i++}END{print i}' /proc/cpuinfo) && \
	make install && \
#Install redis-2.2.8
	${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/redis-2.2.8.tgz && \
#Uninstalll Build software an clean OS
	apk del --no-cache build-base tar wget curl git m4 autoconf && \
	rm -rf /var/cache/apk/* /tmp/*

ENV PATH=${INSTALL_DIR}/bin:$PATH
ENV PATH=${INSTALL_DIR}/sbin:$PATH \
	TERM=linux

ADD entrypoint.sh /entrypoint.sh
ADD php-fpm.conf ${INSTALL_DIR}/etc/php-fpm.conf
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["php-fpm"]
