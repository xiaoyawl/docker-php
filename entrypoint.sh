#!/bin/bash
#########################################################################
# File Name: entrypoint.sh
# Author: LookBack
# Email: admin#dwhd.org
# Version:
# Created Time: 2016年08月13日 星期六 00时50分04秒
#########################################################################

set -e

[ "${1:0:1}" = '-' ] && set -- php-fpm "$@"

mem_sum() {
	Mem=`free -m | awk '/Mem:/{print $2}'`
	Swap=`free -m | awk '/Swap:/{print $2}'`

	if [ $Mem -le 640 ];then
		MEM_LIMIT=64
	elif [ $Mem -gt 640 -a $Mem -le 1280 ];then
		MEM_LIMIT=128
	elif [ $Mem -gt 1280 -a $Mem -le 2500 ];then
		MEM_LIMIT=192
	elif [ $Mem -gt 2500 -a $Mem -le 3500 ];then
		MEM_LIMIT=256
	elif [ $Mem -gt 3500 -a $Mem -le 4500 ];then
		MEM_LIMIT=320
	elif [ $Mem -gt 4500 -a $Mem -le 8000 ];then
		MEM_LIMIT=384
	elif [ $Mem -gt 8000 ];then
		MEM_LIMIT=448
	fi
}

[ -d /data/wwwroot ] || mkdir -p /data/wwwroot
chown -R www.www /data/wwwroot
[ -z "${MEM_LIMIT}" ] && mem_sum
[ "$EXPOSE_PHP" != "On" ] && EXPOSE_PHP=Off

if [[ "$MEMCACHE" =~ ^[yY][eE][sS]$ ]]; then
	echo 'extension=memcache.so' > ${INSTALL_DIR}/etc/php.d/ext-memcache.ini
	cat > ${INSTALL_DIR}/etc/php.d/ext-memcached.ini <<-EOF
		extension=memcached.so
		memcached.use_sasl=1
	EOF
fi

if [[ "$REDIS" =~ ^[yY][eE][sS]$ ]]; then
	cat > ${INSTALL_DIR}/etc/php.d/ext-redis.ini <<-EOF
		[redis]
		extension=redis.so
	EOF
fi

if [[ "${SWOOLE}" =~ ^[yY][eE][sS]$ ]]; then
	echo 'extension=swoole.so' > ${INSTALL_DIR}/etc/php.d/ext-swoole.ini
fi
XDEBUG=${XDEBUG:-disable}
XDEBUG_REMOTE_HOST=${XDEBUG_REMOTE_HOST:-localhost}
XDEBUG_REMOTE_PORT=${XDEBUG_REMOTE_PORT:-9900}


TIMEZONE=${TIMEZONE-Asia/Shanghai}
POST_MAX_SIZE=${POST_MAX_SIZE-100M}
UPLOAD_MAX_FILESIZE=${UPLOAD_MAX_FILESIZE-50M}
MAX_EXECUTION_TIME=${MAX_EXECUTION_TIME-5}
PHP_FPM_CONF=${PHP_FPM_CONF-${INSTALL_DIR}/etc/php-fpm.conf}
PHP_FPM_PID=${PHP_FPM_PID-${INSTALL_DIR}/var/run/php-fpm.pid}
PHP_DISABLE_FUNCTIONS=${PHP_DISABLE_FUNCTIONS:-passthru,exec,system,chroot,chgrp,chown,shell_exec,proc_open,proc_get_status,ini_alter,ini_restore,dl,openlog,syslog,readlink,symlink,popepassthru,stream_socket_server,fsocket,popen}
DISPLAY_ERROES=${DISPLAY_ERROES:-Off}

set -- "$@" -F
set -- "$@" -y ${PHP_FPM_CONF}
set -- "$@" --pid ${PHP_FPM_PID}

sed -i "s@\$HOSTNAME@$HOSTNAME@" ${INSTALL_DIR}/etc/php-fpm.conf

sed -i "s@^memory_limit.*@memory_limit = ${MEM_LIMIT}M@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^output_buffering =@output_buffering = On\noutput_buffering =@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^;cgi.fix_pathinfo.*@cgi.fix_pathinfo=0@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^short_open_tag = Off@short_open_tag = On@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^expose_php = On@expose_php = ${EXPOSE_PHP}@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^request_order.*@request_order = \"CGP\"@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^;date.timezone.*@date.timezone = ${TIMEZONE}@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^post_max_size.*@post_max_size = ${POST_MAX_SIZE}@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^upload_max_filesize.*@upload_max_filesize = ${UPLOAD_MAX_FILESIZE}@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^max_execution_time.*@max_execution_time = ${MAX_EXECUTION_TIME}@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^disable_functions.*@disable_functions = ${PHP_DISABLE_FUNCTIONS}@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^;sendmail_path.*@sendmail_path = /usr/sbin/sendmail -t -i@" ${INSTALL_DIR}/etc/php.ini
sed -i "s@^display_errors.*@display_errors = ${DISPLAY_ERROES}@" ${INSTALL_DIR}/etc/php.ini

cat > ${INSTALL_DIR}/etc/php.d/ext-opcache.ini <<-EOF
	[opcache]
	zend_extension=opcache.so
	opcache.enable=1
	opcache.memory_consumption=$MEM_LIMIT
	opcache.interned_strings_buffer=8
	opcache.max_accelerated_files=4000
	opcache.revalidate_freq=60
	opcache.save_comments=0
	opcache.fast_shutdown=1
	opcache.enable_cli=1
	;opcache.optimization_level=0
EOF

if [[ "${XDEBUG}" =~ [eE][nN][aA][bB][lL][eE] ]]; then
	cat >> ${INSTALL_DIR}/etc/php.d/ext-xdebug.ini <<-EOF
		zend_extension="xdebug.so"
		xdebug.remote_enable = on
		xdebug.remote_handler = "dbgp"
		;官方設明文件中有提到，從xdebug 2.1以後的版本只支援"dbgp"這個協定
		xdebug.remote_host = "${XDEBUG_REMOTE_HOST}"
		xdebug.remote_port = $XDEBUG_REMOTE_PORT
		xdebug.remote_connect_back=1
		xdebug.auto_trace = on
		xdebug.auto_profile = on
		xdebug.collect_params = on
		xdebug.collect_return = on
		xdebug.profiler_enable = on
		xdebug.trace_output_dir = "/tmp"
		xdebug.profiler_output_dir = "/tmp"
		xdebug.dump.GET = *
		xdebug.dump.POST = *
		xdebug.dump.COOKIE = *
		xdebug.dump.SESSION = *
		xdebug.var_display_max_data = 4056
		xdebug.var_display_max_depth = 5
	EOF
fi
exec "$@"
