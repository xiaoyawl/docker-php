# LookBack PHP 7.3.33 镜像

![PHP](https://img.shields.io/badge/PHP-7.3.33-777BB4)
![Alpine](https://img.shields.io/badge/Alpine-3.24-0D597F)
![架构](https://img.shields.io/badge/架构-amd64-blue)
![维护状态](https://img.shields.io/badge/上游-EOL-B0332B)

本分支 `php-7.3.33` 构建 `benyoo/php-alpine:7.3.33.<构建日>`：基于 Alpine 3.24 从源码编译 PHP 7.3.33，纳入可信安全回补、现代依赖适配、常用数据库与缓存扩展、官方 Loader，并在构建时更新 CA 信任库。

- 仓库：<https://git.dwhd.org/lookback/docker-php>（每个 PHP 版本一个分支，命名 `php-<版本>`，`master` 对应 8.5.12）
- 镜像：<https://hub.docker.com/r/benyoo/php-alpine>
- PHP 7.3 已停止上游维护（EOL）。本镜像只回补公开的安全修复，**不等于获得官方安全支持**。

## 快速使用

```bash
# 默认启动 PHP-FPM（9000 端口）与 crond，由 Supervisor 管理
docker run -d --name php73 -v /data/wwwroot:/data/wwwroot benyoo/php-alpine:7.3.33.<构建日>

# 按需开启扩展（第三方扩展与 Loader 默认全部关闭）
docker run -d -e REDIS=enable -e MEMCACHE=enable -e SWOOLE=enable -e IONCUBE=enable \
    benyoo/php-alpine:7.3.33.<构建日>

# 执行一次性命令（不启动 FPM）
docker run --rm benyoo/php-alpine:7.3.33.<构建日> php -v
docker run --rm -v "$PWD":/data/wwwroot benyoo/php-alpine:7.3.33.<构建日> composer install
```

## 版本明细

### 系统与核心组件

| 组件 | 版本 | 说明 |
|---|---|---|
| 基础镜像 | `benyoo/alpine:3.24.20260615` | 固定 OCI 索引摘要 `sha256:7b08066d…ac45d9d`，构建与运行两阶段相同 |
| PHP | 7.3.33（NTS） | CLI、FPM、CGI；安装目录 `/usr/local/php` |
| OpenSSL | 3.5.9 | 系统库；PHP 已打 OpenSSL 3.0 兼容补丁 |
| cURL | 8.22.0 | 系统库 |
| ICU | 78.1 | intl 扩展使用 |
| libxml2 | 2.13.9 | 系统库 |
| SQLite | 3.53.4 | 系统库 |
| PCRE2 | 10.49（系统） | PHP 7.3 起使用 PCRE2，不使用内置版本 |
| Oniguruma | 6.9.10（系统） | mbregex 使用，本地补丁适配其新接口 |
| libzip | 1.11.4（系统） | zip 扩展使用 |
| libgd | 2.3.3 + 两项上游修复 | 自行编译到 `/opt/libgd`，见“适配改动” |
| GNU libiconv | 1.18 | 安装到 `/opt/libiconv`，提供完整的 GBK / GB18030 转换 |
| 时区数据库 | timezonedb 2026.5 | 官方 PECL 时区库，默认加载，不依赖系统 tzdata |
| CA 证书包 | ca-certificates 20261020-r0 | 构建时安装并执行 `update-ca-certificates`；PHP OpenSSL、cURL 与 `SSL_CERT_FILE` 统一使用 `/etc/ssl/certs/ca-certificates.crt` |
| libsodium / argon2 | 1.0.22 / 20190702（系统） | sodium 扩展与 `PASSWORD_ARGON2I` / `PASSWORD_ARGON2ID` |
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
| `FFI` | FFI 是 PHP 7.4 起的原生扩展，PHP 7.3 没有 |

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

补丁序列见 [`patches/series`](patches/series)，共 98 项，按顺序严格应用：任何补丁无法干净应用或没有实际改动文件，构建立即中止，不允许模糊匹配。补丁数量不等于漏洞数量。

- **来源**：Debian 维护者 Ondřej Surý 的 PHP 7.3 源码包（`php7.3_7.3.33-35`）。构建时验证其签名链：InRelease 签名 → Sources 索引 → 补丁包摘要。另有本地移植的现代安全修复。
- **`security/`（84 项）**：安全修复（含 Surý 安全序列附带的测试修正）。补丁中引用的编号如下（另有大量未分配编号的上游 bug 修复）：
  - CVE（10 个）：CVE-2022-31629、CVE-2026-6722、CVE-2026-6735、CVE-2026-7258、CVE-2026-7261、CVE-2026-7262、CVE-2026-7568、CVE-2026-9672、CVE-2026-109618、CVE-2026-109619
  - GHSA（44 个）：GHSA-3237-qqm7-mfv7、GHSA-3cr5-j632-f35r、GHSA-3qgc-jrrr-25jv、GHSA-3qrf-m4j2-pcrr、GHSA-453j-q27h-5p8x、GHSA-4w77-75f9-2c8w、GHSA-54hq-v5wp-fqgv、GHSA-5hqh-c84r-qjcv、GHSA-62xp-839h-2637、GHSA-6wmf-4rv5-p3rp、GHSA-7qg2-v9fj-4mwv、GHSA-7qpv-r5mr-78m4、GHSA-85c2-q967-79q5、GHSA-88hq-2827-7pg6、GHSA-8xr5-qppj-gvwj、GHSA-94p6-54jq-9mwp、GHSA-96wq-48vp-hh57、GHSA-9f67-6fw4-hpfp、GHSA-9pqp-7h25-4f32、GHSA-c5f2-jwm7-mmq2、GHSA-ch8v-r6jh-4vvr、GHSA-cj93-vc83-wgqv、GHSA-g665-fm4p-vhff、GHSA-h35g-vwh6-m678、GHSA-h96m-rvf9-jgm2、GHSA-hgf5-96fm-v528、GHSA-hmxp-6pc4-f3vv、GHSA-hrwm-9436-5mv3、GHSA-j3wh-g957-2m85、GHSA-jqcx-ccgc-xwhv、GHSA-m33r-qmcv-p97q、GHSA-p99j-rfp4-xqvq、GHSA-q6x7-frmf-grcw、GHSA-r6x9-5r99-36j7、GHSA-r977-prxv-hc43、GHSA-rgrp-mwpx-f6rm、GHSA-vc5h-9ppw-p5f3、GHSA-vvx9-73fr-5jjx、GHSA-w8hw-w9fx-j79w、GHSA-w8qr-v226-r27w、GHSA-wg4p-4hqh-c3g9、GHSA-wpj3-hf5j-x4v4、GHSA-www2-q4fc-65wf、GHSA-xr7j-rvgx-xq5p
- **重点**：CVE-2026-109618 / 109619（内存耗尽中断与请求状态残留导致的状态破坏）由补丁 `security/0139-Avoid-state-corruption-via-bailout.patch` 回补。该补丁在部分内存耗尽路径会让 worker 以 `_exit(1)` 退出，由 FPM master 补充新进程（验收已覆盖）。
- **本地移植（31xx、9002）**：参照 PHP 7.4 签名补丁与现代上游修复的安全移植（HTTP 包装器、mysqlnd 协议与长度边界、TLS SAN 通配符、SOAP、Phar、PostgreSQL 转义与 DML 字面量、网络参数 NUL、DatePeriod 重置、ctype 无符号输入等），以及外部 GD 适配。

## 适配改动

| 适配 | 原因 | 处理 |
|---|---|---|
| 现代依赖兼容（`patches/compat/`，14 项） | PHP 7.3 原生不支持 OpenSSL 3、ICU 78、libxml2 2.13、新版 autoconf/GCC 与 musl | Surý 的兼容补丁，加本地适配：9000（Alpine 3.24 构建适配）、3113（libxml2 2.13 运行时适配） |
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
bash scripts/build-image.sh       # 产物：artifacts/<变体>/php-7.3.33-amd64.oci.tar
bash scripts/verify-artifact.sh   # 全套验收：功能、扩展、数据库与缓存真实读写、TLS/CA、FPM 生命周期、扫描、上游 PHPT
```

## 验收结果

最近一次模板构建（2026-10-23，amd64）：

- **全套验收通过**：扩展与 Loader 版本逐项核对（memcache 4.0.5.2、memcached 3.4.0、redis 6.0.2、swoole 4.8.13、xdebug 3.1.6、mongodb 1.16.2、zstd 0.18.0、event 3.1.6、apcu 5.1.28、imagick 3.8.1、hprose 1.8.0、ionCube 15.5.1、SourceGuardian 17.0.0）；ionCube / SourceGuardian 在 CLI 与 FPM worker 中加载，ionCube 与 Xdebug 互斥；libgd 旋转回归 210 组；可选扩展离线功能；git 2.54.0 与 Composer 2.10.3；Redis 6.0.2 接口基线与真实读写；MySQL / PostgreSQL（无效 UTF-8 转义受控失败）/ Memcache / Memcached 真实读写；MongoDB 8.0 认证与读写；Swoole 旧类名 TCP 收发、Xdebug 3 覆盖率与跟踪；`PASSWORD_ARGON2I` / `PASSWORD_ARGON2ID` 可用；安全冒烟、mysqlnd 畸形包、HTTP 包装器、SOAP、CGI；TLS 与 CA（自建 CA、主机名、SAN、wildcard 边界）；FPM 同 worker 请求、multipart、fatal、内存耗尽 worker 退出并由 master 补充、重启与退出（上游内置 IPv6 回退，默认 `listen=9000` 正常启动）；Trivy 扫描 0 项（扫描器无法识别自编译 PHP 与闭源 Loader，0 项不等于没有漏洞）。
- **上游 PHPT**（官方 `run-tests.php`，非 root、断网）：共 756 个用例（补丁附带 102 个 + GD、PCRE、mbregex、zip 全套），通过 654、失败 48、跳过 54。失败项逐项核实，**没有安全修复缺失**：
  - 22 项为新版系统库的输出差异：外部 libgd / FreeType 15 项（警告文案、包围盒与缩放尺寸差 1–2 像素；溢出类用例均被安全拒绝）、系统 PCRE2 10.49 的错误文案与偏移 5 项（其中 bug70345 的 lookaround 内 `\K` 在新版直接编译拒绝）、musl locale 1 项、musl `crypt` 失败标记为 `*` 而非 `*0` 1 项（bcrypt_salt_dollar，非法盐仍被拒绝）；
  - 22 项为测试夹具不完整：mysqli GHSA-r6x9 14 项（7.3 源码的 `fake_server.inc` 缺少对应服务端函数）、GHSA-hgf5 3 项（测试框架缺 `phpt_notify_server_start()`）、OpenSSL GHSA-xr7j 与 `san_*` 5 项（证书生成器忽略 SAN，`san_peer_matching` 的静态证书为 2013 年 SHA1 / 1024 位且已过期）。只替换测试夹具（7.4.33 的 `fake_server.inc` 与证书生成器、8.1.34 的测试框架，仅做 PHP 7.3 语法 / API 适配；同 SAN / Subject 的 SHA256 / 2048 位等价证书），在同一构建阶段镜像以 nobody、断网复跑：GHSA-hgf5 3/3、OpenSSL 5/5、mysqli 13/14 通过。剩余的 `eof-warning-count`：期望的 3 条越界保护告警全部出现，多出的“server has gone away / Error reading result set's header”来自假服务器在收到查询后关闭连接，PHP 7.4 起 mysqlnd 在 `CR_SERVER_GONE_ERROR` 时不再告警，同一用例在 7.4.33 上通过，属版本告警语义差异。命令、夹具（原文件、适配版与摘要）与结果见 `artifacts/default/upstream-phpt/rerun-*/`；
  - 2 项为运行环境限制：内置 CLI 服务器启动横幅混入输出（GHSA-c5f2、GHSA-4w77，修复本身的拒绝信息已出现）；
  - 2 项为运行资源限制：`soap_qname_crash`（GHSA-453j）与 SOAP GHSA-cj93-vc83-wgqv 需要超过 3G 内存，主运行未产生输出；以同一构建阶段镜像、nobody、断网、`--memory 12g` 单独复跑通过（用例未改动）。
- **产物**：OCI SHA-256 `57bbdd4f699cb7b61792808ee0440080220f3c3b8d0eada84fc7a92a0f8d5bfe`；清单 `sha256:20e317b2…6db53d13`；配置 `sha256:f0f7f717…059d7a6c`；镜像约 118 MB。

镜像摘要在推送后补充。
