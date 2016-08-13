FROM benyoo/alpine:3.4.20160812
#FROM registry.ds.com/benyoo/alpine:3.4

MAINTAINER from www.dwhd.org by lookback (mondeolove@gmail.com)

ARG VERSION=${VERSION:-5.6.24}
ARG SHA256=${SHA256:-ed7c38c6dac539ade62e08118258f4dac0c49beca04d8603bee4e0ea6ca8250b}

ENV INSTALL_DIR=/usr/local/php \
	TEMP_DIR=/tmp/php

RUN set -x && \
	[ ! -d ${TEMP_DIR} ] && mkdir -p ${TEMP_DIR} && \
	apk --update --no-cache upgrade && \
	apk --update --no-cache add build-base libxml2-dev openssl-dev curl-dev libjpeg-turbo-dev \
		libpng-dev libmcrypt-dev icu-dev imap-dev freetype-dev gettext-dev \
		libxslt-dev libxpm-dev m4 autoconf && \
	addgroup -g 400 -S www && \
	adduser -u 400 -S -H -s /sbin/nologin -g 'PHP' -G www www && \
	curl -Lk http://www.php.net/distributions/php-${VERSION}.tar.xz|tar xJ -C /tmp && \
	cd /tmp/php-${VERSION}/ && \
	./configure --prefix=${INSTALL_DIR} --with-config-file-path=${INSTALL_DIR}/etc \
		--with-config-file-scan-dir=${INSTALL_DIR}/etc/php.d \
		--with-fpm-user=php --with-fpm-group=php --enable-fpm --enable-opcache --disable-fileinfo \
		--with-mysql=mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
		--with-iconv --with-iconv-dir=/usr/local --with-freetype-dir --with-jpeg-dir --with-png-dir --with-zlib --with-zlib-dir \
		--with-libxml-dir=/usr --enable-xml --disable-rpath --enable-bcmath --enable-shmop --enable-exif \
		--enable-sysvsem --enable-inline-optimization --with-curl --enable-mbregex \
		--enable-mbstring --with-mcrypt --with-gd --enable-gd-native-ttf --enable-gd-jis-conv --with-openssl \
		--with-mhash --enable-pcntl --enable-sockets --with-xmlrpc --enable-ftp --enable-intl --with-xsl \
		--with-gettext --enable-zip --enable-soap --disable-ipv6 --disable-debug \
		#--with-layout=GNU --with-pic --enable-cli --enable-cgi --with-xpm-dir --enable-shared --with-imap && \
		--with-layout=GNU --with-pic --enable-cli --with-xpm-dir --enable-shared --with-imap && \
	make -j $(awk '/processor/{i++}END{print i}' /proc/cpuinfo) && \
	make install && \
	[ ! -e "${INSTALL_DIR}/etc/php.d" ] && mkdir -p ${INSTALL_DIR}/etc/php.d && \
	/bin/cp php.ini-production ${INSTALL_DIR}/etc/php.ini && \
	curl -Lk http://pecl.php.net/get/memcache-3.0.8.tgz|tar xz -C ${TEMP_DIR} && \
	cd ${TEMP_DIR}/memcache-3.0.8 && \
	${INSTALL_DIR}/bin/phpize && \
	./configure --with-php-config=${INSTALL_DIR}/bin/php-config && \
	make -j $(awk '/processor/{i++}END{print i}' /proc/cpuinfo) && \
	make install && \
	#curl -Lk https://launchpad.net/libmemcached/1.0/1.0.18/+download/libmemcached-1.0.18.tar.gz|tar xz -C ${TEMP_DIR} && \
	#cd ${TEMP_DIR}/libmemcached-1.0.18 && \
	#curl -Lk http://pecl.php.net/get/memcached-2.2.0.tgz|tar xz -C ${TEMP_DIR} && \
	#cd ${TEMP_DIR}/memcached-2.2.0 && \
	apk del --no-cache build-base tar wget curl git && \
	rm -rf /var/cache/apk/* /tmp/*

ENV PATH=${INSTALL_DIR}/bin:$PATH
ENV PATH=${INSTALL_DIR}/sbin:$PATH

ADD entrypoint.sh /entrypoint.sh
ADD php-fpm.conf ${INSTALL_DIR}/etc/php-fpm.conf
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

CMD ["php-fpm"]
