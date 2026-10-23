#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# @Time     : 2026-10-22
# @Author   : LookBack
# @Project  : docker-php
# @File     : start-services.sh
# @Desc     : 仅在隔离集成测试容器内启动临时数据库与缓存。
# @Contact  : admin@dstw.com
set -Eeuo pipefail
test_password=${PHP_TEST_DB_PASSWORD:?缺少临时测试数据库口令环境变量}
[[ $test_password =~ ^[a-f0-9]{32}$ ]] || { echo '临时数据库口令格式无效' >&2; exit 1; }
mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld
mariadb-install-db --user=mysql --datadir=/var/lib/mysql --auth-root-authentication-method=normal --skip-test-db >/dev/null
mariadbd --user=mysql --datadir=/var/lib/mysql --skip-networking=0 --bind-address=0.0.0.0 \
    --innodb-buffer-pool-size=32M --skip-log-bin &
database_pid=$!
for _ in {1..60}; do
    if mariadb-admin --protocol=socket -uroot ping --silent >/dev/null 2>&1; then break; fi
    sleep 1
done
# 口令由测试程序临时生成，通过环境变量传入，仅在标准输入中交给数据库。
mariadb --protocol=socket -uroot <<SQL
CREATE DATABASE php_test CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'php_test'@'%' IDENTIFIED BY '${test_password}';
GRANT ALL ON php_test.* TO 'php_test'@'%';
SQL
redis-server --bind 0.0.0.0 --protected-mode no --save '' --appendonly no &
redis_pid=$!
memcached -u nobody -l 0.0.0.0 -m 16 &
cache_pid=$!
mkdir -p /tmp/postgresql-data /run/postgresql
chown postgres:postgres /tmp/postgresql-data /run/postgresql
su postgres -s /bin/sh -c 'initdb -D /tmp/postgresql-data --auth-local=trust --auth-host=scram-sha-256 --encoding=UTF8 --locale=C' >/dev/null
# 仅用于无公网出口、无宿主端口映射的一次性测试网络，仍要求随机口令认证。
printf '\nhost all all 0.0.0.0/0 scram-sha-256\n' >> /tmp/postgresql-data/pg_hba.conf
su postgres -s /bin/sh -c 'exec postgres -D /tmp/postgresql-data -h 0.0.0.0 -c shared_buffers=16MB -c max_connections=20' &
postgres_pid=$!
for _ in {1..60}; do
    if su postgres -s /bin/sh -c 'pg_isready -q'; then break; fi
    sleep 1
done
su postgres -s /bin/sh -c 'psql -v ON_ERROR_STOP=1' <<SQL
CREATE USER php_test WITH PASSWORD '${test_password}';
CREATE DATABASE php_test OWNER php_test;
SQL
trap 'kill "$database_pid" "$redis_pid" "$cache_pid" "$postgres_pid" 2>/dev/null || true; wait || true' EXIT
trap 'exit 0' TERM INT
echo '临时数据库与缓存已就绪'
wait -n "$database_pid" "$redis_pid" "$cache_pid" "$postgres_pid"
