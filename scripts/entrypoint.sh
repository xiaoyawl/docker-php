#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : entrypoint.sh
# @Desc     : 生成兼容配置，按参数启动 FPM 服务或执行指定命令。
# @Contact  : admin@dstw.com
set -Eeuo pipefail
enabled() { [[ ${1,,} == enable ]]; }
fail() { echo "配置错误：$*" >&2; exit 1; }
INSTALL_DIR=${INSTALL_DIR:-/usr/local/php}
export PHP_FPM_CONF=${PHP_FPM_CONF:-$INSTALL_DIR/etc/php-fpm.conf}
export PHP_FPM_PID=${PHP_FPM_PID:-$INSTALL_DIR/var/run/php-fpm.pid}
ini_dir=$INSTALL_DIR/etc/php.d
mkdir -p "$ini_dir" "$INSTALL_DIR/var/run" /data/wwwroot /data/wwwlogs/supervisor

if [[ -z ${MEM_LIMIT:-} ]]; then
    memory_bytes=$(awk '/MemTotal:/ {printf "%.0f", $2*1024}' /proc/meminfo)
    for limit_file in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
        if [[ -r $limit_file ]]; then
            limit=$(cat "$limit_file")
            if [[ $limit =~ ^[0-9]+$ ]] && (( limit > 0 && limit < memory_bytes )); then
                memory_bytes=$limit
            fi
        fi
    done
    memory_mib=$(( memory_bytes / 1024 / 1024 ))
    if (( memory_mib <= 640 )); then MEM_LIMIT=64
    elif (( memory_mib <= 1280 )); then MEM_LIMIT=128
    elif (( memory_mib <= 2500 )); then MEM_LIMIT=192
    elif (( memory_mib <= 3500 )); then MEM_LIMIT=256
    elif (( memory_mib <= 4500 )); then MEM_LIMIT=320
    elif (( memory_mib <= 8000 )); then MEM_LIMIT=384
    else MEM_LIMIT=448; fi
fi
[[ $MEM_LIMIT =~ ^[1-9][0-9]*$ || $MEM_LIMIT == -1 ]] || fail 'MEM_LIMIT 必须为 MiB 正整数或 -1'
if [[ $MEM_LIMIT == -1 ]]; then memory_value=-1; else memory_value=${MEM_LIMIT}M; fi
TIMEZONE=${TIMEZONE:-Asia/Shanghai}
POST_MAX_SIZE=${POST_MAX_SIZE:-100M}
UPLOAD_MAX_FILESIZE=${UPLOAD_MAX_FILESIZE:-50M}
MAX_EXECUTION_TIME=${MAX_EXECUTION_TIME:-5}
DISPLAY_ERROES=${DISPLAY_ERROES:-Off}
EXPOSE_PHP=${EXPOSE_PHP:-Off}
PHP_DISABLE_FUNCTIONS=${PHP_DISABLE_FUNCTIONS-passthru,exec,system,chroot,chgrp,chown,shell_exec,proc_open,proc_get_status,ini_alter,ini_restore,dl,openlog,syslog,readlink,symlink,popepassthru,stream_socket_server,fsocket,popen}
[[ $TIMEZONE =~ ^[A-Za-z0-9_+/-]+$ ]] || fail 'TIMEZONE 格式无效'
[[ $POST_MAX_SIZE =~ ^[0-9]+[KMGkmg]?$ ]] || fail 'POST_MAX_SIZE 格式无效'
[[ $UPLOAD_MAX_FILESIZE =~ ^[0-9]+[KMGkmg]?$ ]] || fail 'UPLOAD_MAX_FILESIZE 格式无效'
[[ $MAX_EXECUTION_TIME =~ ^[0-9]+$ ]] || fail 'MAX_EXECUTION_TIME 必须为非负整数'
[[ ${DISPLAY_ERROES,,} =~ ^(on|off)$ ]] || fail 'DISPLAY_ERROES 必须为 On 或 Off'
[[ ${EXPOSE_PHP,,} =~ ^(on|off)$ ]] || fail 'EXPOSE_PHP 必须为 On 或 Off'
[[ $PHP_DISABLE_FUNCTIONS =~ ^[A-Za-z0-9_,[:blank:]]*$ ]] || fail 'PHP_DISABLE_FUNCTIONS 格式无效'
if enabled "${PHP_INI_CONF:-enable}"; then
    cat > "$ini_dir/00-lookback-runtime.ini" <<EOF
