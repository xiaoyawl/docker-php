# syntax=docker/dockerfile:1
# ============================================================================
# 项目：LookBack PHP Alpine 镜像（全版本统一模板）
# 维护者：LookBack <mondeolove@gmail.com>
# 仓库：https://git.dwhd.org/lookback/docker-php
# 用途：提供 PHP CLI/FPM/CGI、常用数据库与缓存扩展、官方 Loader；当前仅构建 amd64。
# 版本：PHP 版本、扩展、Loader 与 Swoole 变体见 config/extensions.json；
#       configure 参数见 config/php-configure.txt；依赖包见 config/*-packages.txt。
# 安全范围：可信安全回补、现代依赖适配与 CA 更新；EOL 版本不等于获得官方安全支持。
# 构建位置：指定远程 Linux 节点，由 scripts/build-image.sh 传入版本与变体参数。
# ============================================================================

# 同时固定标签与 OCI 索引摘要，两个阶段使用同一系统基线。
# 更新摘要前必须重新核对清单、系统包和完整回归结果。
ARG BASE_IMAGE=benyoo/alpine:3.24.20260615@sha256:7b08066d86153fff7c557beb57cbe20f07539f36b19cced8907d8d453ac45d9d

# ---------- 第一阶段：可信源码校验、PHP 内核与 PECL 扩展构建 ----------
FROM ${BASE_IMAGE} AS build

# 基础镜像继承登录 Shell；显式使用非登录 Bash，避免工作目录被切回 /root。
SHELL ["/bin/bash", "-c"]
ARG BUILD_JOBS=2
# 镜像变体后缀（如 -swoole6），无后缀时为 -；决定编译哪个 Swoole 版本。
ARG VARIANT_SUFFIX=-

# 编译工具、校验工具及各扩展开发包只安装在构建阶段，包清单见 config/build-packages.txt。
# apk 使用基础镜像的 v3.24 软件源；实际解析版本记录在镜像 /usr/local/php/build-apk-packages.txt。
COPY config/build-packages.txt /tmp/build-packages.txt
RUN apk upgrade --no-cache \
    && apk add --no-cache $(sed 's/#.*//' /tmp/build-packages.txt) \
    && rm /tmp/build-packages.txt

WORKDIR /build

# 系统 gd-2.3.3-r10 缺少上游旋转修复（调色板图像 180° 释放原图、最近邻旋转空指针），
# 自行编译带两项上游补丁的 libgd 到 /opt/libgd，编译选项与 Alpine 一致；PHP 通过 rpath 链接。
COPY libgd ./libgd
RUN --mount=type=cache,id=lookback-php-sources,target=/build/.cache/sources \
    BUILD_JOBS=${BUILD_JOBS} bash libgd/build-libgd.sh /build/libgd /build/.cache/sources

# 验证 Surý 签名链（InRelease → Sources → 补丁包摘要），校验全部源码与补丁 SHA-256，
# 按 patches/series 固定顺序严格应用补丁（失败立即中止），再编译 PHP 内核。
COPY sources.lock.json ./
COPY config ./config
COPY patches ./patches
COPY provenance ./provenance
COPY scripts/manifest.py scripts/verify-provenance.py scripts/prepare-sources.py scripts/build-php.sh ./scripts/
RUN --mount=type=cache,id=lookback-php-sources,target=/build/.cache/sources \
    python3 scripts/verify-provenance.py && python3 scripts/prepare-sources.py \
    && BUILD_JOBS=${BUILD_JOBS} bash scripts/build-php.sh

# 单独构建 PECL 扩展与 Loader，复用已验证的 PHP 内核构建层；
# 通过 ELF 依赖分析生成最小运行依赖清单，并生成入口脚本使用的扩展开关清单。
COPY extension-patches.lock.json ./
COPY extension-patches ./extension-patches
COPY scripts/build-extensions.sh ./scripts/
RUN VARIANT_SUFFIX=${VARIANT_SUFFIX} BUILD_JOBS=${BUILD_JOBS} bash scripts/build-extensions.sh

# 系统 tzdata 不会替换 PHP 内嵌时区库，单独构建官方时区数据库并默认加载。
COPY timezonedb.lock.json ./
COPY scripts/build-timezonedb.sh ./scripts/
RUN BUILD_JOBS=${BUILD_JOBS} bash scripts/build-timezonedb.sh

# ---------- 第二阶段：仅复制 PHP、兼容库、配置和必要运行依赖 ----------
FROM ${BASE_IMAGE} AS runtime
ARG BUILD_DATE
ARG PHP_VERSION
ARG IMAGE_TAG
SHELL ["/bin/bash", "-c"]

