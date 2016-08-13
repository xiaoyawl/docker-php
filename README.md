# docker-php

# Docker 安装
```bash
curl -Lks https://get.docker.com/ | sh
```

## 可用变量说明

| 变量名 | 默认值 | 描述 |
| -------- | ------------- | ----------- |
| MEM_LIMIT | 自动计算 | memory_limit的值 |
| EXPOSE_PHP | Off  | 可选值Off或者On |
| MEMCACHE | No | PHP Memcache 插件开关 |
| REDIS | No | PHP Redis 插件开关 |
| TIMEZONE | Asia/Shanghai | PHP 时区 |
| POST_MAX_SIZE | 100M | PHP post_max_size 值 |
| UPLOAD_MAX_FILESIZE | 50M | PHP upload_max_filesize 值 |
| MAX_EXECUTION_TIME | 5 | PHP max_execution_time 值 |
| PHP_FPM_CONF | ${INSTALL_DIR}/etc/php-fpm.conf | PHP-FPM 配置文件路径 |
| PHP_FPM_PID | ${INSTALL_DIR}/var/run/php-fpm.pid | PHP-PID 路径 |
| PHP_DISABLE_FUNCTIONS | 见注1 | PHP disable_functions 值 |

```bash
# 注1: PHP_DISABLE_FUNCTIONS=passthru,exec,system,chroot,chgrp,chown,shell_exec,proc_open,proc_get_status,ini_alter,ini_restore,dl,openlog,syslog,readlink,symlink,popepassthru,stream_socket_server,fsocket,popen
```

