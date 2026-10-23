# LookBack PHP 8.1.34 镜像

![PHP](https://img.shields.io/badge/PHP-8.1.34-777BB4)
![Alpine](https://img.shields.io/badge/Alpine-3.24-0D597F)
![架构](https://img.shields.io/badge/架构-amd64-blue)
![维护状态](https://img.shields.io/badge/上游-EOL-B0332B)

本分支 `php-8.1.34` 构建 `benyoo/php-alpine:8.1.34.<构建日>-swoole5`、`benyoo/php-alpine:8.1.34.<构建日>-swoole6`：基于 Alpine 3.24 从源码编译 PHP 8.1.34，纳入可信安全回补、现代依赖适配、常用数据库与缓存扩展、官方 Loader，并在构建时更新 CA 信任库。

- 仓库：<https://git.dwhd.org/lookback/docker-php>（每个 PHP 版本一个分支，命名 `php-<版本>`，`master` 对应 8.5.12）
- 镜像：<https://hub.docker.com/r/benyoo/php-alpine>
- PHP 8.1 已停止上游维护（EOL，2025-12-31）。本镜像只回补公开的安全修复，**不等于获得官方安全支持**。

镜像按 Swoole 主版本分变体，每个镜像只含一个 Swoole：`-swoole5` 含 Swoole 5.1.8；`-swoole6` 含 Swoole 6.1.10。除 Swoole 外其余内容相同。

## 快速使用

```bash
# 默认启动 PHP-FPM（9000 端口）与 crond，由 Supervisor 管理
docker run -d --name php81 -v /data/wwwroot:/data/wwwroot benyoo/php-alpine:8.1.34.<构建日>-swoole5

# 按需开启扩展（第三方扩展与 Loader 默认全部关闭）
docker run -d -e REDIS=enable -e MEMCACHE=enable -e SWOOLE=enable -e IONCUBE=enable \
    benyoo/php-alpine:8.1.34.<构建日>-swoole5

# 执行一次性命令（不启动 FPM）
docker run --rm benyoo/php-alpine:8.1.34.<构建日>-swoole5 php -v
docker run --rm -v "$PWD":/data/wwwroot benyoo/php-alpine:8.1.34.<构建日>-swoole5 composer install
```

## 版本明细

### 系统与核心组件

| 组件 | 版本 | 说明 |
|---|---|---|
| 基础镜像 | `benyoo/alpine:3.24.20260615` | 固定 OCI 索引摘要 `sha256:7b08066d…ac45d9d`，构建与运行两阶段相同 |
| PHP | 8.1.34（NTS） | CLI、FPM、CGI；安装目录 `/usr/local/php` |
| OpenSSL | 3.5.9 | 系统库；PHP 已打 OpenSSL 3.0 兼容补丁 |
| cURL | 8.22.0 | 系统库 |
| ICU | 78.1 | intl 扩展使用 |
| libxml2 | 2.13.9 | 系统库；已打 libxml2 2.12/2.13 兼容补丁 |
| SQLite | 3.53.4 | 系统库 |
| PCRE2 | 10.49（系统） | `--with-external-pcre`，不使用 PHP 内置 PCRE2 |
| Oniguruma | 6.9.10 | mbregex 使用 |
| libzip | 1.11.4 | 系统库 |
| libgd | 2.3.3 + 两项上游修复 | 自行编译到 `/opt/libgd`，PHP 以外部 GD 链接，见“适配改动” |
| libmongoc / libbson | 2.5.6（mongodb 扩展捆绑） | MongoDB 2.x 需要 libmongoc 2.x，Alpine 3.24 只有 1.30；许可文件随镜像保存 |
| GNU libiconv | 1.18 | 安装到 `/opt/libiconv`，提供完整的 GBK / GB18030 转换 |
| 时区数据库 | timezonedb 2026.5 | 官方 PECL 时区库，默认加载，不依赖系统 tzdata |
| CA 证书包 | ca-certificates（构建时安装并执行 `update-ca-certificates`） | PHP OpenSSL、cURL 与 `SSL_CERT_FILE` 统一使用 `/etc/ssl/certs/ca-certificates.crt`；bundle 摘要 `5961c0a3…f568b` |
| Composer | 2.10.3 | 最新稳定版（要求 PHP ≥ 7.2.5） |
| git | 2.54.0 | 含 ssh 客户端，供 Composer 拉取源码依赖 |

镜像内 `/usr/local/share/php-build/` 保存了来源锁、扩展清单、补丁序列与 CA 摘要，`/usr/local/php/build-apk-packages.txt` 保存了构建时全部 apk 包版本。

### 原生扩展

默认加载（64 个模块，完整清单见 `config/extensions.json` 的 `native_modules`）：

bcmath、bz2、calendar、ctype、curl、date、dba（gdbm / cdb / cdb_make / db4 / inifile / flatfile）、dom、enchant、exif、fileinfo、filter、ftp、gd（外部 libgd，WebP 与 AVIF 已启用）、gettext、gmp、hash、iconv、imap、intl、json、ldap、libxml、mbstring、mysqli、mysqlnd、odbc、openssl、pcntl、pcre、PDO（dblib / mysql / odbc / pgsql / sqlite）、pgsql、Phar、posix、pspell、readline、Reflection、session、shmop、SimpleXML、snmp、soap、sockets、sodium（含 argon2 密码哈希）、SPL、sqlite3、standard、sysvmsg、sysvsem、sysvshm、tidy、tokenizer、xml、xmlreader、xmlwriter、xsl、zip、zlib，以及默认开启的 OPcache。

configure 参数见 [`config/php-configure.txt`](config/php-configure.txt)。

### 可选扩展与 Loader

全部默认关闭，通过环境变量开启（值为 `enable`）。

| 扩展 | 版本 | 开关 | 说明 |
|---|---|---|---|
| redis | 6.3.0 | `REDIS` | 启用 Session 处理，不引入 igbinary / LZF |
| memcache | 8.2 | `MEMCACHE` | 支持 PHP 8 的分支 |
| memcached | 3.4.0 | `MEMCACHE` | 与 memcache 同一开关；启用 SASL |
| mongodb | 2.5.5 | `MONGODB` | 使用扩展捆绑的 libmongoc / libbson 2.5.6（系统 1.30 不满足 2.x 要求） |
| swoole | 5.1.8 / 6.1.10 | `SWOOLE` | `-swoole5` 含 5.1.8、`-swoole6` 含 6.1.10；编译 openssl、sockets、curl hook、mysqlnd（U6）；Swoole 5/6 已移除 `swoole_server` 等旧类名，需使用 `Swoole\Server` |
| xdebug | 3.5.3 | `XDEBUG` | 默认 `xdebug.mode=debug`、按触发启动 |
| apcu | 5.1.28 | `APCU` | CLI 下需 `apc.enable_cli=1` |
| event | 3.1.6 | `EVENT` | 链接系统 libevent |
| zstd | 0.18.0 | `ZSTD` | 链接系统 libzstd |
| imagick | 3.8.1 | `IMAGICK` | 运行镜像含 imagemagick 格式模块 |
| FFI | 8.1.34（内置） | `FFI` | 以共享模块编译，开启时同时设置 `ffi.enable=1` |
| ionCube Loader | 15.5.1 | `IONCUBE` | 官方 musl 版，无需 glibc 兼容层；与 Xdebug 互斥 |
| SourceGuardian Loader | 17.0.0 | `SOURCEGUARDIAN` | 官方 glibc 版，依赖 gcompat 与 libudev-zero |

扩展的版本、编译参数与开关统一定义在 [`config/extensions.json`](config/extensions.json)，源码摘要见 [`sources.lock.json`](sources.lock.json)。

本版本不提供以下开关，开启时容器会报错退出，不会静默忽略：

| 开关 | 原因 |
|---|---|
| `MONGO` | 旧版 mongo 驱动（`MongoClient`）只支持 PHP 5；请使用 `MONGODB` 新驱动 |
| `HPROSE` | hprose-pecl 1.8.0 使用 PHP 8 已删除的 `TSRMLS_DC` 等宏，编译失败；上游最后提交为 2020-03-21，没有 PHP 8 版本。PHP 8 业务可改用纯 PHP 实现的 Composer 包 hprose/hprose-php |

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

补丁序列见 [`patches/series`](patches/series)，共 37 项，按顺序严格应用：任何补丁无法干净应用或没有实际改动文件，构建立即中止，不允许模糊匹配。补丁数量不等于漏洞数量。

- **来源**：Debian 维护者 Ondřej Surý 的 PHP 8.1 源码包（`php8.1_8.1.34-9+0~20261021.82+debian12~1.gbp4e430a`）。构建时验证其签名链：InRelease 签名 → Sources 索引 → 补丁包摘要。另有本地补丁（09xx）。
- **`security/`（29 项）**：安全修复。补丁中引用的编号如下（另有未分配编号的上游安全 bug 修复）：
  - CVE（11 个）：CVE-2025-14179、CVE-2026-109618、CVE-2026-109619、CVE-2026-6722、CVE-2026-6735、CVE-2026-7258、CVE-2026-7259、CVE-2026-7261、CVE-2026-7262、CVE-2026-7568、CVE-2026-9672
  - GHSA（23 个）：GHSA-62xp-839h-2637、GHSA-6wmf-4rv5-p3rp、GHSA-7qg2-v9fj-4mwv、GHSA-7qpv-r5mr-78m4、GHSA-85c2-q967-79q5、GHSA-88hq-2827-7pg6、GHSA-96wq-48vp-hh57、GHSA-9f67-6fw4-hpfp、GHSA-ch8v-r6jh-4vvr、GHSA-cj93-vc83-wgqv、GHSA-fpwc-w8rq-cr92、GHSA-hmxp-6pc4-f3vv、GHSA-j3wh-g957-2m85、GHSA-m33r-qmcv-p97q、GHSA-m8rr-4c36-8gq4、GHSA-r6x9-5r99-36j7、GHSA-rgrp-mwpx-f6rm、GHSA-vc5h-9ppw-p5f3、GHSA-vvx9-73fr-5jjx、GHSA-w476-322c-wpvm、GHSA-w8hw-w9fx-j79w、GHSA-wm6j-2649-pv75、GHSA-xr7j-rvgx-xq5p
- **重点**：CVE-2026-109618 / 109619（内存耗尽中断与请求状态残留导致的状态破坏）由补丁 0083 回补。该补丁在部分内存耗尽路径会让 worker 以 `_exit(1)` 退出，由 FPM master 补充新进程。
- **本地安全补丁**：0902 HTTP 包装器边界加固，0905 mysqlnd OK 消息按实际负载长度校验。
- GHSA-r6x9-5r99-36j7（mysqlnd 多处包越界读）在 8.1 上为完整修复（Surý 0071）。
- GHSA-hrwm-9436-5mv3 已含于上游 8.1.34：`pg_escape_string()` 遇无效编码时抛出 `ValueError`；含 NUL 的 bcrypt 密码、DNS 主机名同样抛出 `ValueError`（PHP 8 的参数校验方式）。
- HTTP 头字段值含 NUL 时，PHP 8 上游会完整保留该值（不截断、不拆分成多个头），本镜像接受上游行为、未增加本地补丁；这与 5.6 镜像直接拒绝不同，安全回归按“拒绝或完整保留”断言。
- **`compat/`（8 项）**：构建与依赖适配、外部 GD 兼容，以及只调整测试的上游补丁，见“适配改动”。

## 适配改动

| 适配 | 原因 | 处理 |
|---|---|---|
| 现代依赖兼容（`patches/compat/`） | PHP 8.1 原生不支持新版 GCC 属性检测宏与 musl 的部分签名；另有只调整测试的上游补丁 | Surý 同分支兼容补丁，加上本地 0900（musl `fopencookie` 定位签名） |
| 外部 GD 兼容 | 外部 libgd 2.3.3 遗漏 BICUBIC 缩放模式 | 本地 0906 按上游 libgd [a5f5698](https://github.com/libgd/libgd/commit/a5f5698a6832fc1f8179a9257f0b91c9a8ef496b) 兼容 BICUBIC，原两段构建（内核层 + 兼容层）已并入单一补丁序列；上游参考见 `provenance/external-gd/` |
| 补丁版 libgd | Alpine 的 gd-2.3.3-r10 未打补丁：调色板图像旋转 180° 会释放调用方原图（释放后使用），最近邻插值旋转会空指针崩溃 | 自行编译 libgd 2.3.3，加入上游 [6cc1e39](https://github.com/libgd/libgd/commit/6cc1e39e9fddd15ae74adb1a09fcd5740f44923e) 与 [a656f5c](https://github.com/libgd/libgd/commit/a656f5cc5592757996e9e96b0821a0966bfaa3b3)，经 pkg-config 发现、以 rpath 链接 |
| MongoDB 2.x 捆绑 C 驱动 | mongodb 2.5.5 需要 libmongoc 2.x，Alpine 3.24 只提供 1.30 | `--with-mongodb-system-libs=no` 使用扩展捆绑的 libmongoc / libbson 2.5.6，许可文件随镜像保存，`provenance/mongo-c-driver-2.5.6/` 保存许可清单 |
| 外部 GD 的 JIS 映射 | PHP 只在内置 GD 时支持 JIS 映射的日文字体，外部 libgd 下 `--enable-gd-jis-conv` 被忽略 | 保留该参数（U4，与其他版本写法一致、无副作用）；实测 `gd_info()` 中 JIS-mapped Japanese Font Support 为 false |
| 统一编译参数（U1–U4） | 历史各组自行决定造成的不一致 | U1 保留 `--with-layout=GNU --with-pic --enable-shared`；U2 保留 `--with-db4`（实测 `dba_handlers()` 含 db4）与 `--with-mhash`；U3 启用 `--with-password-argon2`（实测 `PASSWORD_ARGON2ID` 已定义）、`--with-webp` 与 `--with-avif`（实测 `gd_info()` WebP、AVIF Support 均为 true）；U4 恢复 `--enable-gd-jis-conv`、`--disable-rpath` |
| 统一构建与入口（U5–U7、U10–U12） | 同上 | U5 不带 `--without-pear`；U6 Swoole 编译 openssl、sockets、curl hook、mysqlnd；U7 CFLAGS 含 `-DOPENSSL_SUPPRESS_DEPRECATED`；U10 上游 PHPT 使用统一运行器；U11 时区锁统一为 `timezonedb.lock.json`；U12 开关清单由 `config/extensions.json` 生成，不提供的开关报错 |
| FFI | PHP 7.4 起内置 | 以共享模块编译（`--with-ffi=shared`），开关 `FFI` 加载并设置 `ffi.enable=1` |
| ionCube / SourceGuardian | ionCube 有官方 musl 版；SourceGuardian 只有 glibc 版 | ionCube 直接加载；运行镜像安装 gcompat 与 libudev-zero 供 SourceGuardian 使用 |
| Composer | 默认禁用了 `proc_open` 等函数，Composer 拉取源码和执行脚本需要 | `composer` 命令只为自身进程清空禁用函数，业务 FPM / CLI 仍保持禁用 |

## 已知问题

- **加密 Loader 只验证了加载**：没有 ionCube / SourceGuardian 加密业务样本。SourceGuardian 通过 libudev 读取硬件信息，绑定机器的加密脚本在容器内可能无法匹配。
- **Swoole 5/6 不兼容旧类名**：`swoole_server`、`swoole_client` 等已移除，业务需改用 `Swoole\Server`、`Swoole\Client`。
- **外部 GD 与 PHP 内置 GD 的数值差异**：字体包围盒、缩放与旋转后的尺寸可能相差 1–2 像素（如 `imagerotate` 结果 42×24 对内置 GD 的 40×23）。
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
# 在指定的远程 Linux 构建节点执行（只构建 amd64，不推送）
bash scripts/build-image.sh       # 产物：artifacts/<变体>/php-8.1.34-amd64.oci.tar
bash scripts/verify-artifact.sh   # 全套验收：功能、扩展、数据库与缓存真实读写、TLS/CA、FPM 生命周期、扫描
```

## 验收结果

最近一次模板构建（2026-10-23，amd64）：

- **产物**：
  - `benyoo/php-alpine:8.1.34.20261023-swoole5`：OCI SHA-256 `a28c059d2823b633e9ebd0542800f587db82e880322add1b41c41572591825ae`；清单 `sha256:280f6326…49eb9855`；配置 `sha256:63407f69…b61d10156`；镜像约 121 MB。
  - `benyoo/php-alpine:8.1.34.20261023-swoole6`：OCI SHA-256 `361efd7416d721ba4cf1568591d3dfae1ec0f53df5bb91fca112a504e1d65250`；清单 `sha256:e8c19a13…b61a608f`；配置 `sha256:18eadba2…a58dfb90d`；镜像约 121 MB。
- **全套验收通过（两个变体）**：扩展与 Loader 版本逐项核对（memcache 8.2、memcached 3.4.0、redis 6.3.0、swoole 5.1.8 / 6.1.10、xdebug 3.5.3、mongodb 2.5.5、zstd 0.18.0、event 3.1.6、apcu 5.1.28、imagick 3.8.1、FFI、ionCube 15.5.1、SourceGuardian 17.0.0）；ionCube + SourceGuardian + OPcache 组合与 FPM worker 中加载；`HPROSE` / `MONGO` 开关报错退出；libgd 旋转回归 210 组；可选扩展离线功能（Imagick、SourceGuardian、APCu、FFI）；Xdebug 3.5.3 覆盖率与跟踪；Swoole（`Swoole\Server` / `Swoole\Client`）TCP 收发；Redis 6.3.0 接口基线与真实读写；git 与 Composer；MySQL / PostgreSQL / Memcache / Memcached 真实读写；MongoDB 8.0（捆绑 libmongoc 2.5.6）；HTTP 与 mysqlnd 协议安全回归、TLS 与 CA；FPM 同 worker 请求、内存耗尽后 worker 按 0083 补丁退出并由 master 补充（清单 `fpm.oom_worker_exits=true`）、重启与退出；argon2、WebP、AVIF、db4 实测生效；扩展包许可文件（含 MongoDB 捆绑 C 驱动）随镜像保存在 `/usr/local/php/share/licenses/`；Trivy 扫描 0 项（扫描器无法识别自编译 PHP 与闭源 Loader，0 项不等于没有漏洞）。
- **上游 PHPT**（官方 `run-tests.php`，非 root、断网；与 Swoole 变体无关，在 `-swoole5` 构建阶段镜像运行）：共 526 个用例（补丁附带 80 个 + GD、PCRE 全套 + mysqlnd 安全用例），通过 459、失败 11、跳过 56；GHSA-r6x9 的 38 个伪服务端用例全部通过。失败项逐项核实，**没有安全修复缺失**，11 项均为环境或系统库差异：外部 libgd / FreeType 的字体度量 6 项、旋转与缩放尺寸 2 项（bug65148、bug73272）、PCRE2 10.49 错误文本 1 项、musl 区域设置 2 项。

镜像摘要在推送后补充。