memory_limit=$memory_value
output_buffering=On
cgi.fix_pathinfo=0
short_open_tag=On
expose_php=$EXPOSE_PHP
request_order=CGP
date.timezone=$TIMEZONE
post_max_size=$POST_MAX_SIZE
upload_max_filesize=$UPLOAD_MAX_FILESIZE
max_execution_time=$MAX_EXECUTION_TIME
disable_functions=$PHP_DISABLE_FUNCTIONS
display_errors=$DISPLAY_ERROES
sendmail_path=/usr/sbin/sendmail -t -i
EOF
else
    rm -f "$ini_dir/00-lookback-runtime.ini"
fi

# 扩展、Loader 与 OPcache 的开关由构建时生成的清单驱动，脚本不写死版本信息。
# 清单字段：类别|开关|类型|加载值|额外 ini（\x1f 分隔）|预加载库|互斥开关
extension_list=$INSTALL_DIR/share/lookback/extensions.list
[[ -r $extension_list ]] || fail "扩展开关清单不存在：$extension_list"
xdebug_ini=$ini_dir/50-lookback-xdebug.ini

# ionCube 与 Xdebug 都会接管引擎执行流程，不能同时加载；同时检查用户自建 ini。
if enabled "${IONCUBE:-disable}" && enabled "${XDEBUG:-disable}"; then
    fail 'ionCube 与 Xdebug 不可同时启用，请分别运行对应容器'
