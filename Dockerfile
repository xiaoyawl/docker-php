#FROM benyoo/centos:7.2.1511.20160910
FROM benyoo/centos:7.9.2009.20230703

MAINTAINER from www.dwhd.org by lookback (mondeolove@gmail.com)
ENV VERSION=${VERSION:-7.4.33} \
        SWOOLE_V=${SWOOLE_V:-4.8.13} \
        MEMCACHE_V=${MEMCACHE_V:-4.0.5.2} \
        MEMCACHED_V=${MEMCACHED_V:-3.2.0} \
        REDIS_V=${REDIS_V:-5.3.7} \
        XDEBUG_V=${XDEBUG_V:-3.1.6} \
        EVENT_V=${EVENT_V:-3.0.6} \
        RUN_USER=www \
        INSTALL_DIR=/usr/local/php \
        TEMP_DIR=/tmp/php

RUN set -x && \
#Set date to Shanghai
        rm -f /etc/localtime && ln -sv /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
#Define variable
        PHP_URL="https://secure.php.net/get/php-${VERSION}.tar.xz/from/this/mirror" && \
        PHPIZE_DEPS="gcc gcc-c++ make autoconf" && \
        PHPIZE_DEPS="${PHPIZE_DEPS} libxml2-devel openssl-devel curl-devel libjpeg-devel sqlite-devel oniguruma-devel libmemcached-devel" && \
        PHPIZE_DEPS="${PHPIZE_DEPS} libxslt-devel libpng-devel libXpm-devel freetype-devel libicu-devel libmcrypt-devel ImageMagick-devel" && \
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
                --with-pear \
                --enable-fpm \
                --enable-ftp \
                --enable-zip \
                --enable-xml \
                --enable-cli \
                --enable-exif \
                --enable-intl \
                --enable-ipv6 \
                --enable-soap \
                --enable-pcntl \
                --enable-shmop \
                --enable-bcmath \
                --enable-fileinfo \
                --enable-shared \
                --enable-opcache \
                --enable-sysvsem \
                --enable-mbregex \
                --enable-sockets \
                --enable-mbstring \
                --enable-gd-jis-conv \
                --enable-gd-native-ttf \
                --enable-inline-optimization \
                --disable-rpath \
                --disable-debug && \
        make -j$(getconf _NPROCESSORS_ONLN) && \
        make install && \
#Copy php.ini confige file
        /bin/cp php.ini-production ${INSTALL_DIR}/etc/php.ini && \
        mkdir -p ${INSTALL_DIR}/etc/php.d/ && \
        echo -e "\n\n\n\n\n" >> ${INSTALL_DIR}/etc/php.ini && \
#Install memcache extended
        printf "\n" | ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/memcache-${MEMCACHE_V}.tgz && \
        echo -e '[memcache]\nextension = memcache.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#Install memcached extended
        printf "\n" | ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/memcached-${MEMCACHED_V}.tgz && \
        echo -e '[memcached]\nextension = memcached.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#Install redis extended
        ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/redis-${REDIS_V}.tgz && \
        echo -e '[Redis]\nextension = redis.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#Install swoole extended
        ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/swoole-${SWOOLE_V}.tgz && \
        echo -e '[swoole]\nextension = swoole.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#Install xdebug extended
        ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/xdebug-${XDEBUG_V}.tgz && \
        echo -e '[xdebug]\nextension = xdebug.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#Install event extended
        yum install -y libevent-devel && \
        ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/event-${EVENT_V}.tgz && \
         echo -e '[event]\nextension = event.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#Install Opencache extended
#       ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/zendopcache-7.0.5.tgz && \
#Install ionCube extended
        mkdir -p ${TEMP_DIR}/ioncube && \
        curl -Lk https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz | tar -xz -C ${TEMP_DIR}/ioncube/ --strip-components=1 && \
        cp ${TEMP_DIR}/ioncube/ioncube_loader_lin_7.4.so /usr/local/php/lib/php/20190902/ && \
        echo -e '[ionCube Loader]\nzend_extension = ioncube_loader_lin_7.4.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#Install imagick
    ${INSTALL_DIR}/bin/pecl install https://pecl.php.net/get/imagick-3.7.0.tgz && \
        echo -e '[ImageMagick]\nextension = imagick.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#Install SourceGuardian
    mkdir -p ${TEMP_DIR}/sourceguardian && \
    curl -Lks http://www.sourceguardian.com/loaders/download/loaders.linux-x86_64.tar.gz | tar -xz -C ${TEMP_DIR}/sourceguardian/ && \
    cp ${TEMP_DIR}/sourceguardian/ixed.7.4.lin /usr/local/php/lib/php/20190902/ && \
    echo -e '[SourceGuardian]\nextension = ixed.7.4.lin\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#
        chmod +x -R /usr/local/php/lib/php/20190902/ && \
#Clean OS
        yum remove -y gcc gcc-c++ make autoconf && \
        yum clean all && \
        rm -rf ${TEMP_DIR} /tmp/*

ADD extension-so-file/* ${INSTALL_DIR}/lib/php/20190902/

RUN set -x && \
        chmod +x -R /usr/local/php/lib/php/20190902/ && \
        echo -e '[bz2]\nextension = bz2.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#       echo -e '[exif]\nextension = exif.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
        echo -e '[geoip]\nextension = geoip.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#       echo -e '[intl]\nextension = intl.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
        echo -e '[mcrypt]\nextension = mcrypt.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
        echo -e '[readline]\nextension = readline.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#       echo -e '[snmp]\nextension = snmp.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#       echo -e '[xsl]\nextension = xsl.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
#       echo -e '[zip]\nextension = zip.so\n' >> ${INSTALL_DIR}/etc/php.d/10-extension.ini && \
        echo

COPY entrypoint.sh /entrypoint.sh
ADD php-fpm.conf ${INSTALL_DIR}/etc/php-fpm.conf
ENV PATH=${INSTALL_DIR}/bin:${INSTALL_DIR}/sbin:$PATH

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
