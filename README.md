# LookBack PHP 7.4.33 镜像

![PHP](https://img.shields.io/badge/PHP-7.4.33-777BB4)
![Alpine](https://img.shields.io/badge/Alpine-3.24-0D597F)
![架构](https://img.shields.io/badge/架构-amd64%20%7C%20arm64-blue)
![维护状态](https://img.shields.io/badge/上游-EOL-B0332B)

本分支 `php-7.4.33` 构建 `benyoo/php-alpine:7.4.33.<构建日>`：基于 Alpine 3.24 从源码编译 PHP 7.4.33，纳入可信安全回补、现代依赖适配、常用数据库与缓存扩展、官方 Loader，并在构建时更新 CA 信任库。

- 仓库：<https://git.dwhd.org/lookback/docker-php>（每个 PHP 版本一个分支，命名 `php-<版本>`，`master` 对应 8.5.12）
- 镜像：<https://hub.docker.com/r/benyoo/php-alpine>
- PHP 7.4 已停止上游维护（EOL，2022-11-28）。本镜像只回补公开的安全修复，**不等于获得官方安全支持**。

## 快速使用

```bash
# 默认启动 PHP-FPM（9000 端口）与 crond，由 Supervisor 管理
docker run -d --name php74 -v /data/wwwroot:/data/wwwroot benyoo/php-alpine:7.4.33.<构建日>

# 按需开启扩展（第三方扩展与 Loader 默认全部关闭）
docker run -d -e REDIS=enable -e MEMCACHE=enable -e SWOOLE=enable -e IONCUBE=enable \
    benyoo/php-alpine:7.4.33.<构建日>

# 执行一次性命令（不启动 FPM）
docker run --rm benyoo/php-alpine:7.4.33.<构建日> php -v
docker run --rm -v "$PWD":/data/wwwroot benyoo/php-alpine:7.4.33.<构建日> composer install
```

## 从线上镜像迁移

线上 `benyoo/php:7.4.33`（Alpine 3.16，2024-12）切换到本镜像时注意：

| 项目 | 线上 benyoo/php:7.4.33 | 本镜像 | 迁移动作 |
|---|---|---|---|
| ionCube Loader | 14.0.0，`php.d/10-ioncube.ini` **默认加载** | 15.5.1（官方 musl 版），**默认关闭** | 需要时设置 `IONCUBE=enable`；与 Xdebug 互斥 |
| SourceGuardian | 配置了 `ixed.7.4.lin` 默认加载，但缺 `libudev.so.1`，**实际加载失败** | 17.0.0，补齐 gcompat 与 libudev-zero 后可加载，**默认关闭** | 需要时设置 `SOURCEGUARDIAN=enable` |
| git | 有 | 2.54.0（含 ssh 客户端） | 无需处理 |
| Composer | 无 | 2.10.3，`composer` 命令只为自身进程解除禁用函数 | 无需处理 |
| Redis | 6.1.0 | 6.3.0 | 接口向后兼容：Redis 类新增 32 个方法、RedisCluster 新增 31 个、新增常量 `OPT_PACK_IGNORE_NUMBERS`、`REDIS_VECTORSET`；没有移除或改变参数个数的方法，默认选项相同 |
| Imagick / APCu / memcached / event | 3.7.0 / 5.1.24 / 3.2.0 / 3.1.4 | 3.8.1 / 5.1.28 / 3.4.0 / 3.1.6 | 同主版本升级，默认关闭，按需开启 |
| Swoole / Xdebug | 4.8.13 / 3.1.6 | 相同 | — |
| 第三方镜像 `dylan2012/php:7.4.33` 的 Hprose、mongodb | Hprose 1.8.0、mongodb 1.20.1 | 相同版本，开关 `HPROSE`、`MONGODB` | 按需开启 |

线上镜像的 `php.d` 默认加载项在本镜像都改为显式开关，未开启的扩展不会加载；如业务依赖加密脚本，务必在部署配置中加上对应开关。

## 版本明细

### 系统与核心组件

| 组件 | 版本 | 说明 |
|---|---|---|
| 基础镜像 | `benyoo/alpine:3.24.20260615` | 固定 OCI 索引摘要 `sha256:7b08066d…ac45d9d`，构建与运行两阶段相同 |
| PHP | 7.4.33（NTS） | CLI、FPM、CGI；安装目录 `/usr/local/php` |
| OpenSSL | 3.5.9 | 系统库；PHP 已打 OpenSSL 3.0 兼容补丁 |
| cURL | 8.22.0 | 系统库 |
| ICU | 78.1 | intl 扩展使用 |
| libxml2 | 2.13.9 | 系统库；已打 libxml2 2.12/2.13 兼容补丁 |
| SQLite | 3.53.4 | 系统库 |
| PCRE2 | 10.49（系统） | `--with-external-pcre`，不使用 PHP 内置 PCRE2 |
| Oniguruma | 6.9.10 | mbregex 使用 |
| libzip | 1.11.4 | 系统库 |
| libgd | 2.3.3 + 两项上游修复 | 自行编译到 `/opt/libgd`，PHP 以外部 GD 链接，见“适配改动” |
| GNU libiconv | 1.18 | 安装到 `/opt/libiconv`，提供完整的 GBK / GB18030 转换 |
| 时区数据库 | timezonedb 2026.5 | 官方 PECL 时区库，默认加载，不依赖系统 tzdata |
| CA 证书包 | ca-certificates（构建时安装并执行 `update-ca-certificates`） | PHP OpenSSL、cURL 与 `SSL_CERT_FILE` 统一使用 `/etc/ssl/certs/ca-certificates.crt`；bundle 摘要 `5961c0a3…f568b` |
| Composer | 2.10.3 | 最新稳定版（要求 PHP ≥ 7.2.5） |
| git | 2.54.0 | 含 ssh 客户端，供 Composer 拉取源码依赖 |

镜像内 `/usr/local/share/php-build/` 保存了来源锁、扩展清单、补丁序列与 CA 摘要，`/usr/local/php/build-apk-packages.txt` 保存了构建时全部 apk 包版本。

### 原生扩展

默认加载（65 个模块，完整清单见 `config/extensions.json` 的 `native_modules`）：

bcmath、bz2、calendar、ctype、curl、date、dba（gdbm / cdb / cdb_make / db4 / inifile / flatfile）、dom、enchant、exif、fileinfo、filter、ftp、gd（外部 libgd，WebP 已启用）、gettext、gmp、hash、iconv、imap、intl、json、ldap、libxml、mbstring、mysqli、mysqlnd、odbc、openssl、pcntl、pcre、PDO（dblib / mysql / odbc / pgsql / sqlite）、pgsql、Phar、posix、pspell、readline、Reflection、session、shmop、SimpleXML、snmp、soap、sockets、sodium（含 argon2 密码哈希）、SPL、sqlite3、standard、sysvmsg、sysvsem、sysvshm、tidy、tokenizer、xml、xmlreader、xmlrpc、xmlwriter、xsl、zip、zlib，以及默认开启的 OPcache。

configure 参数见 [`config/php-configure.txt`](config/php-configure.txt)。

### 可选扩展与 Loader

全部默认关闭，通过环境变量开启（值为 `enable`）。

| 扩展 | 版本 | 开关 | 说明 |
|---|---|---|---|
| redis | 6.3.0 | `REDIS` | 启用 Session 处理，不引入 igbinary / LZF |
| memcache | 4.0.5.2 | `MEMCACHE` | 支持 PHP 7 的最终分支 |
| memcached | 3.4.0 | `MEMCACHE` | 与 memcache 同一开关；启用 SASL |
| mongodb | 1.20.1 | `MONGODB` | 链接系统 libmongoc / libbson |
| swoole | 4.8.13 | `SWOOLE` | 支持 PHP 7.4 的最终版本；编译 openssl、sockets、curl hook、mysqlnd（U6）；`swoole_server` 等旧类名仍可用 |
| xdebug | 3.1.6 | `XDEBUG` | 支持 PHP 7.4 的最终版本；默认 `xdebug.mode=debug`、按触发启动；与 ionCube 互斥 |
| apcu | 5.1.28 | `APCU` | CLI 下需 `apc.enable_cli=1` |
| event | 3.1.6 | `EVENT` | 链接系统 libevent |
| zstd | 0.18.0 | `ZSTD` | 链接系统 libzstd |
| imagick | 3.8.1 | `IMAGICK` | 运行镜像含 imagemagick 格式模块 |
| hprose | 1.8.0 | `HPROSE` | 上游最终版本；只在 PHP 7.x 提供 |
| FFI | 7.4.33（内置） | `FFI` | 以共享模块编译，开启时同时设置 `ffi.enable=1` |
| ionCube Loader | 15.5.1 | `IONCUBE` | 官方 musl 版，无需 glibc 兼容层；与 Xdebug 互斥；arm64 使用官方 aarch64 glibc 版，启用时预加载 gcompat |
| SourceGuardian Loader | 17.0.0 | `SOURCEGUARDIAN` | 官方 glibc 版，依赖 gcompat 与 libudev-zero；arm64 使用官方 aarch64 版 |

扩展的版本、编译参数与开关统一定义在 [`config/extensions.json`](config/extensions.json)，源码摘要见 [`sources.lock.json`](sources.lock.json)。

本版本不提供以下开关，开启时容器会报错退出，不会静默忽略：

| 开关 | 原因 |
|---|---|
| `MONGO` | 旧版 mongo 驱动（`MongoClient`）只支持 PHP 5；PHP 7 起请使用 `MONGODB` 新驱动（或 Composer 包 alcaeus/mongo-php-adapter 兼容旧接口） |

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

补丁序列见 [`patches/series`](patches/series)，共 104 项，按顺序严格应用：任何补丁无法干净应用或没有实际改动文件，构建立即中止，不允许模糊匹配。补丁数量不等于漏洞数量。

- **来源**：Debian 维护者 Ondřej Surý 的 PHP 7.4 源码包（`php7.4_7.4.33-31+0~20261021.121+debian12~1.gbpe9c428`）。构建时验证其签名链：InRelease 签名 → Sources 索引 → 补丁包摘要。另有本地补丁（09xx）。
- **`security/`（68 项）**：安全修复。补丁中引用的编号如下（另有未分配编号的上游安全 bug 修复）：
  - CVE（11 个）：CVE-2022-31629、CVE-2024-1874、CVE-2026-109618、CVE-2026-109619、CVE-2026-6722、CVE-2026-6735、CVE-2026-7258、CVE-2026-7261、CVE-2026-7262、CVE-2026-7568、CVE-2026-9672
  - GHSA（52 个）：GHSA-3237-qqm7-mfv7、GHSA-3cr5-j632-f35r、GHSA-3qgc-jrrr-25jv、GHSA-3qrf-m4j2-pcrr、GHSA-453j-q27h-5p8x、GHSA-4w77-75f9-2c8w、GHSA-52jp-hrpf-2jff、GHSA-54hq-v5wp-fqgv、GHSA-5hqh-c84r-qjcv、GHSA-62xp-839h-2637、GHSA-6wmf-4rv5-p3rp、GHSA-7qg2-v9fj-4mwv、GHSA-7qpv-r5mr-78m4、GHSA-85c2-q967-79q5、GHSA-865w-9rf3-2wh5、GHSA-88hq-2827-7pg6、GHSA-94p6-54jq-9mwp、GHSA-96wq-48vp-hh57、GHSA-9f67-6fw4-hpfp、GHSA-9fcc-425m-g385、GHSA-9pqp-7h25-4f32、GHSA-c5f2-jwm7-mmq2、GHSA-ch8v-r6jh-4vvr、GHSA-cj93-vc83-wgqv、GHSA-fpwc-w8rq-cr92、GHSA-g665-fm4p-vhff、GHSA-h35g-vwh6-m678、GHSA-h96m-rvf9-jgm2、GHSA-hgf5-96fm-v528、GHSA-hmxp-6pc4-f3vv、GHSA-hrwm-9436-5mv3、GHSA-j3wh-g957-2m85、GHSA-jqcx-ccgc-xwhv、GHSA-m33r-qmcv-p97q、GHSA-m8rr-4c36-8gq4、GHSA-p3x9-6h7p-cgfc、GHSA-p99j-rfp4-xqvq、GHSA-pc52-254m-w9w7、GHSA-pcmh-g36c-qc44、GHSA-q6x7-frmf-grcw、GHSA-r6x9-5r99-36j7、GHSA-r977-prxv-hc43、GHSA-rgrp-mwpx-f6rm、GHSA-v8xr-gpvj-cx9g、GHSA-vc5h-9ppw-p5f3、GHSA-vvx9-73fr-5jjx、GHSA-w8hw-w9fx-j79w、GHSA-w8qr-v226-r27w、GHSA-wg4p-4hqh-c3g9、GHSA-wpj3-hf5j-x4v4、GHSA-www2-q4fc-65wf、GHSA-xr7j-rvgx-xq5p
- **重点**：CVE-2026-109618 / 109619（内存耗尽中断与请求状态残留导致的状态破坏）由补丁 0164 回补。该补丁在部分内存耗尽路径会让 worker 以 `_exit(1)` 退出，由 FPM master 补充新进程。
- **本地安全补丁**：0902 HTTP 包装器边界加固（长度索引、响应头 NUL 与 EOF 错误处理、空 Location 内存复用），0905 mysqlnd OK 消息按实际负载长度校验（覆盖官方 38 个 PHPT 未覆盖的边界）。
- GHSA-r6x9-5r99-36j7（mysqlnd 多处包越界读）在 7.4 上为 Surý 的部分修复（0149），配套测试调整（0150/0151）；本次上游 PHPT 中该修复附带的 38 个伪服务端用例全部通过，本地 0905 补齐 OK 消息边界。
- GHSA-hrwm-9436-5mv3：`pg_escape_string()` 遇无效编码时抛出 `Exception("Escaping string failed")`，不再返回未转义字符串（与 5.6 返回 false、8.x 抛 ValueError 不同）。
- **`compat/`（36 项）**：构建与依赖适配、外部 GD 兼容，以及只调整测试的上游补丁，见“适配改动”。

## 适配改动

| 适配 | 原因 | 处理 |
|---|---|---|
| 现代依赖兼容（`patches/compat/`） | PHP 7.4 原生不支持 OpenSSL 3、libxml2 2.12/2.13、Enchant 2、新版 autoconf/GCC 与 musl | Surý 同分支兼容补丁，加上本地 0900（musl `fopencookie` 定位签名）、0901（Enchant 2 保留 7.4 旧函数别名） |
| 外部 GD 兼容 | 外部 libgd 2.3.3 缺少 PHP 历史的翻转常量，且遗漏 BICUBIC 缩放模式 | 本地 0904 按内置 gd.h 补翻转常量；0906 按上游 libgd [a5f5698](https://github.com/libgd/libgd/commit/a5f5698a6832fc1f8179a9257f0b91c9a8ef496b) 兼容 BICUBIC，原两段构建（内核层 + 兼容层）已并入单一补丁序列；上游参考见 `provenance/external-gd/` |
| SOAP 重负载测试辅助 | 7.4 的 `http_server_skipif` 必须传 socket 参数，否则资源保护被跳过 | 本地 0910，只影响测试 |
| 补丁版 libgd | Alpine 的 gd-2.3.3-r10 未打补丁：调色板图像旋转 180° 会释放调用方原图（释放后使用），最近邻插值旋转会空指针崩溃 | 自行编译 libgd 2.3.3，加入上游 [6cc1e39](https://github.com/libgd/libgd/commit/6cc1e39e9fddd15ae74adb1a09fcd5740f44923e) 与 [a656f5c](https://github.com/libgd/libgd/commit/a656f5cc5592757996e9e96b0821a0966bfaa3b3)，经 pkg-config 发现、以 rpath 链接 |
| 外部 GD 的 JIS 映射 | PHP 只在内置 GD 时支持 JIS 映射的日文字体，外部 libgd 下 `--enable-gd-jis-conv` 被忽略 | 保留该参数（U4，与其他版本写法一致、无副作用）；实测 `gd_info()` 中 JIS-mapped Japanese Font Support 为 false。现网 `benyoo/php:7.4.33` 使用 PHP 内置 GD（2.1.0 兼容，实测 JIS 映射与 WebP 均未启用），JIS 行为与本镜像一致；改用外部 libgd 后数值可能有 1–2 像素差异 |
| 统一编译参数（U1–U4） | 历史各组自行决定造成的不一致 | U1 保留 `--with-layout=GNU --with-pic --enable-shared`；U2 保留 `--with-db4`（实测 `dba_handlers()` 含 db4）与 `--with-mhash`；U3 启用 `--with-password-argon2`（实测 `PASSWORD_ARGON2ID` 已定义）与 `--with-webp`（实测 `gd_info()` WebP Support 为 true）；U4 恢复 `--enable-gd-jis-conv`、`--disable-rpath` |
| 统一构建与入口（U5–U7、U10–U12） | 同上 | U5 不带 `--without-pear`；U6 Swoole 编译 openssl、sockets、curl hook、mysqlnd；U7 CFLAGS 含 `-DOPENSSL_SUPPRESS_DEPRECATED`；U10 上游 PHPT 使用统一运行器；U11 时区锁统一为 `timezonedb.lock.json`；U12 开关清单由 `config/extensions.json` 生成，不提供的开关报错 |
| FFI | PHP 7.4 起内置 | 以共享模块编译（`--with-ffi=shared`），开关 `FFI` 加载并设置 `ffi.enable=1` |
| ionCube / SourceGuardian | ionCube 有官方 musl 版；SourceGuardian 只有 glibc 版 | ionCube 直接加载；运行镜像安装 gcompat 与 libudev-zero 供 SourceGuardian 使用 |
| Composer | 默认禁用了 `proc_open` 等函数，Composer 拉取源码和执行脚本需要 | `composer` 命令只为自身进程清空禁用函数，业务 FPM / CLI 仍保持禁用 |

## 已知问题

- **加密 Loader 只验证了加载**：没有 ionCube / SourceGuardian 加密业务样本。SourceGuardian 通过 libudev 读取硬件信息，绑定机器的加密脚本在容器内可能无法匹配。
- **外部 GD 与 PHP 内置 GD 的数值差异**：字体包围盒、缩放与旋转后的尺寸可能相差 1–2 像素（如 `imagerotate` 结果 42×24 对内置 GD 的 40×23）。
- **升级到 PHP 8 的 Swoole 5/6 时**：Swoole 5/6 已移除 `swoole_server`、`swoole_client` 等旧类名，业务需改用 `Swoole\Server`、`Swoole\Client`；7.4 的 Swoole 4.8.13 仍保留旧类名。
- musl 与 glibc 的区域设置、`crypt()` 失败标记存在差异（如 bcrypt 拒绝时返回 `*` 而非 `*0`），安全行为一致。

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
bash scripts/build-image.sh       # 产物：artifacts/<变体>/php-7.4.33.oci.tar（多架构 OCI 索引）
bash scripts/verify-artifact.sh   # 按架构全套验收：功能、扩展、数据库与缓存真实读写、TLS/CA、FPM 生命周期、扫描
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

最近一次模板构建（2026-10-23，linux/amd64 与 linux/arm64，两种架构分别验收，`benyoo/php-alpine:7.4.33.20261023`）：

- **全套验收通过**：扩展与 Loader 版本逐项核对（memcache 4.0.5.2、memcached 3.4.0、redis 6.3.0、swoole 4.8.13、xdebug 3.1.6、mongodb 1.20.1、zstd 0.18.0、event 3.1.6、apcu 5.1.28、imagick 3.8.1、hprose 1.8.0、FFI、ionCube 15.5.1、SourceGuardian 17.0.0）；ionCube + SourceGuardian + OPcache 组合与 FPM worker 中加载；libgd 旋转回归 210 组；可选扩展离线功能（Imagick、SourceGuardian、APCu、FFI、Hprose）；Xdebug 3.1.6 覆盖率与跟踪；Swoole 4.8.13 旧类名 TCP 收发；Redis 6.3.0 接口基线与真实读写；git 与 Composer；MySQL / PostgreSQL / Memcache / Memcached 真实读写；MongoDB 8.0；HTTP 与 mysqlnd 协议安全回归、TLS 与 CA；FPM 同 worker 请求、内存耗尽后 worker 按 0164 补丁退出并由 master 补充（清单 `fpm.oom_worker_exits=true`）、重启与退出；扩展包许可文件随镜像保存在 `/usr/local/php/share/licenses/`；Trivy 扫描 0 项（扫描器无法识别自编译 PHP 与闭源 Loader，0 项不等于没有漏洞）。
- **上游 PHPT**（官方 `run-tests.php`，非 root、断网）：linux/amd64 与 linux/arm64 结果相同、失败清单一致，没有 arm64 独有失败；共 635 个用例（补丁附带 177 个 + GD、PCRE 全套 + mysqlnd 安全用例），通过 545、失败 27、跳过 63。失败项逐项核实，**没有安全修复缺失**：
  - 25 项为环境或系统库差异：外部 libgd / FreeType 的警告文案、度量与旋转尺寸 14 项（含 bug65148；GD 溢出类用例均被安全拒绝）、libxml2 2.13 诊断文案 4 项（外部实体仍被拒绝加载）、PCRE2 10.49 错误文本与偏移 4 项、musl 区域设置 2 项、musl `crypt()` 失败标记 1 项；
  - 1 项为测试预期过时：bug75535 期望无冒号响应头返回空串，安全修复 GHSA-pcmh-g36c-qc44 起改为拒绝；
  - 1 项为运行资源限制：soap_qname_crash 需 `memory_limit=8G`，运行器容器上限 3G，主运行无输出或只输出 `Termsig=0`（两种架构均为进程被中止）；以 12G 单独复跑通过（命令与结果见 `artifacts/default/upstream-phpt/resource-rerun-soap_qname_crash.log`），对应修复 GHSA-453j-q27h-5p8x 有效。

| 镜像标签（已推送） | 索引摘要（仓库端与归档一致） | amd64 清单 | arm64 清单 | 压缩层 amd64 / arm64 | OCI 归档 SHA-256 |
|---|---|---|---|---|---|
| `benyoo/php-alpine:7.4.33.20261023` | `sha256:51624b76feba7ce00052932b9668149b15659e7a66e5805f0525b37f051ec48f` | `sha256:c6762bb9a909f2d1e42a2a953d963202acaa2d6908bbca1aafd0c86ce9851104` | `sha256:7f0f87fa8abce08ba53d436e9888b81c025030ff36fc58a813e372f961fb847e` | 约 119 / 119 MB | `7589c31bac3b16fac0b15b54c1dfe8682d6afd1b3d0fe38ab4503b211ab7c922` |

Trivy 扫描（每个变体与架构）：amd64 0、arm64 0 项。

2026-10-24 以相同构建日重建并覆盖上述标签：只把维护者标签改为 Manta（`org.opencontainers.image.authors`、`maintainer`），编译阶段复用缓存；两种架构重新完成全套功能验收与 Trivy 扫描（0 项），上游 PHPT 未重跑（编译阶段未变，沿用上述结果）。