fi
for config_file in "$INSTALL_DIR/etc/php.ini" "$ini_dir"/*.ini; do
    [[ -f $config_file ]] || continue
    [[ $config_file != "$ini_dir/20-lookback-ioncube.ini" && $config_file != "$xdebug_ini" ]] || continue
    if enabled "${IONCUBE:-disable}" && grep -Eiq '^[[:blank:]]*zend_extension[[:blank:]]*=[^;]*xdebug' "$config_file"; then
        fail "ionCube 与用户 Xdebug 配置冲突：$config_file"
    fi
    if enabled "${XDEBUG:-disable}" && grep -Eiq '^[[:blank:]]*zend_extension[[:blank:]]*=[^;]*ioncube' "$config_file"; then
        fail "Xdebug 与用户 ionCube 配置冲突：$config_file"
    fi
done

write_ini() {
    # 参数：目标文件、加载指令、加载值、额外 ini（\x1f 分隔）
    local target=$1 directive=$2 value=$3 extra=$4
    {
        [[ -z $value ]] || printf '%s=%s\n' "$directive" "$value"
        [[ -z $extra ]] || tr '\037' '\n' <<< "$extra"
    } > "$target"
}

while IFS='|' read -r category switch kind value extra preload conflicts; do
    [[ -n $category ]] || continue
    directive=extension
    [[ $kind != zend ]] || directive=zend_extension
    case $category in
        loader)
            # 官方 Loader 默认关闭；20- 前缀保证先于 OPcache 加载。
            target=$ini_dir/20-lookback-${switch,,}.ini
            if enabled "${!switch:-disable}"; then
                [[ -r $value ]] || fail "$switch 对应的 Loader 不存在：$value"
                if [[ -n $preload ]]; then
                    [[ -r $preload ]] || fail "$switch 需要的兼容库不存在：$preload"
                    export LD_PRELOAD="$preload${LD_PRELOAD:+:$LD_PRELOAD}"
                fi
                write_ini "$target" "$directive" "$value" ''
            else
                rm -f "$target"
            fi
            ;;
        opcache)
            # OPcache 默认启用；PHP 8.5 起为内置模块，只能通过 opcache.enable 关闭。
            target=$ini_dir/50-lookback-opcache.ini
            [[ $value != builtin ]] || value=''
            if enabled "${OPCACHE:-enable}"; then
                opcache_memory=$MEM_LIMIT
                [[ $opcache_memory != -1 ]] || opcache_memory=128
                settings=$(printf '%s\037' opcache.enable=1 "opcache.memory_consumption=$opcache_memory" \
                    opcache.interned_strings_buffer=8 opcache.max_accelerated_files=4000 \
                    opcache.revalidate_freq=60 opcache.save_comments=0 opcache.fast_shutdown=1 opcache.enable_cli=1)
                write_ini "$target" "$directive" "$value" "${settings%$'\037'}"
            elif [[ -z $value ]]; then
                write_ini "$target" "$directive" '' $'opcache.enable=0\037opcache.enable_cli=0'
            else
                rm -f "$target"
            fi
            ;;
        extension)
            if [[ $switch == XDEBUG ]]; then
                target=$xdebug_ini
                if ! enabled "${XDEBUG:-disable}" || ! enabled "${XDEBUG_DEFAULT_CONF:-enable}"; then
                    rm -f "$target"
                    continue
                fi
                xdebug_host=${XDEBUG_REMOTE_HOST:-localhost}
                xdebug_port=${XDEBUG_REMOTE_PORT:-9900}
                [[ $xdebug_host =~ ^[A-Za-z0-9_.:-]+$ ]] || fail 'XDEBUG_REMOTE_HOST 格式无效'
                [[ $xdebug_port =~ ^[0-9]+$ ]] && (( xdebug_port > 0 && xdebug_port < 65536 )) || fail 'XDEBUG_REMOTE_PORT 超出范围'
                extra=${extra//\{host\}/$xdebug_host}
                extra=${extra//\{port\}/$xdebug_port}
                write_ini "$target" "$directive" "$value" "$extra"
                continue
            fi
            target=$ini_dir/50-lookback-${value%.so}.ini
            if enabled "${!switch:-disable}"; then
                write_ini "$target" "$directive" "$value" "$extra"
            else
                rm -f "$target"
            fi
            ;;
    esac
done < "$extension_list"

# 项目级全部扩展开关；当前版本清单中没有的开关一旦开启即报错，避免静默忽略。
for switch in APCU EVENT FFI HPROSE IMAGICK IONCUBE MEMCACHE MONGO MONGODB REDIS SOURCEGUARDIAN SWOOLE XDEBUG ZSTD; do
    enabled "${!switch:-disable}" || continue
    grep -q "^[a-z]*|$switch|" "$extension_list" || fail "$switch：PHP $(php -r 'echo PHP_VERSION;') 不提供该扩展，原因见镜像仓库 README"
done

# XDEBUG_DEFAULT_CONF=disable 时由用户挂载 Xdebug 配置，启动前确认确实可用。
if enabled "${XDEBUG:-disable}" && ! enabled "${XDEBUG_DEFAULT_CONF:-enable}"; then
    php -m | grep -qi '^xdebug$' || fail 'XDEBUG_DEFAULT_CONF=disable 时必须挂载可用的 Xdebug 配置'
fi

if [[ $# == 0 ]]; then set -- php-fpm; fi
if [[ $1 == -* ]]; then set -- php-fpm "$@"; fi
if [[ $1 == php-fpm && $# == 1 ]]; then
    if enabled "${PHP_FPM_CONF_DEF:-enable}"; then
        [[ -r $PHP_FPM_CONF ]] || fail "FPM 配置不存在：$PHP_FPM_CONF"
    fi
    php-fpm -t -y "$PHP_FPM_CONF" --pid "$PHP_FPM_PID"
    echo '配置检查通过，启动 PHP-FPM 与定时任务'
    exec /usr/bin/supervisord -c /etc/supervisord.conf
fi
exec "$@"
