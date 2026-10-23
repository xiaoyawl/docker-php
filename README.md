# LookBack PHP 7.0.33 镜像

![PHP](https://img.shields.io/badge/PHP-7.0.33-777BB4)
![Alpine](https://img.shields.io/badge/Alpine-3.24-0D597F)
![架构](https://img.shields.io/badge/架构-amd64-blue)
![维护状态](https://img.shields.io/badge/上游-EOL-B0332B)

本分支 `php-7.0.33` 构建 `benyoo/php-alpine:7.0.33.<构建日>`：基于 Alpine 3.24 从源码编译 PHP 7.0.33，纳入可信安全回补、现代依赖适配、常用数据库与缓存扩展、官方 Loader，并在构建时更新 CA 信任库。

- 仓库：<https://git.dwhd.org/lookback/docker-php>（每个 PHP 版本一个分支，命名 `php-<版本>`，`master` 对应 8.5.12）
- 镜像：<https://hub.docker.com/r/benyoo/php-alpine>
- PHP 7.0 已停止上游维护（EOL）。本镜像只回补公开的安全修复，**不等于获得官方安全支持**。

## 快速使用

```bash
# 默认启动 PHP-FPM（9000 端口）与 crond，由 Supervisor 管理
docker run -d --name php70 -v /data/wwwroot:/data/wwwroot benyoo/php-alpine:7.0.33.<构建日>

# 按需开启扩展（第三方扩展与 Loader 默认全部关闭）
docker run -d -e REDIS=enable -e MEMCACHE=enable -e SWOOLE=enable -e IONCUBE=enable \
    benyoo/php-alpine:7.0.33.<构建日>

# 执行一次性命令（不启动 FPM）
docker run --rm benyoo/php-alpine:7.0.33.<构建日> php -v
docker run --rm -v "$PWD":/data/wwwroot benyoo/php-alpine:7.0.33.<构建日> composer install
```

## 从线上镜像迁移

线上 `benyoo/php:7.0`（PHP 7.0.18，Alpine 3.4，2017-05，Gateway/Worker 集群）切换到本镜像时注意：

| 项目 | 线上 benyoo/php:7.0 | 本镜像 | 迁移动作 |
|---|---|---|---|
| 入口与进程模型 | `docker-php-entrypoint`，CMD 为 `php-fpm`，无 Supervisor | `/entrypoint.sh`：默认由 Supervisor 管理 FPM 与 crond；传入其他命令（如 `php start.php start`）时直接执行 | 以命令行方式启动 Gateway/Worker 的部署无需改动；依赖原入口行为的需核对启动参数 |
| Swoole | 1.9.4 | 4.3.6 | **跨大版本**，业务需按 Swoole 4 迁移说明回归 |
| Redis | 3.1.0 | 5.3.7 | 无缺失方法、无常量变化；`OPT_TCP_KEEPALIVE` 为新增选项，未连接时读取会抛异常 |
| Event | 2.2.1 | 3.1.6 | Gateway/Worker 的关键依赖，需回归事件循环 |
| memcache / memcached | 3.0.9-dev / 3.0.0b1 | 4.0.5.2 / 3.4.0 | 由开发版、测试版升级为正式版 |
| Xdebug | 2.5.0 | 2.8.1 | — |
| mcrypt / zip | 有 | 保留 | — |
| GD | PHP 内置 GD | 补丁版外部 libgd 2.3.3 | JIS 映射日文字体不可用；字体度量、缩放尺寸可能相差 1–2 像素 |
| APCu / Hprose / Imagick / SourceGuardian / ionCube | 无 | 新增，默认关闭 | 按需开启 |
| git / Composer | 无 | 新增 | 无需处理 |

## 版本明细

### 系统与核心组件

| 组件 | 版本 | 说明 |
|---|---|---|
| 基础镜像 | `benyoo/alpine:3.24.20260615` | 固定 OCI 索引摘要 `sha256:7b08066d…ac45d9d`，构建与运行两阶段相同 |
| PHP | 7.0.33（NTS） | CLI、FPM、CGI；安装目录 `/usr/local/php` |
| OpenSSL | 3.5.9 | 系统库；PHP 已打 OpenSSL 3.0 兼容补丁 |
| cURL | 8.22.0 | 系统库 |
| ICU | 78.1 | intl 扩展使用 |
| libxml2 | 2.13.9 | 系统库 |
| SQLite | 3.53.4 | 系统库 |
| PCRE | 8.45（系统） | 不使用 PHP 内置的旧版 PCRE |
| Oniguruma | 6.9.10（系统） | mbregex 使用，本地补丁适配其新接口 |
| libzip | 1.11.4（系统） | zip 扩展使用 |
| libgd | 2.3.3 + 两项上游修复 | 自行编译到 `/opt/libgd`，见“适配改动” |
| GNU libiconv | 1.18 | 安装到 `/opt/libiconv`，提供完整的 GBK / GB18030 转换 |
| 时区数据库 | timezonedb 2026.5 | 官方 PECL 时区库，默认加载，不依赖系统 tzdata |
| CA 证书包 | ca-certificates 20261020-r0 | 构建时安装并执行 `update-ca-certificates`；PHP OpenSSL、cURL 与 `SSL_CERT_FILE` 统一使用 `/etc/ssl/certs/ca-certificates.crt` |
| Composer | 2.2.30（LTS） | 2.2 是支持 PHP 7.0/7.1 的最终系列 |
| git | 2.54.0 | 含 ssh 客户端，供 Composer 拉取源码依赖 |

镜像内 `/usr/local/share/php-build/` 保存了来源锁、扩展清单、补丁序列与 CA 摘要，`/usr/local/php/build-apk-packages.txt` 保存了构建时全部 apk 包版本。

### 原生扩展

默认加载（66 个模块，完整清单见 `config/extensions.json` 的 `native_modules`）：

bcmath、bz2、calendar、Core、ctype、curl、date、dba、dom、enchant、exif、fileinfo、filter、ftp、gd、gettext、gmp、hash、iconv、imap、intl、json、ldap、libxml、mbstring、mcrypt、mysqli、mysqlnd、odbc、openssl、pcntl、pcre、PDO、pdo_dblib、pdo_mysql、PDO_ODBC、pdo_pgsql、pdo_sqlite、pgsql、Phar、posix、pspell、readline、Reflection、session、shmop、SimpleXML、snmp、soap、sockets、SPL、sqlite3、standard、sysvmsg、sysvsem、sysvshm、tidy、tokenizer、wddx、xml、xmlreader、xmlrpc、xmlwriter、xsl、zip、zlib，以及默认开启的 OPcache。

configure 参数见 [`config/php-configure.txt`](config/php-configure.txt)。

### 可选扩展与 Loader

全部默认关闭，通过环境变量开启（值为 `enable`）。

| 扩展 | 版本 | 开关 | 说明 |
|---|---|---|---|
| redis | 5.3.7 | `REDIS` | 启用 Session 处理，不引入 igbinary / LZF；现网 7.0 为 3.1.0，接口差异见“已知问题” |
| memcache | 4.0.5.2 | `MEMCACHE` | PHP 7 系列版本；不加 `-fgnu89-inline`（见“适配改动”） |
| memcached | 3.4.0 | `MEMCACHE` | 与 memcache 同一开关；启用 SASL |
| mongodb | 1.9.2 | `MONGODB` | 链接系统 libmongoc / libbson，不编译捆绑的旧 C 驱动 |
| swoole | 4.3.6 | `SWOOLE` | 支持 PHP 7.0 的较新版本；现网 7.0 为 1.9.4 |
| xdebug | 2.8.1 | `XDEBUG` | Xdebug 2 配置（`xdebug.remote_*`）；与 ionCube 互斥 |
| apcu | 5.1.28 | `APCU` | CLI 下需 `-d apc.enable_cli=1` |
| event | 3.1.6 | `EVENT` | 链接系统 libevent |
| zstd | 0.18.0 | `ZSTD` | 链接系统 libzstd |
| imagick | 3.8.1 | `IMAGICK` | 运行镜像含 imagemagick 格式模块 |
| hprose | 1.8.0 | `HPROSE` | 上游最终版本（PHP 8 起无法编译，仅 PHP 5/7 分支提供） |
| ionCube Loader | 15.5.1 | `IONCUBE` | 官方 glibc 版，启用时预加载 gcompat；与 Xdebug 互斥 |
| SourceGuardian Loader | 17.0.0 | `SOURCEGUARDIAN` | 官方 glibc 版，依赖 gcompat 与 libudev-zero |

扩展的版本、编译参数与开关统一定义在 [`config/extensions.json`](config/extensions.json)，源码摘要见 [`sources.lock.json`](sources.lock.json)。

本版本不提供以下开关，开启时容器会报错退出，不会静默忽略：

| 开关 | 原因 |
|---|---|
| `MONGO` | 旧版 mongo 驱动（`MongoClient`）只支持 PHP 5；PHP 7 请使用 `MONGODB`（新驱动），旧代码可借助纯 PHP 的 `alcaeus/mongo-php-adapter` |
| `FFI` | FFI 是 PHP 7.4 起的原生扩展，PHP 7.0 没有 |

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

补丁序列见 [`patches/series`](patches/series)，共 184 项，按顺序严格应用：任何补丁无法干净应用或没有实际改动文件，构建立即中止，不允许模糊匹配。补丁数量不等于漏洞数量。

- **来源**：Debian 维护者 Ondřej Surý 的 PHP 7.0 源码包（`php7.0_7.0.33-92`）。构建时验证其签名链：InRelease 签名 → Sources 索引 → 补丁包摘要。另有本地移植的现代安全修复。
- **`security/`（165 项）**：安全修复（含 Surý 安全序列附带的测试修正）。补丁中引用的编号如下（另有大量未分配编号的上游 bug 修复）：
  - CVE（18 个）：CVE-2019-9020、CVE-2019-9021、CVE-2019-9022、CVE-2019-9023、CVE-2019-9024、CVE-2019-11043、CVE-2019-13224、CVE-2022-31629、CVE-2026-6722、CVE-2026-6735、CVE-2026-7258、CVE-2026-7259、CVE-2026-7261、CVE-2026-7262、CVE-2026-7568、CVE-2026-9672、CVE-2026-109618、CVE-2026-109619
  - GHSA（38 个）：GHSA-3qgc-jrrr-25jv、GHSA-3qrf-m4j2-pcrr、GHSA-453j-q27h-5p8x、GHSA-4w77-75f9-2c8w、GHSA-52jp-hrpf-2jff、GHSA-5hqh-c84r-qjcv、GHSA-62xp-839h-2637、GHSA-6wmf-4rv5-p3rp、GHSA-7qg2-v9fj-4mwv、GHSA-85c2-q967-79q5、GHSA-88hq-2827-7pg6、GHSA-8xr5-qppj-gvwj、GHSA-94p6-54jq-9mwp、GHSA-96wq-48vp-hh57、GHSA-9pqp-7h25-4f32、GHSA-c5f2-jwm7-mmq2、GHSA-ch8v-r6jh-4vvr、GHSA-cj93-vc83-wgqv、GHSA-g665-fm4p-vhff、GHSA-h35g-vwh6-m678、GHSA-hgf5-96fm-v528、GHSA-hmxp-6pc4-f3vv、GHSA-hrwm-9436-5mv3、GHSA-j3wh-g957-2m85、GHSA-jqcx-ccgc-xwhv、GHSA-m33r-qmcv-p97q、GHSA-p99j-rfp4-xqvq、GHSA-pcmh-g36c-qc44、GHSA-q6x7-frmf-grcw、GHSA-r6x9-5r99-36j7、GHSA-r977-prxv-hc43、GHSA-rgrp-mwpx-f6rm、GHSA-v8xr-gpvj-cx9g、GHSA-vc5h-9ppw-p5f3、GHSA-w8hw-w9fx-j79w、GHSA-w8qr-v226-r27w、GHSA-wm6j-2649-pv75、GHSA-wpj3-hf5j-x4v4
- **重点**：CVE-2026-109618 / 109619（内存耗尽中断与请求状态残留导致的状态破坏）由补丁 `security/0230-Avoid-state-corruption-via-bailout.patch` 回补。该补丁在部分内存耗尽路径会让 worker 以 `_exit(1)` 退出，由 FPM master 补充新进程（验收已覆盖）。
- **本地移植（31xx、3200–3203）**：参照 PHP 7.4 签名补丁与现代上游修复的安全移植（HTTP 包装器、mysqlnd 协议边界、TLS SAN 通配符、SOAP、Phar、libxml、PostgreSQL 转义与 DML 字面量等），以及外部 GD、Oniguruma、mysqlnd 认证切换边界适配。
- **上游修复回补（无 CVE）**：`security/3205` 为 `openssl_pkey_export_to_file` / `openssl_pkey_export` 增加 `bio_out` 判空。PHP 7.0.33 在输出路径不可写时会空指针崩溃，上游 7.1 已修复，对照 7.1.33 官方代码回补；回归见 `tests/security-smoke.php`。

## 适配改动

| 适配 | 原因 | 处理 |
|---|---|---|
| 现代依赖兼容（`patches/compat/`，19 项） | PHP 7.0 原生不支持 OpenSSL 3、ICU 78、libxml2 2.13、新版 autoconf/GCC 与 musl | Surý 的兼容补丁，加本地适配：3000（现代编译器适配）、3204（FPM 隐式监听在 IPv6 不可用时回退 0.0.0.0，来源 7.2.34 官方 `fpm_sockets.c`） |
| 补丁版 libgd | Alpine 的 gd-2.3.3-r10 未打补丁：调色板图像旋转 180° 会释放调用方原图（释放后使用），最近邻插值旋转会空指针崩溃 | 自行编译 libgd 2.3.3，加入上游提交 [6cc1e39](https://github.com/libgd/libgd/commit/6cc1e39e9fddd15ae74adb1a09fcd5740f44923e) 与 [a656f5c](https://github.com/libgd/libgd/commit/a656f5cc5592757996e9e96b0821a0966bfaa3b3)，编译选项与 Alpine 一致，PHP 以 rpath 链接 |
| PECL 扩展 `SED=sed` | PHP 7.0–7.3 的 phpize 生成的 configure 没有设置 `$SED`，mongodb、xdebug、swoole、imagick 会丢失扩展头文件与链接参数 | 在 `config/extensions.json` 的 configure 参数中显式写 `SED=sed`（不再需要原配方的 `CPPFLAGS` 头文件路径），已逐个预编译验证 |
| memcache 4.0.5.2 | 4.x 在 C11 下以 `extern inline` 导出 `mmc_buffer_alloc`；`-fgnu89-inline` 会让该函数只内联不导出，加载即报符号缺失 | 不加 `-fgnu89-inline`（该参数只用于 PHP 5 的 memcache 3.0.8） |
| Swoole 4.3.6 编译参数（U6） | 各版本历史写法不一 | 统一为该 Swoole 版本支持的最大公共集合：`--enable-openssl` `--enable-sockets` `--enable-mysqlnd` |
| Swoole 4.3.6 扩展补丁 | 新版 C++ 编译器拒绝 `ZVAL_ZVAL` 析构标志中 `NULL` 的隐式转换 | 改为整数 0，所有权与析构行为不变 |
| FPM 监听（U9） | PHP 7.0 对只写端口的 `listen = 9000` 固定绑定 `::`，在内核禁用 IPv6（`ipv6.disable=1`）的主机上 FPM 无法启动 | 回补 3204：先绑定 `::`（IPv6 与 IPv4 映射），失败后回退 `0.0.0.0`；配置保持 `listen = 9000`，对外仍是 9000 端口 |
| ionCube / SourceGuardian | 官方只提供 glibc 版 Loader | 运行镜像安装 gcompat 与 libudev-zero；ionCube 启用时预加载 gcompat |
| Composer 2.2.30 | 默认禁用了 `proc_open` 等函数，Composer 拉取源码和执行脚本需要 | `composer` 命令只为自身进程清空禁用函数，业务 FPM / CLI 仍保持禁用；Composer 2.2 LTS 是支持 PHP 7.0/7.1 的最终系列 |
| 统一模板（U1–U12） | 历史上各组自行决定造成的不一致 | 本版应用：U1、U2、U4（原配方已具备，保留）；U5 去掉 `--without-pear`；U6 Swoole 参数；U7 CFLAGS 统一；U8 去掉 `nlohmann-json`（仅 Swoole 4.8 使用且其自带副本）；U9 保留回补 3204 与 `listen = 9000`；U10 统一上游 PHPT 运行器；U11 时区锁统一命名；U12 开关由清单生成。U3 不适用（argon2 自 7.2） |

## 已知问题

- **与现网 `benyoo/php:7.0` 的差异**：现网为 PHP 7.0.18、Swoole 1.9.4、Redis 3.1.0、memcache 3.0.9-dev、memcached 3.0.0b1、event 2.2.1、xdebug 2.5.0。本镜像 Redis 5.3.7 对照现网 3.1.0 的接口基线：`Redis` / `RedisArray` / `RedisCluster` 无缺失方法、无常量变化，分别新增 28 / 6 / 26 个方法；新增的 `OPT_TCP_KEEPALIVE` 选项在未连接时读取会抛 `RedisException`（旧版无此选项）。Swoole 1.9 → 4.3 跨大版本，Gateway/Worker 业务需按 Swoole 4 的迁移说明验证。
- **HTTP 包装器 Location 语义与 5.6 分支不同**：单字符相对 Location 按根路径解析（`/dir/start` 跳 `a` 得到 `/a`），空 Location 跳转根目录，这是 PHP 7.x 上游语义。5.6 分支因整体改写 `http_fopen_wrapper.c`（回补 Location 超长截断等问题）而采用 RFC 相对解析，不对应某个安全公告。Location 超长截断、头部换行等安全断言在本版同样通过。
- **FPM 的 IPv6 双栈分支未实测**：构建节点内核禁用 IPv6，验收覆盖的是回退到 `0.0.0.0:9000` 的路径；支持 IPv6 的主机上走上游 7.2+ 的 `::` 双栈逻辑。
- **加密 Loader 只验证了加载**：没有 ionCube / SourceGuardian 加密业务样本。SourceGuardian 通过 libudev 读取硬件信息，绑定机器的加密脚本在容器内可能无法匹配。
- **外部 GD 与 PHP 内置 GD 的数值差异**：字体包围盒、缩放与旋转后的尺寸可能相差 1–2 像素，警告文案不同（见上游 PHPT）。

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
# 在指定的远程 Linux 构建节点执行（只构建 amd64，不推送）
bash scripts/build-image.sh       # 产物：artifacts/<变体>/php-7.0.33-amd64.oci.tar
bash scripts/verify-artifact.sh   # 全套验收：功能、扩展、数据库与缓存真实读写、TLS/CA、FPM 生命周期、扫描、上游 PHPT
```

## 验收结果

最近一次模板构建（2026-10-23，amd64）：

- **全套验收通过**：扩展与 Loader 版本逐项核对（memcache 4.0.5.2、memcached 3.4.0、redis 5.3.7、swoole 4.3.6、xdebug 2.8.1、mongodb 1.9.2、zstd 0.18.0、event 3.1.6、apcu 5.1.28、imagick 3.8.1、hprose 1.8.0、ionCube 15.5.1、SourceGuardian 17.0.0）；ionCube / SourceGuardian 在 CLI 与 FPM worker 中加载，ionCube 与 Xdebug 互斥；libgd 旋转回归 210 组；可选扩展离线功能；git 2.54.0 与 Composer 2.2.30；Redis 5.3.7 接口基线与真实读写；MySQL / PostgreSQL / Memcache / Memcached 真实读写；MongoDB 8.0 认证与读写；Swoole 旧类名 TCP 收发、Xdebug 覆盖率与跟踪；安全冒烟、mysqlnd 畸形包、HTTP 包装器、SOAP、CGI；TLS 与 CA（自建 CA、主机名、SAN、wildcard 边界）；FPM 同 worker 请求、multipart、fatal、内存耗尽补进程、重启与退出（构建节点禁用 IPv6，默认 `listen=9000` 经回补 3204 正常启动）；Trivy 扫描 0 项（扫描器无法识别自编译 PHP 与闭源 Loader，0 项不等于没有漏洞）。
- **上游 PHPT**（官方 `run-tests.php`，非 root、断网）：共 694 个用例（补丁附带 129 个 + GD、PCRE、mbregex、zip 全套），通过 600、失败 46、跳过 48。失败项逐项核实，**没有安全修复缺失**：
  - 25 项为新版系统库的输出差异：外部 libgd / FreeType 14 项（警告文案、包围盒与缩放尺寸差 1–2 像素；溢出类用例均被安全拒绝）、Oniguruma 4 项（含 GHSA-wm6j，未崩溃）、libxml2 2 项（dom bug77569、simplexml bug79971_1，NUL 字节仍被拒绝）、cURL 8、SQLite 3.53、libzip、musl locale 各 1 项，OpenSSL 3 拒绝测试自带旧证书 1 项；
  - 19 项为运行环境限制：mysqli GHSA-r6x9 的 14 项缺测试辅助文件 `fake_server.inc`（同类畸形包由本仓库 `mysql-protocol.py` 覆盖并通过）、FPM GHSA-62xp 的 2 项需要 IPv6、内置 CLI 服务器启动横幅混入输出 2 项（GHSA-c5f2、GHSA-4w77，修复本身的拒绝信息已出现）、断网 1 项；
  - 2 项测试本身不适用于 PHP 7.0：`soap_qname_crash` 使用 7.1 的可空返回类型语法（GHSA-453j；该用例需要超过 3G 内存。仅删除返回类型声明后，以同一构建阶段镜像、nobody、断网、`--memory 12g` 单独复跑，官方 `run-tests.php` 按原 EXPECT 判定通过，命令与结果见 `artifacts/default/upstream-phpt/rerun-soap_qname_crash/`）；`gh22186` 使用 7.1 起才有的常量（AES-WRAP-PAD 回归已在 verify.py 通过）。
- **产物**：OCI SHA-256 `6eac04a782aa2ed48801ad7eecd04d53e09f14aa9f19bb8ce236b8fa295d7715`；清单 `sha256:fb517bec…2912da64`；配置 `sha256:89e142c0…f9a78c68`；镜像约 116 MB。

镜像摘要在推送后补充。
