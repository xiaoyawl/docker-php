# LookBack PHP 5.6.40 镜像

![PHP](https://img.shields.io/badge/PHP-5.6.40-777BB4)
![Alpine](https://img.shields.io/badge/Alpine-3.24-0D597F)
![架构](https://img.shields.io/badge/架构-amd64%20%7C%20arm64-blue)
![维护状态](https://img.shields.io/badge/上游-EOL-B0332B)

本分支 `php-5.6.40` 构建 `benyoo/php-alpine:5.6.40.<构建日>`：基于 Alpine 3.24 从源码编译 PHP 5.6.40，纳入可信安全回补、现代依赖适配、常用数据库与缓存扩展、官方 Loader，并在构建时更新 CA 信任库。

- 仓库：<https://git.dwhd.org/lookback/docker-php>（每个 PHP 版本一个分支，命名 `php-<版本>`，`master` 对应 8.5.12）
- 镜像：<https://hub.docker.com/r/benyoo/php-alpine>
- PHP 5.6 已停止上游维护（EOL）。本镜像只回补公开的安全修复，**不等于获得官方安全支持**。

## 快速使用

```bash
# 默认启动 PHP-FPM（9000 端口）与 crond，由 Supervisor 管理
docker run -d --name php56 -v /data/wwwroot:/data/wwwroot benyoo/php-alpine:5.6.40.<构建日>

# 按需开启扩展（第三方扩展与 Loader 默认全部关闭）
docker run -d -e REDIS=enable -e MEMCACHE=enable -e SWOOLE=enable -e IONCUBE=enable \
    benyoo/php-alpine:5.6.40.<构建日>

# 执行一次性命令（不启动 FPM）
docker run --rm benyoo/php-alpine:5.6.40.<构建日> php -v
docker run --rm -v "$PWD":/data/wwwroot benyoo/php-alpine:5.6.40.<构建日> composer install
```

## 从线上镜像迁移

线上 5.6 有三个镜像（均为 Alpine 3.5、PHP 内置 GD），切换到本镜像时注意：

| 项目 | 线上 | 本镜像 | 迁移动作 |
|---|---|---|---|
| 镜像与 PHP 版本 | `benyoo/php:5.6.30.dt`（5.6.30）、`benyoo/php:5.6.30.dt.redis.4.3.0`（**实际为 5.6.33**）、`benyoo/php:5.6.31.dt`（5.6.31） | 5.6.40 | — |
| Redis | 2.2.8（5.6.30.dt、5.6.31.dt）/ 4.3.0（redis.4.3.0） | 4.3.0 | 原用 2.2.8 的业务跨大版本，需回归；4.3.0 接口与现网基线一致 |
| Swoole | 1.9.4 | 2.0.11 | 有两处行为差异，见“已知问题”；不兼容时可改用 1.10.5 |
| 旧 mongo 驱动 | 1.6.16（仅 redis.4.3.0 镜像），`MONGO=enable` | 1.6.16，开关相同 | 服务端须为 MongoDB 5.0 及以下 |
| mongodb 新驱动 | 1.5.5（仅 redis.4.3.0 镜像） | 1.7.5 | 同主版本升级，按需开启 |
| memcache / memcached / Xdebug | 3.0.8 / 2.2.0 / 2.5.0 | 3.0.8 / 2.2.0 / 2.5.5 | — |
| iconv | 5.6.30.dt 的 iconv.so 缺失，启动告警 | 内置 GNU libiconv 1.18 | 无需处理 |
| GD | PHP 内置 GD | 补丁版外部 libgd 2.3.3 | JIS 映射日文字体不可用；字体度量、缩放尺寸可能相差 1–2 像素 |
| TLS | 旧 OpenSSL | OpenSSL 3.5.9 | `tls://` 仍为 TLS 1.0 语义会被拒绝，改用 `tlsv1.2://` |
| APCu / Hprose / Imagick / SourceGuardian / ionCube | 无 | 新增，默认关闭 | 按需开启 |
| git / Composer | 无 | 新增 | 无需处理 |

环境变量开关名与现网一致（如 `REDIS`、`MEMCACHE`、`SWOOLE`、`XDEBUG`、`MONGO`），保留历史拼写 `DISPLAY_ERROES`。

## 版本明细

### 系统与核心组件

| 组件 | 版本 | 说明 |
|---|---|---|
| 基础镜像 | `benyoo/alpine:3.24.20260615` | 固定 OCI 索引摘要 `sha256:7b08066d…ac45d9d`，构建与运行两阶段相同 |
| PHP | 5.6.40（NTS） | CLI、FPM、CGI；安装目录 `/usr/local/php` |
| OpenSSL | 3.5.9 | 系统库；PHP 已打 OpenSSL 1.1 / 3.0 兼容补丁 |
| cURL | 8.22.0 | 系统库 |
| ICU | 78.1 | intl 扩展使用 |
| libxml2 | 2.13.9 | 系统库 |
| SQLite | 3.53.4 | 系统库 |
| PCRE | 8.45（系统） | 不使用 PHP 内置的旧版 PCRE |
| Oniguruma | 系统库 | mbregex 使用，补丁 0405 适配其新接口 |
| libgd | 2.3.3 + 两项上游修复 | 自行编译到 `/opt/libgd`，见“适配改动” |
| GNU libiconv | 1.18 | 安装到 `/opt/libiconv`，提供完整的 GBK / GB18030 转换 |
| 时区数据库 | timezonedb 2026.5 | 官方 PECL 时区库，默认加载，不依赖系统 tzdata |
| CA 证书包 | ca-certificates（构建时安装并执行 `update-ca-certificates`） | PHP OpenSSL、cURL 与 `SSL_CERT_FILE` 统一使用 `/etc/ssl/certs/ca-certificates.crt` |
| Composer | 2.2.30（LTS） | 2.2 是支持 PHP 5.3–7.1 的长期支持版 |
| git | 2.54.0 | 含 ssh 客户端，供 Composer 拉取源码依赖 |

镜像内 `/usr/local/share/php-build/` 保存了来源锁、扩展清单、补丁序列与 CA 摘要，`/usr/local/php/build-apk-packages.txt` 保存了构建时全部 apk 包版本。

### 原生扩展

默认加载（71 个模块，完整清单见 `config/extensions.json` 的 `native_modules`）：

bcmath、bz2、calendar、ctype、curl、date、dba（gdbm / db4 / cdb / inifile / flatfile）、dom、enchant、ereg、exif、fileinfo、filter、ftp、gd、gettext、gmp、hash、iconv、imap、intl、json、ldap、libxml、mbstring、mcrypt、mhash、mssql、mysql、mysqli、mysqlnd、odbc、openssl、pcntl、pcre、PDO（dblib / mysql / odbc / pgsql / sqlite）、pgsql、Phar、posix、pspell、readline、Reflection、session、shmop、SimpleXML、snmp、soap、sockets、SPL、sqlite3、standard、sybase_ct、sysvmsg、sysvsem、sysvshm、tidy、tokenizer、wddx、xml、xmlreader、xmlrpc、xmlwriter、xsl、zip、zlib，以及默认开启的 OPcache。

configure 参数见 [`config/php-configure.txt`](config/php-configure.txt)。

### 可选扩展与 Loader

全部默认关闭，通过环境变量开启（值为 `enable`）。

| 扩展 | 版本 | 开关 | 说明 |
|---|---|---|---|
| redis | 4.3.0 | `REDIS` | 与现网同版；启用 Session 处理，不引入 igbinary / LZF |
| memcache | 3.0.8 | `MEMCACHE` | PHP 5 最后版本 |
| memcached | 2.2.0 | `MEMCACHE` | 与 memcache 同一开关；启用 SASL |
| mongodb（新驱动） | 1.7.5 | `MONGODB` | 链接系统 libmongoc / libbson，不编译捆绑的旧 C 驱动 |
| mongo（旧驱动） | 1.6.16 | `MONGO` | 现网 `MongoClient` 驱动；**只能连接 MongoDB 5.0 及以下** |
| swoole | 2.0.11 | `SWOOLE` | 支持 PHP 5.6 的最高版本；保持 `swoole.use_namespace=Off` 旧类名 |
| xdebug | 2.5.5 | `XDEBUG` | 与 ionCube 互斥 |
| apcu | 4.0.11 | `APCU` | APCu 4.x 是支持 PHP 5.6 的最终版本 |
| event | 3.1.6 | `EVENT` | 链接系统 libevent |
| zstd | 0.11.0 | `ZSTD` | 链接系统 libzstd |
| imagick | 3.8.1 | `IMAGICK` | 运行镜像含 imagemagick 格式模块 |
| hprose | 1.8.0 | `HPROSE` | 上游最终版本 |
| ionCube Loader | 15.5.1 | `IONCUBE` | 官方 glibc 版，启用时预加载 gcompat；与 Xdebug 互斥 |
| SourceGuardian Loader | 17.0.0 | `SOURCEGUARDIAN` | 官方 glibc 版，依赖 gcompat 与 libudev-zero；仅 amd64（官方无 PHP 5.6 的 aarch64 版），arm64 开启即报错退出 |

扩展的版本、编译参数与开关统一定义在 [`config/extensions.json`](config/extensions.json)，源码摘要见 [`sources.lock.json`](sources.lock.json)。

本版本不提供以下开关，开启时容器会报错退出，不会静默忽略：

| 开关 | 原因 |
|---|---|
| `FFI` | FFI 是 PHP 7.4 起的原生扩展，PHP 5.6 没有 |

## 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `MEM_LIMIT` | 按容器内存自动计算 | PHP `memory_limit`（MiB），识别 cgroup 限额；`-1` 为不限 |
| `TIMEZONE` | `Asia/Shanghai` | `date.timezone` |
| `POST_MAX_SIZE` | `100M` | |
| `UPLOAD_MAX_FILESIZE` | `50M` | |
| `MAX_EXECUTION_TIME` | `5` | 秒 |
| `DISPLAY_ERROES` | `Off` | 保留历史拼写 |
| `EXPOSE_PHP` | `Off` | |
| `PHP_DISABLE_FUNCTIONS` | `passthru,exec,system,…` | 默认禁用的危险函数；`composer` 命令不受影响 |
| `PHP_INI_CONF` | `enable` | `disable` 时不生成运行时 ini，完全使用挂载配置 |
| `PHP_FPM_CONF` / `PHP_FPM_PID` / `PHP_FPM_CONF_DEF` | 内置路径 / `enable` | 指定 FPM 配置文件与 PID 文件 |
| `OPCACHE` | `enable` | 设为 `disable` 关闭 OPcache |
| `XDEBUG_DEFAULT_CONF` | `enable` | `disable` 时由用户挂载 Xdebug 配置 |
| `XDEBUG_REMOTE_HOST` / `XDEBUG_REMOTE_PORT` | `localhost` / `9900` | Xdebug 远程调试地址 |
| 扩展开关 | `disable` | 见上表 |

## 安全回补

补丁序列见 [`patches/series`](patches/series)，共 180 项，按顺序严格应用：任何补丁无法干净应用或没有实际改动文件，构建立即中止，不允许模糊匹配。补丁数量不等于漏洞数量。

- **来源**：Debian 维护者 Ondřej Surý 的 PHP 5.6 源码包（`php5.6_5.6.40-104`）。构建时验证其签名链：InRelease 签名 → Sources 索引 → 补丁包摘要。另有本地移植的现代安全修复。
- **`security/`（152 项）**：安全修复。补丁中引用的编号如下（另有大量未分配编号的上游 bug 修复）：
  - CVE（8 个）：CVE-2019-11043、CVE-2019-13224、CVE-2022-31629、CVE-2026-6735、CVE-2026-7261、CVE-2026-7262、CVE-2026-109618、CVE-2026-109619
  - GHSA（20 个）：GHSA-3qgc-jrrr-25jv、GHSA-3qrf-m4j2-pcrr、GHSA-4w77-75f9-2c8w、GHSA-6wmf-4rv5-p3rp、GHSA-76gg-c692-v2mw、GHSA-7qg2-v9fj-4mwv、GHSA-94p6-54jq-9mwp、GHSA-96wq-48vp-hh57、GHSA-9pqp-7h25-4f32、GHSA-c5f2-jwm7-mmq2、GHSA-g665-fm4p-vhff、GHSA-hmxp-6pc4-f3vv、GHSA-jqcx-ccgc-xwhv、GHSA-m33r-qmcv-p97q、GHSA-p99j-rfp4-xqvq、GHSA-q6x7-frmf-grcw、GHSA-r977-prxv-hc43、GHSA-w8hw-w9fx-j79w、GHSA-w8qr-v226-r27w、GHSA-wpj3-hf5j-x4v4
- **重点**：CVE-2026-109618 / 109619（内存耗尽中断与请求状态残留导致的状态破坏）由补丁 0261 回补。注意：该补丁在部分内存耗尽路径会让 worker 以 `_exit(1)` 退出，由 FPM master 补充新进程。
- **`0400`–`0405`**：本地移植的现代安全修复，以及外部 GD、Oniguruma、mysqlnd 认证切换边界等适配。

## 适配改动

| 适配 | 原因 | 处理 |
|---|---|---|
| 现代依赖兼容（`patches/compat/`，28 项） | PHP 5.6 原生不支持 OpenSSL 3、ICU 78、libxml2 2.13、新版 autoconf/GCC 与 musl | 使用 Surý 的兼容补丁，加上本地 0300–0303（libxml2 回调常量、zlib 全局变量、mbfl 指针类型、musl 文件定位与 getpid） |
| 外部 GD 的 JIS 映射 | PHP 只在内置 GD 时支持 JIS 映射的日文字体，外部 libgd 下 `--enable-gd-jis-conv` 被忽略 | 保留该参数（与其他版本写法一致、无副作用）；`gd_info()` 中 JIS-mapped Japanese Font Support 为 false。现网旧镜像使用内置 GD，如业务依赖 JIS 映射需评估 |
| 补丁版 libgd | Alpine 的 gd-2.3.3-r10 未打补丁：调色板图像旋转 180° 会释放调用方原图（释放后使用），最近邻插值旋转会空指针崩溃 | 自行编译 libgd 2.3.3，加入上游提交 [6cc1e39](https://github.com/libgd/libgd/commit/6cc1e39e9fddd15ae74adb1a09fcd5740f44923e) 与 [a656f5c](https://github.com/libgd/libgd/commit/a656f5cc5592757996e9e96b0821a0966bfaa3b3)，编译选项与 Alpine 一致，PHP 以 rpath 链接 |
| Swoole 2.0.11 | PHP 改用系统 PCRE 后定义了 `HAVE_PCRE`，Swoole 因重复声明类属性写坏 Zend 内存管理器，加载即报内存耗尽 | 扩展补丁取消该宏，保持与内置 PCRE 构建相同的代码路径；上游 2.0.12 已删除该重复声明 |
| Event 3.1.6 | PHP 5 的 `createPair` 未保存回调上下文，回调异常路径重复释放 | 扩展补丁，参照同包 PHP 7 实现 |
| memcache 3.0.8 | 使用 GNU89 inline 语义，C11 下函数符号不导出 | 仅对该扩展加 `-fgnu89-inline` |
| 旧 mongo 驱动 | 不启用 SASL 即可在新编译器下通过 | 对齐现网：启用 SSL，GSSAPI / PLAIN 关闭 |
| ionCube / SourceGuardian | 官方只提供 glibc 版 Loader | 运行镜像安装 gcompat 与 libudev-zero；ionCube 启用时预加载 gcompat |
| Composer | 默认禁用了 `proc_open` 等函数，Composer 拉取源码和执行脚本需要 | `composer` 命令只为自身进程清空禁用函数，业务 FPM / CLI 仍保持禁用 |

## 已知问题

- **Swoole 2.0.11 与现网 1.9.4 的行为差异**：脚本文件中调用 `swoole_event_wait` 后进程退出码为 1；关闭 OPcache 时遍历 `swoole_table` 后再进入事件循环，请求结束时段错误。两者都是 2.0.11 原有问题。若业务依赖退出码，可改用 1.10.5（实测无此问题）。
- **旧 mongo 驱动**只能连接 MongoDB 5.0 及以下；6.0 起服务端移除了旧协议。
- **加密 Loader 只验证了加载**：没有 ionCube / SourceGuardian 加密业务样本。SourceGuardian 通过 libudev 读取硬件信息，绑定机器的加密脚本在容器内可能无法匹配。
- **外部 GD 与 PHP 内置 GD 的数值差异**：字体包围盒、缩放与旋转后的尺寸可能相差 1–2 像素。
- PHP 5.6 的 `tls://` 保留上游 TLS 1.0 语义，现代 OpenSSL 默认会拒绝；需要 TLS 1.2 时请使用 `tlsv1.2://`。

## 构建与验收

所有分支使用同一套脚本，版本差异只在以下数据文件中：

| 文件 | 内容 |
|---|---|
| `config/extensions.json` | PHP 版本、原生模块清单、PECL 扩展（版本、编译参数、开关）、Loader、Swoole 变体、Composer 版本 |
| `config/php-configure.txt` | PHP configure 参数 |
| `config/build-packages.txt` / `config/runtime-packages.txt` | 构建期 / 运行期 apk 包 |
| `sources.lock.json` | 全部源码、扩展、Loader 的下载地址与 SHA-256 |
| `patches/series` 与 `patches/` | PHP 补丁及应用顺序 |
| `extension-patches.lock.json` 与 `extension-patches/` | 扩展补丁 |
| `libgd/` | 补丁版 libgd 的源码锁与补丁 |

```bash
# 在指定的远程 Linux 构建节点执行（默认 linux/amd64,linux/arm64，不推送；PLATFORMS 可只构建部分架构）
bash scripts/build-image.sh       # 产物：artifacts/<变体>/php-5.6.40.oci.tar（多架构 OCI 索引）
bash scripts/verify-artifact.sh   # 按架构全套验收：功能、扩展、数据库与缓存真实读写、TLS/CA、FPM 生命周期、扫描、上游 PHPT
printf '%s' "$令牌" | DOCKERHUB_USER=benyoo bash scripts/push-image.sh   # 原样推送已验收归档并核对仓库端摘要
```

## 目录与维护说明

所有分支使用同一套模板。下表中的“公共文件”在全部分支逐字节一致，修改时必须同步到所有分支；其余是本分支的版本数据，只改本分支。

| 路径 | 类别 | 用途 | 新增或变动时怎么做 |
|---|---|---|---|
| `Dockerfile`、`scripts/`、`config/composer.sh`、`config/php-fpm.conf`、`config/security.ini`、`config/supervisord.conf`、`libgd/` | 公共文件 | 构建流程、入口脚本、验收脚本、运行配置、补丁版 libgd | 不在单个分支修改；改动先在模板验证，再同步到全部分支并重建 |
| `config/extensions.json` | 版本数据 | PHP 版本、原生模块清单、PECL 扩展（源码包、开关、编译参数、额外 CFLAGS、ini）、Loader、Swoole 变体、OPcache 是否内置、FPM 内存耗尽行为、Composer 版本 | 增删扩展或升级版本时，同时在 `sources.lock.json` 登记源码地址与 SHA-256；开关名使用现有项目级名称 |
| `config/php-configure.txt` | 版本数据 | PHP configure 参数，一行一项，按功能分组注释 | 新增参数写明原因；上游已移除的参数不要保留 |
| `config/build-packages.txt`、`config/runtime-packages.txt` | 版本数据 | 构建期 / 运行期 apk 包 | 运行期动态库由构建时 ELF 扫描自动补齐，这里只列扫描覆盖不到的包 |
| `sources.lock.json`、`timezonedb.lock.json` | 版本数据 | 全部源码、扩展、Loader、工具的下载地址与 SHA-256，以及 PHP 补丁摘要 | 只能更新为经核实的官方地址与摘要；摘要不符时构建会中止 |
| `patches/series`、`patches/security/`、`patches/compat/` | 版本数据 | PHP 源码补丁：`security/` 放安全修复与上游修复回补，`compat/` 放构建与依赖适配 | 新补丁按序号命名放入对应目录，在 `series` 中按应用顺序登记，并在 `sources.lock.json` 的 `patches` 段登记 SHA-256；补丁头写明来源、原因和对应的 CVE/GHSA；必须能被 `git apply --check` 干净应用且确实改动文件，否则构建中止 |
| `extension-patches/`、`extension-patches.lock.json` | 版本数据 | 第三方 PECL 扩展源码补丁，用于兼容修复与缺陷修复 | 见下文 |
| `provenance/` | 版本数据 | Surý 签名索引、公钥等来源证明 | 随补丁来源更新，构建时校验签名链 |
| `tests/` | 公共文件为主 | 通用测试与模板一致；`tests/security-smoke.php`、`security-soap.php`、`http-security.py`、`mysql-protocol.py`、`verify-security.py`、`modern-tls-fixtures.sh` 的内容可按版本适配；`tests/upstream-phpt-extra.txt` 为本版本的上游 PHPT 额外用例；`tests/fixtures/redis-<版本>-api.json` 为 Redis 接口基线 | 升级 Redis 扩展后，用 `php tests/redis-api.php --fingerprint` 从新镜像导出基线 |

### extension-patches/ 的用途与维护

- **用途**：存放对第三方 PECL 扩展源码的补丁。上游扩展在本 PHP 版本或新版系统库下编译失败、行为有缺陷，而上游尚未发布修复时使用。没有扩展补丁的版本，这个目录只有占位文件 `.gitkeep`，`extension-patches.lock.json` 的 `patches` 为空列表。
- **为什么要保留 `.gitkeep`**：Git 不跟踪空目录，而 Dockerfile 会执行 `COPY extension-patches ./extension-patches`；目录缺失会导致构建失败。新增补丁后可以保留 `.gitkeep`，它不影响构建。
- **目录结构**：每个扩展一个子目录，名称与源码包解压后的目录一致，即 `<扩展名>-<版本>/`，例如 `extension-patches/swoole-2.0.11/0001-disable-have-pcre-code-path.patch`。
- **锁文件登记**：在 `extension-patches.lock.json` 的 `patches` 中为每个补丁增加一项，字段为 `package`（如 `swoole-2.0.11`）、`file`（补丁相对路径）、`sha256`、`reason`（为什么需要）、`reference`（对应的上游提交或参照代码）、`regression`（验证它的测试）。
- **构建时如何应用**：`scripts/build-extensions.sh` 先校验每个补丁的 SHA-256，再在对应扩展源码目录执行 `git apply --check`，通过后才应用；任一步失败都会中止构建。
- **升级扩展版本时**：先确认新版本是否已包含该修复。已包含就删除补丁和锁文件条目；仍需要就把子目录改名为新版本、重新生成补丁并更新 `package` 与 `sha256`，然后完整构建并跑验收。

## 验收结果

最近一次模板构建（2026-10-23，linux/amd64 与 linux/arm64，两种架构分别验收）：

- **全套验收通过**：扩展与 Loader 版本逐项核对；libgd 旋转回归 210 组；可选扩展离线功能；git 与 Composer；MySQL / PostgreSQL / Redis / Memcache / Memcached 真实读写；MongoDB 8.0 与旧驱动连 MongoDB 5.0；TLS 与 CA；FPM 同 worker 请求、内存耗尽补进程、重启与退出；Trivy 扫描 0 项（扫描器无法识别自编译 PHP 与闭源 Loader，0 项不等于没有漏洞）。
- **上游 PHPT**（官方 `run-tests.php`，非 root、断网）：两种架构结果相同，各 463 个用例（补丁附带 134 个 + GD 全套），通过 379、失败 27、跳过 56；两种架构的失败清单一致，没有 arm64 独有失败。失败项逐项核实，**没有安全修复缺失**：
  - 20 项为新版系统库的输出差异：外部 libgd / FreeType 的文案与度量（GD 溢出类用例均被安全拒绝，关闭内存分配器复现无崩溃）、OpenSSL 3 拒绝测试自带的旧弱证书、cURL 8 / libxml2 2.13 / SQLite 3.53 的文案变化；
  - 7 项为运行环境限制：断网、内置 CLI 服务器启动横幅混入输出等。

| 产物 | 值 |
|---|---|
| 镜像标签 | `benyoo/php-alpine:5.6.40.20261023`（已推送，仓库端摘要与归档一致） |
| OCI 归档 SHA-256 | `91c73713ad0871a6732a6ef807ea3ef14eae2444019ffec8ee1d01ce218f869e` |
| 索引摘要 | `sha256:3fe6637807f43185272068b2b68e3cc33c6f229114917e41e63e653ebfde3e5a` |
| amd64 清单摘要 | `sha256:bcea4a8bdec623bf21f4ddfba62e1b54aa83a447e6a9bd8d534ee7c143fd361e` |
| arm64 清单摘要 | `sha256:0e3063c7bd97c3b9a40ed02986de43b100cc03ce92bcc674ce8fb2334000b78e` |
| 压缩层大小 | amd64 约 110 MB，arm64 约 110 MB |