# 使用 OCI 元数据描述版本，避免将自有回补伪装为 PHP 上游新版本。
LABEL org.opencontainers.image.title="LookBack PHP ${PHP_VERSION} 镜像" \
    org.opencontainers.image.authors="LookBack <mondeolove@gmail.com>" \
    org.opencontainers.image.source="https://git.dwhd.org/lookback/docker-php" \
    org.opencontainers.image.version="${IMAGE_TAG}" \
    org.opencontainers.image.description="PHP ${PHP_VERSION}，可信安全回补、CA 更新、常用扩展与官方 Loader；amd64"

# 保留历史安装目录与命令路径；GNU libiconv（如有）使用独立库目录，无全局 LD_PRELOAD。
ENV INSTALL_DIR=/usr/local/php \
    PATH=/usr/local/php/bin:/usr/local/php/sbin:$PATH \
    LD_LIBRARY_PATH=/opt/libiconv/lib \
    TERM=linux \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/certs

COPY --from=build /usr/local/php /usr/local/php
COPY --from=build /opt/libiconv /opt/libiconv
COPY --from=build /opt/libgd /opt/libgd
# ionCube、SourceGuardian 为官方闭源 Loader，仅按需加载，保留原始文件名和许可。
COPY --from=build /usr/local/ioncube /usr/local/ioncube
COPY --from=build /usr/local/sourceguardian /usr/local/sourceguardian
# Composer 固定版本，摘要见 sources.lock.json；由 /usr/local/bin/composer 包装启动。
COPY --from=build /usr/local/lib/composer /usr/local/lib/composer
COPY --from=build /build/runtime-deps.txt /tmp/php-runtime-deps.txt
COPY config/runtime-packages.txt /tmp/runtime-packages.txt

# 与构建层同步更新 v3.24 系统库，再安装 ELF 扫描得到的动态库依赖与 config/runtime-packages.txt。
# FPM worker 保留 UID/GID 400；Supervisor/crond 由容器主进程管理。
# 仅设置镜像内新建目录权限，启动时不递归修改宿主挂载文件。
RUN apk upgrade --no-cache \
    && apk add --no-cache $(cat /tmp/php-runtime-deps.txt) $(sed 's/#.*//' /tmp/runtime-packages.txt) \
    && update-ca-certificates \
    && addgroup -g 400 -S www \
    && adduser -u 400 -S -H -s /sbin/nologin -g PHP -G www www \
    && mkdir -p /data/wwwroot /data/wwwlogs/supervisor /usr/local/php/etc/php.d /usr/local/php/var/run /usr/local/php/var/log \
    && chown www:www /data/wwwroot \
    && mkdir -p /usr/local/share/php-build \
    && apk info -v ca-certificates > /usr/local/share/php-build/ca-packages.txt \
    && sha256sum /etc/ssl/certs/ca-certificates.crt > /usr/local/share/php-build/ca-bundle.sha256 \
    && rm /tmp/php-runtime-deps.txt /tmp/runtime-packages.txt

# 默认 FPM/Supervisor 配置、安全显示配置与 Composer 包装脚本。
# 回补在源码层禁用 session.upload_progress，普通文件上传仍保留。
COPY config/php-fpm.conf /usr/local/php/etc/php-fpm.conf
COPY config/security.ini /usr/local/php/etc/php.d/10-lookback-security.ini
COPY config/supervisord.conf /etc/supervisord.conf
COPY config/composer.sh /usr/local/bin/composer
COPY scripts/entrypoint.sh /entrypoint.sh

# 在运行镜像内保留来源锁、版本清单和补丁序列，便于按镜像摘要追溯构建内容。
COPY sources.lock.json /usr/local/share/php-build/sources.lock.json
COPY config/extensions.json /usr/local/share/php-build/extensions.json
COPY libgd/libgd.lock.json /usr/local/share/php-build/libgd.lock.json
COPY timezonedb.lock.json /usr/local/share/php-build/timezonedb.lock.json
COPY extension-patches.lock.json /usr/local/share/php-build/extension-patches.lock.json
COPY patches/series /usr/local/share/php-build/patches.series
RUN chmod 0755 /entrypoint.sh /usr/local/bin/composer

# 默认启动 FPM 与 crond；显式传入 php 等命令时由入口脚本直接执行。
# 9000 是 FastCGI 接口，EXPOSE 不发布宿主端口；应接入受控业务网络。
# SIGTERM 交给 Supervisor，按配置顺序停止 FPM 与 crond。
WORKDIR /data/wwwroot
EXPOSE 9000
STOPSIGNAL SIGTERM
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
