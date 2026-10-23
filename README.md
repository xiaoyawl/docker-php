# LookBack PHP 7.2.34 镜像

![PHP](https://img.shields.io/badge/PHP-7.2.34-777BB4)
![Alpine](https://img.shields.io/badge/Alpine-3.24-0D597F)
![架构](https://img.shields.io/badge/架构-amd64-blue)
![维护状态](https://img.shields.io/badge/上游-EOL-B0332B)

本分支 `php-7.2.34` 构建 `benyoo/php-alpine:7.2.34.<构建日>`：基于 Alpine 3.24 从源码编译 PHP 7.2.34，纳入可信安全回补、现代依赖适配、常用数据库与缓存扩展、官方 Loader，并在构建时更新 CA 信任库。

- 仓库：<https://git.dwhd.org/lookback/docker-php>（每个 PHP 版本一个分支，命名 `php-<版本>`，`master` 对应 8.5.12）
- 镜像：<https://hub.docker.com/r/benyoo/php-alpine>
- PHP 7.2 已停止上游维护（EOL）。本镜像只回补公开的安全修复，**不等于获得官方安全支持**。

## 快速使用

```bash
# 默认启动 PHP-FPM（9000 端口）与 crond，由 Supervisor 管理
docker run -d --name php72 -v /data/wwwroot:/data/wwwroot benyoo/php-alpine:7.2.34.<构建日>

# 按需开启扩展（第三方扩展与 Loader 默认全部关闭）
docker run -d -e REDIS=enable -e MEMCACHE=enable -e SWOOLE=enable -e IONCUBE=enable \
    benyoo/php-alpine:7.2.34.<构建日>

# 执行一次性命令（不启动 FPM）
docker run --rm benyoo/php-alpine:7.2.34.<构建日> php -v
docker run --rm -v "$PWD":/data/wwwroot benyoo/php-alpine:7.2.34.<构建日> composer install
```

## 版本明细

### 系统与核心组件

| 组件 | 版本 | 说明 |
|---|---|---|
| 基础镜像 | `benyoo/alpine:3.24.20260615` | 固定 OCI 索引摘要 `sha256:7b08066d…ac45d9d`，构建与运行两阶段相同 |
| PHP | 7.2.34（NTS） | CLI、FPM、CGI；安装目录 `/usr/local/php` |
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
| libsodium / argon2 | 1.0.22 / 20190702（系统） | sodium 扩展与 `PASSWORD_ARGON2I`（`PASSWORD_ARGON2ID` 自 PHP 7.3 起） |
| Composer | 2.10.3 | PHP 7.2.5+ 使用的最新稳定版 |
| git | 2.54.0 | 含 ssh 客户端，供 Composer 拉取源码依赖 |

镜像内 `/usr/local/share/php-build/` 保存了来源锁、扩展清单、补丁序列与 CA 摘要，`/usr/local/php/build-apk-packages.txt` 保存了构建时全部 apk 包版本。

### 原生扩展

默认加载（66 个模块，完整清单见 `config/extensions.json` 的 `native_modules`）：

bcmath、bz2、calendar、Core、ctype、curl、date、dba、dom、enchant、exif、fileinfo、filter、ftp、gd、gettext、gmp、hash、iconv、imap、intl、json、ldap、libxml、mbstring、mysqli、mysqlnd、odbc、openssl、pcntl、pcre、PDO、pdo_dblib、pdo_mysql、PDO_ODBC、pdo_pgsql、pdo_sqlite、pgsql、Phar、posix、pspell、readline、Reflection、session、shmop、SimpleXML、snmp、soap、sockets、sodium、SPL、sqlite3、standard、sysvmsg、sysvsem、sysvshm、tidy、tokenizer、wddx、xml、xmlreader、xmlrpc、xmlwriter、xsl、zip、zlib，以及默认开启的 OPcache。

configure 参数见 [`config/php-configure.txt`](config/php-configure.txt)。

### 可选扩展与 Loader

全部默认关闭，通过环境变量开启（值为 `enable`）。

| 扩展 | 版本 | 开关 | 说明 |
|---|---|---|---|
| redis | 6.0.2 | `REDIS` | 启用 Session 处理，不引入 igbinary / LZF |
| memcache | 4.0.5.2 | `MEMCACHE` | PHP 7 系列版本；不加 `-fgnu89-inline`（见“适配改动”） |
| memcached | 3.4.0 | `MEMCACHE` | 与 memcache 同一开关；启用 SASL |
| mongodb | 1.16.2 | `MONGODB` | 链接系统 libmongoc / libbson，不编译捆绑的旧 C 驱动 |
| swoole | 4.8.13 | `SWOOLE` | 4.x 最终系列，支持 PHP 7.2–8.1；启用 curl hook |
| xdebug | 3.1.6 | `XDEBUG` | Xdebug 3 配置（`xdebug.mode=debug,develop`）；与 ionCube 互斥 |
| apcu | 5.1.28 | `APCU` | CLI 下需 `-d apc.enable_cli=1` |
| event | 3.1.6 | `EVENT` | 链接系统 libevent |
| zstd | 0.18.0 | `ZSTD` | 链接系统 libzstd |
| imagick | 3.8.1 | `IMAGICK` | 运行镜像含 imagemagick 格式模块 |
| hprose | 1.8.0 | `HPROSE` | 上游最终版本（PHP 8 起无法编译，仅 PHP 5/7 分支提供） |
| ionCube Loader | 15.5.1 | `IONCUBE` | 官方 musl 版，无需预加载；与 Xdebug 互斥 |
| SourceGuardian Loader | 17.0.0 | `SOURCEGUARDIAN` | 官方 glibc 版，依赖 gcompat 与 libudev-zero |

扩展的版本、编译参数与开关统一定义在 [`config/extensions.json`](config/extensions.json)，源码摘要见 [`sources.lock.json`](sources.lock.json)。

本版本不提供以下开关，开启时容器会报错退出，不会静默忽略：

| 开关 | 原因 |
|---|---|
| `MONGO` | 旧版 mongo 驱动（`MongoClient`）只支持 PHP 5；PHP 7 请使用 `MONGODB`（新驱动），旧代码可借助纯 PHP 的 `alcaeus/mongo-php-adapter` |
| `FFI` | FFI 是 PHP 7.4 起的原生扩展，PHP 7.2 没有 |

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
| `XDEBUG_REMOTE_HOST` / `XDEBUG_REMOTE_PORT` | `localhost` / `9900` | Xdebug 远程调试地址（映射为 Xdebug 3 的 `xdebug.client_host` / `xdebug.client_port`） |
| 扩展开关 | `disable` | 见上表 |

## 安全回补

补丁序列见 [`patches/series`](patches/series)，共 113 项，按顺序严格应用：任何补丁无法干净应用或没有实际改动文件，构建立即中止，不允许模糊匹配。补丁数量不等于漏洞数量。

- **来源**：Debian 维护者 Ondřej Surý 的 PHP 7.2 源码包（`php7.2_7.2.34-66`）。构建时验证其签名链：InRelease 签名 → Sources 索引 → 补丁包摘要。另有本地移植的现代安全修复。
- **`security/`（98 项）**：安全修复（含 Surý 安全序列附带的测试修正）。补丁中引用的编号如下（另有大量未分配编号的上游 bug 修复）：
  - CVE（10 个）：CVE-2022-31629、CVE-2026-6722、CVE-2026-6735、CVE-2026-7258、CVE-2026-7261、CVE-2026-7262、CVE-2026-7568、CVE-2026-9672、CVE-2026-109618、CVE-2026-109619
  - GHSA（41 个）：GHSA-3cr5-j632-f35r、GHSA-3qgc-jrrr-25jv、GHSA-3qrf-m4j2-pcrr、GHSA-453j-q27h-5p8x、GHSA-4w77-75f9-2c8w、GHSA-54hq-v5wp-fqgv、GHSA-5hqh-c84r-qjcv、GHSA-62xp-839h-2637、GHSA-6wmf-4rv5-p3rp、GHSA-7qg2-v9fj-4mwv、GHSA-7qpv-r5mr-78m4、GHSA-85c2-q967-79q5、GHSA-88hq-2827-7pg6、GHSA-94p6-54jq-9mwp、GHSA-96wq-48vp-hh57、GHSA-9f67-6fw4-hpfp、GHSA-9pqp-7h25-4f32、GHSA-c5f2-jwm7-mmq2、GHSA-ch8v-r6jh-4vvr、GHSA-cj93-vc83-wgqv、GHSA-g665-fm4p-vhff、GHSA-h35g-vwh6-m678、GHSA-h96m-rvf9-jgm2、GHSA-hmxp-6pc4-f3vv、GHSA-hrwm-9436-5mv3、GHSA-j3wh-g957-2m85、GHSA-jqcx-ccgc-xwhv、GHSA-m33r-qmcv-p97q、GHSA-p99j-rfp4-xqvq、GHSA-q6x7-frmf-grcw、GHSA-r6x9-5r99-36j7、GHSA-r977-prxv-hc43、GHSA-rgrp-mwpx-f6rm、GHSA-vc5h-9ppw-p5f3、GHSA-vvx9-73fr-5jjx、GHSA-w8hw-w9fx-j79w、GHSA-w8qr-v226-r27w、GHSA-wg4p-4hqh-c3g9、GHSA-wpj3-hf5j-x4v4、GHSA-www2-q4fc-65wf、GHSA-xr7j-rvgx-xq5p
- **重点**：CVE-2026-109618 / 109619（内存耗尽中断与请求状态残留导致的状态破坏）由补丁 `security/0159-Avoid-state-corruption-via-bailout.patch` 回补。该补丁在部分内存耗尽路径会让 worker 以 `_exit(1)` 退出，由 FPM master 补充新进程（验收已覆盖）。
- **本地移植（31xx、9002）**：参照 PHP 7.4 签名补丁与现代上游修复的安全移植（HTTP 包装器、mysqlnd 协议与长度边界、TLS SAN 通配符、SOAP、Phar、PostgreSQL 转义与 DML 字面量、网络参数 NUL、DatePeriod 重置、ctype 无符号输入等），以及外部 GD 适配。
- **补充补丁 3125a（GHSA-www2-q4fc-65wf）**：3125 在 7.2 上不完整，只改了 Windows 的 `dns_win32.c`，Linux 的 `dns.c` 中 `dns_get_record` / `dns_get_mx` 仍接受含 NUL 字节的主机名；补充补丁 3125a 补齐 Linux 实现（改为 `Z_PARAM_PATH`，与 7.3 对应代码逐行一致），上游 PHPT `ghsa-www2-q4fc-65wf` 由失败变为通过。

## 适配改动

| 适配 | 原因 | 处理 |
|---|---|---|
| 现代依赖兼容（`patches/compat/`，15 项） | PHP 7.2 原生不支持 OpenSSL 3、ICU 78、libxml2 2.13、新版 autoconf/GCC 与 musl | Surý 的兼容补丁，加本地适配：9000（Alpine 3.24 构建适配）、3113（libxml2 2.13 运行时适配） |
| 补丁版 libgd | Alpine 的 gd-2.3.3-r10 未打补丁：调色板图像旋转 180° 会释放调用方原图（释放后使用），最近邻插值旋转会空指针崩溃 | 自行编译 libgd 2.3.3，加入上游提交 [6cc1e39](https://github.com/libgd/libgd/commit/6cc1e39e9fddd15ae74adb1a09fcd5740f44923e) 与 [a656f5c](https://github.com/libgd/libgd/commit/a656f5cc5592757996e9e96b0821a0966bfaa3b3)，编译选项与 Alpine 一致，PHP 以 rpath 链接 |
| PECL 扩展 `SED=sed` | PHP 7.0–7.3 的 phpize 生成的 configure 没有设置 `$SED`，mongodb、xdebug、swoole、imagick 会丢失扩展头文件与链接参数 | 在 `config/extensions.json` 的 configure 参数中显式写 `SED=sed`（不再需要原配方的 `CPPFLAGS` 头文件路径），已逐个预编译验证 |
| memcache 4.0.5.2 | 4.x 在 C11 下以 `extern inline` 导出 `mmc_buffer_alloc`；`-fgnu89-inline` 会让该函数只内联不导出，加载即报符号缺失 | 不加 `-fgnu89-inline`（该参数只用于 PHP 5 的 memcache 3.0.8） |
| Swoole 4.8.13 编译参数（U6） | 各版本历史写法不一 | 统一为该 Swoole 版本支持的最大公共集合：`--enable-openssl` `--enable-sockets` `--enable-mysqlnd` `--enable-swoole-curl` |
| FPM 监听（U9） | 上游自 7.2 起已内置“隐式监听在 IPv6 不可用时回退 0.0.0.0” | 不需要回补 3204，配置保持 `listen = 9000` |
| 密码哈希（U3） | argon2 自 PHP 7.2 可用，原配方未启用 | 启用 `--with-password-argon2`，构建依赖增加 `argon2-dev` |
| ionCube / SourceGuardian | ionCube 有官方 musl 版；SourceGuardian 只有 glibc 版 | 运行镜像安装 gcompat 与 libudev-zero；ionCube 使用 musl 版，不预加载 |
| Composer 2.10.3 | 默认禁用了 `proc_open` 等函数，Composer 拉取源码和执行脚本需要 | `composer` 命令只为自身进程清空禁用函数，业务 FPM / CLI 仍保持禁用；PHP 7.2.5+ 使用 Composer 最新稳定版 |
| 统一模板（U1–U12） | 历史上各组自行决定造成的不一致 | 本版应用：U1、U2、U4（原配方已具备，保留）；U5（原配方已无 `--without-pear`）；U6 Swoole 参数；U7 CFLAGS 统一；U8 去掉 `nlohmann-json`（仅 Swoole 4.8 使用且其自带副本）；U10 统一上游 PHPT 运行器；U11 时区锁由 `timezonedb-source.lock.json` 统一为 `timezonedb.lock.json`；U12 开关由清单生成。U3 启用 `--with-password-argon2`；U9 上游已内置回退，保持 `listen = 9000` |

## 已知问题

- **HTTP 包装器 Location 语义与 5.6 分支不同**：单字符相对 Location 按根路径解析（`/dir/start` 跳 `a` 得到 `/a`），空 Location 跳转根目录，这是 PHP 7.x 上游语义。5.6 分支因整体改写 `http_fopen_wrapper.c`（回补 Location 超长截断等问题）而采用 RFC 相对解析，不对应某个安全公告。Location 超长截断、头部换行等安全断言在本版同样通过。
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
bash scripts/build-image.sh       # 产物：artifacts/<变体>/php-7.2.34-amd64.oci.tar
bash scripts/verify-artifact.sh   # 全套验收：功能、扩展、数据库与缓存真实读写、TLS/CA、FPM 生命周期、扫描、上游 PHPT
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

最近一次模板构建（2026-10-23，amd64）：

- **全套验收通过**：扩展与 Loader 版本逐项核对（memcache 4.0.5.2、memcached 3.4.0、redis 6.0.2、swoole 4.8.13、xdebug 3.1.6、mongodb 1.16.2、zstd 0.18.0、event 3.1.6、apcu 5.1.28、imagick 3.8.1、hprose 1.8.0、ionCube 15.5.1、SourceGuardian 17.0.0）；ionCube / SourceGuardian 在 CLI 与 FPM worker 中加载，ionCube 与 Xdebug 互斥；libgd 旋转回归 210 组；可选扩展离线功能；git 2.54.0 与 Composer 2.10.3；Redis 6.0.2 接口基线与真实读写；MySQL / PostgreSQL（无效 UTF-8 转义受控失败）/ Memcache / Memcached 真实读写；MongoDB 8.0 认证与读写；Swoole 旧类名 TCP 收发、Xdebug 3 覆盖率与跟踪；`PASSWORD_ARGON2I` 哈希与校验；安全冒烟、mysqlnd 畸形包、HTTP 包装器、SOAP、CGI；TLS 与 CA（自建 CA、主机名、SAN、wildcard 边界）；FPM 同 worker 请求、multipart、fatal、内存耗尽 worker 退出并由 master 补充、重启与退出（上游内置 IPv6 回退，默认 `listen=9000` 正常启动）；Trivy 扫描 0 项（扫描器无法识别自编译 PHP 与闭源 Loader，0 项不等于没有漏洞）。
- **上游 PHPT**（官方 `run-tests.php`，非 root、断网）：共 744 个用例（补丁附带 116 个 + GD、PCRE、mbregex、zip 全套），通过 632、失败 56、跳过 56。补充补丁 3125a 应用前 GHSA-www2-q4fc-65wf 用例失败，应用后通过。失败项逐项核实，**没有安全修复缺失**：
  - 31 项为运行环境限制：mysqli 29 项缺测试辅助文件 `fake_server.inc`（GHSA-r6x9、GHSA-h35g 等 mysqlnd 畸形包用例；同类畸形包由本仓库 `mysql-protocol.py` 覆盖并通过）、内置 CLI 服务器启动横幅混入输出 2 项（GHSA-c5f2、GHSA-4w77，修复本身的拒绝信息已出现）；
  - 19 项为新版系统库的输出差异：外部 libgd / FreeType 16 项（警告文案、包围盒与缩放尺寸差 1–2 像素；溢出类用例均被安全拒绝）、libxml2（simplexml bug79971_1，NUL 字节仍被拒绝）、musl locale、libzip 各 1 项；
  - 5 项为测试夹具问题：GHSA-xr7j-rvgx-xq5p 与 `san_*` 系列。7.2 源码的测试证书生成器忽略 SAN 参数（生成的证书无 SAN，PHP 回退 CN 属正确行为），`san_peer_matching` 的静态证书为 2013 年 SHA1 / 1024 位且已过期、被 OpenSSL 3 拒绝。只替换测试夹具（7.4.33 官方证书生成器、同 SAN / Subject 的 SHA256 / 2048 位等价证书）后，在同一构建阶段镜像以 nobody、断网复跑 5 项全部通过，证明 PHP 的 SAN 校验逻辑正确；命令、夹具摘要与结果见 `artifacts/default/upstream-phpt/rerun-openssl-san/`；
  - 1 项为运行资源限制：`soap_qname_crash`（GHSA-453j）声明的 memory_limit 超过 3G，主运行只输出 `Termsig=0`；以同一构建阶段镜像、nobody、断网、`--memory 12g` 单独复跑通过（用例未改动），见 `artifacts/default/upstream-phpt/rerun-soap_qname_crash/`。
- **产物**：OCI SHA-256 `53c269f6a3a1cdafc2ed7e8db4e4b1390987f1cfa678c66dfe4c4ab25531f3ba`；清单 `sha256:6b3df749…59735310`；配置 `sha256:50814acc…20daf4db`；镜像约 118 MB。

镜像摘要在推送后补充。
