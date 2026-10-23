# LookBack PHP 8.4.27 镜像

![PHP](https://img.shields.io/badge/PHP-8.4.27-777BB4)
![Alpine](https://img.shields.io/badge/Alpine-3.24-0D597F)
![架构](https://img.shields.io/badge/架构-amd64%20%7C%20arm64-blue)
![维护状态](https://img.shields.io/badge/上游-活跃支持-2E8B57)

本分支 `php-8.4.27` 构建 `benyoo/php-alpine:8.4.27.<构建日>-<变体>`：基于 Alpine 3.24 从源码编译 PHP 8.4.27，包含官方安全修复与本地加固补丁、现代依赖适配、常用数据库与缓存扩展、官方 Loader，并在构建时更新 CA 信任库。

- 仓库：<https://git.dwhd.org/lookback/docker-php>（每个 PHP 版本一个分支，命名 `php-<版本>`，`master` 对应 8.5.12）
- 镜像：<https://hub.docker.com/r/benyoo/php-alpine>
- PHP 8.4 当前处于官方活跃支持期（安全支持至 2028-12-31）。

## 快速使用

```bash
# 默认启动 PHP-FPM（9000 端口）与 crond，由 Supervisor 管理
docker run -d --name php84 -v /data/wwwroot:/data/wwwroot benyoo/php-alpine:8.4.27.<构建日>-swoole6

# 按需开启扩展（第三方扩展与 Loader 默认全部关闭）
docker run -d -e REDIS=enable -e MEMCACHE=enable -e SWOOLE=enable -e IONCUBE=enable \
    benyoo/php-alpine:8.4.27.<构建日>-swoole6

# 执行一次性命令（不启动 FPM）
docker run --rm benyoo/php-alpine:8.4.27.<构建日>-swoole6 php -v
docker run --rm -v "$PWD":/data/wwwroot benyoo/php-alpine:8.4.27.<构建日>-swoole6 composer install
```

本版本提供以下镜像变体（每个镜像只含一个 Swoole 版本）：

| 镜像标签 | Swoole |
|---|---|
| `benyoo/php-alpine:8.4.27.<构建日>-swoole6` | Swoole 6.2.3 |

PHP 8.4 不提供 `-swoole5` 变体：Swoole 5.1.8 官方声明只支持 PHP 8.0–8.3。

## 版本明细

### 系统与核心组件

| 组件 | 版本 | 说明 |
|---|---|---|
| 基础镜像 | `benyoo/alpine:3.24.20260615` | 固定 OCI 索引摘要 `sha256:7b08066d…ac45d9d`，构建与运行两阶段相同 |
| PHP | 8.4.27（NTS） | CLI、FPM、CGI；安装目录 `/usr/local/php` |
| OpenSSL | 3.5.9 | 系统库 |
| cURL | 8.22.0 | 系统库 |
| ICU | 78.1 | intl 扩展使用 |
| libxml2 | 2.13.9 | 系统库 |
| SQLite | 3.53.4 | 系统库 |
| PCRE2 | 10.49（系统） | `--with-external-pcre` |
| Oniguruma | 6.9.10 | mbregex 使用 |
| libgd | 2.3.3 + 两项上游修复 | 自行编译到 `/opt/libgd`，见“适配改动” |
| GNU libiconv | 1.18 | 安装到 `/opt/libiconv`，提供完整的 GBK / GB18030 转换 |
| 时区数据库 | timezonedb 2026.5 | 官方 PECL 时区库，默认加载，不依赖系统 tzdata |
| CA 证书包 | ca-certificates-20261020-r0 | 构建时安装并执行 `update-ca-certificates`；PHP OpenSSL、cURL 与 `SSL_CERT_FILE` 统一使用 `/etc/ssl/certs/ca-certificates.crt`（SHA-256 `5961c0a3c6545993…`） |
| Composer | 2.10.3 | 最新稳定版 |
| git | 2.54.0 | 含 ssh 客户端，供 Composer 拉取源码依赖 |

镜像内 `/usr/local/share/php-build/` 保存了来源锁、扩展清单、补丁序列与 CA 摘要，`/usr/local/php/build-apk-packages.txt` 保存了构建时全部 apk 包版本。

### 原生扩展

默认加载（63 个模块，完整清单见 `config/extensions.json` 的 `native_modules`）：

bcmath、bz2、calendar、Core、ctype、curl、date、dba、dom、enchant、exif、fileinfo、filter、ftp、gd、gettext、gmp、hash、iconv、intl、json、ldap、libxml、mbstring、mysqli、mysqlnd、odbc、openssl、pcntl、pcre、PDO、pdo_dblib、pdo_mysql、PDO_ODBC、pdo_pgsql、pdo_sqlite、pgsql、Phar、posix、random、readline、Reflection、session、shmop、SimpleXML、snmp、soap、sockets、sodium、SPL、sqlite3、standard、sysvmsg、sysvsem、sysvshm、tidy、tokenizer、xml、xmlreader、xmlwriter、xsl、zip、zlib，以及默认开启的 OPcache。

PDO 驱动：dblib / mysql / odbc / pgsql / sqlite；DBA 处理器：gdbm / cdb / cdb_make / db4 / inifile / flatfile。configure 参数见 [`config/php-configure.txt`](config/php-configure.txt)。

### 可选扩展与 Loader

全部默认关闭，通过环境变量开启（值为 `enable`）。

| 扩展 | 版本 | 开关 | 说明 |
|---|---|---|---|
| redis | 6.3.0 | `REDIS` | 启用 Session 处理，不引入 igbinary / LZF |
| memcache | 8.2 | `MEMCACHE` | PECL 最新版 |
| memcached | 3.4.0 | `MEMCACHE` | 与 memcache 同一开关；启用 SASL |
| mongodb | 2.5.5 | `MONGODB` | 使用扩展随附的 libmongoc / libbson 2.5.6（Alpine 3.24 只有 1.30）；客户端字段加密关闭 |
| swoole | 6.2.3 | `SWOOLE` | 每个镜像只含一个 Swoole 版本，按标签后缀区分（见下） |
| xdebug | 3.5.3 | `XDEBUG` | Xdebug 3 配置；与 ionCube 互斥 |
| apcu | 5.1.28 | `APCU` |  |
| event | 3.1.6 | `EVENT` | 链接系统 libevent |
| zstd | 0.18.0 | `ZSTD` | 链接系统 libzstd |
| imagick | 3.8.1 | `IMAGICK` | 运行镜像含 imagemagick 格式模块 |
| FFI | 8.4.27 | `FFI` | PHP 内置，以共享模块编译；开启时同时设置 `ffi.enable=1` |
| ionCube Loader | 15.5.1 | `IONCUBE` | 官方 musl 版，无需 gcompat 预加载；与 Xdebug 互斥；arm64 使用官方 aarch64 glibc 版，启用时预加载 gcompat |
| SourceGuardian Loader | 17.0.0 | `SOURCEGUARDIAN` | 官方 glibc 版，依赖 gcompat 与 libudev-zero；arm64 使用官方 aarch64 版 |

扩展的版本、编译参数与开关统一定义在 [`config/extensions.json`](config/extensions.json)，源码摘要见 [`sources.lock.json`](sources.lock.json)。

### 本版本不提供的开关

开启下列开关时容器会报错退出，不会静默忽略：

| 开关 | 原因 |
|---|---|
| `MONGO` | 旧版 `mongo` 驱动（`MongoClient`）只支持 PHP 5；请使用 `MONGODB` 新驱动，旧代码可借助 Composer 包 `alcaeus/mongo-php-adapter` 过渡 |
| `HPROSE` | hprose 1.8.0（PECL 最终版）使用 PHP 8 已删除的 `TSRMLS_DC` 宏，在 PHP 8 上编译失败；上游 hprose-pecl 最后提交为 2020-03-21，没有 PHP 8 版本。替代方案：纯 PHP 实现的 Composer 包 [`hprose/hprose-php`](https://github.com/hprose/hprose-php) |

本版本也不提供原生模块 `imap`、`pspell`：PHP 8.4 起二者移出内核、改由 PECL 发布，本镜像未纳入；同时不提供 Swoole 5 变体（Swoole 5.1.8 官方只支持 PHP 8.0–8.3）。

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
| `XDEBUG_REMOTE_HOST` / `XDEBUG_REMOTE_PORT` | `localhost` / `9900` | 映射为 Xdebug 3 的 `xdebug.client_host` / `xdebug.client_port` |
| 扩展开关 | `disable` | 见上表 |

## 安全回补

- **官方修复**：PHP 8.4.27 是官方发布的源码（`php-8.4.27.tar.xz`，SHA-256 见 `sources.lock.json`），已包含截至该版本的全部官方安全修复，包括内存耗尽中断与请求状态残留导致的状态破坏（CVE-2026-109618 / CVE-2026-109619，官方 bailout 修复）。源码中带编号的安全回归用例全部在本镜像上运行通过（见“验收结果”），涉及 GHSA 33 个：GHSA-3cr5-j632-f35r、GHSA-52jp-hrpf-2jff、GHSA-54hq-v5wp-fqgv、GHSA-62xp-839h-2637、GHSA-7qg2-v9fj-4mwv、GHSA-85c2-q967-79q5、GHSA-88hq-2827-7pg6、GHSA-96wq-48vp-hh57、GHSA-9f67-6fw4-hpfp、GHSA-9fcc-425m-g385、GHSA-c5f2-jwm7-mmq2、GHSA-cj93-vc83-wgqv、GHSA-fpwc-w8rq-cr92、GHSA-h35g-vwh6-m678、GHSA-h96m-rvf9-jgm2、GHSA-hgf5-96fm-v528、GHSA-hmxp-6pc4-f3vv、GHSA-j3wh-g957-2m85、GHSA-jqcx-ccgc-xwhv、GHSA-m33r-qmcv-p97q、GHSA-pc52-254m-w9w7、GHSA-pcmh-g36c-qc44、GHSA-r6x9-5r99-36j7、GHSA-r977-prxv-hc43、GHSA-rgrp-mwpx-f6rm、GHSA-rwp7-7vc6-8477、GHSA-v8xr-gpvj-cx9g、GHSA-vc5h-9ppw-p5f3、GHSA-w8qr-v226-r27w、GHSA-wm6j-2649-pv75、GHSA-wpj3-hf5j-x4v4、GHSA-www2-q4fc-65wf、GHSA-xr7j-rvgx-xq5p。
- **本地补丁**：补丁序列见 [`patches/series`](patches/series)，共 4 项，按顺序严格应用（无法干净应用或没有实际改动文件即中止构建，不允许模糊匹配）。来源包 Surý `php8.4_8.4.27-1+0~20261021.57+debian12~1.gbp7636b9.debian.tar.xz` 的签名链（InRelease → Sources 索引 → 补丁包摘要）在构建时验证。

| 补丁 | 说明 |
|---|---|
| `compat/0045-Add-missing-header-includes.patch` | 原样提取自 Surý php8.4 打包（8.4.27-1+0~20261021.57+debian12~1.gbp7636b9）；补齐缺失的头文件声明，适配现代编译器 |
| `security/9001-mysqlnd-ok-payload-and-length-prefix.patch` | 本地 mysqlnd 加固：OK 消息按实际包边界校验，两个长度解码器拒绝非法 0xff 前缀（协议回归实测复现） |
| `compat/9002-system-gd-bicubic.patch` | 外部 libgd 2.3.3 缺少上游 a5f5698 双三次插值设置修复；仅在 libgd setter 拒绝这两个模式时按官方相同字段语义补齐 |
| `security/9003-mysqlnd-preserve-high-length-bits.patch` | 本地 mysqlnd 加固：0xfe 长度完整读取 64 位；不小于非法长度哨兵的值钳制为哨兵减一，避开 NULL/非法哨兵并由各调用处边界检查拒绝 |

`9001`、`9003` 是本地 mysqlnd 加固，由 31 项正常 / 畸形 MySQL 协议回归（`tests/mysql-protocol.py`）验证，不冒充官方补丁，也没有对应的 CVE 编号。

## 适配改动

| 适配 | 原因 | 处理 |
|---|---|---|
| 补丁版 libgd | Alpine 的 gd-2.3.3-r10 未打补丁：调色板图像旋转 180° 会释放调用方原图（释放后使用），最近邻插值旋转会空指针崩溃 | 自行编译 libgd 2.3.3，加入上游提交 [6cc1e39](https://github.com/libgd/libgd/commit/6cc1e39e9fddd15ae74adb1a09fcd5740f44923e) 与 [a656f5c](https://github.com/libgd/libgd/commit/a656f5cc5592757996e9e96b0821a0966bfaa3b3)，编译选项与 Alpine 一致；PHP 以 `--with-external-gd` 经 pkg-config 找到 `/opt/libgd`，以 rpath 链接，构建阶段不安装系统 gd-dev |
| 外部 GD 双三次插值 | libgd 2.3.3 缺少上游 a5f5698 的插值模式设置修复 | 补丁 9002 在 libgd 拒绝这两个模式时按官方相同字段语义补齐；上游参考补丁与许可保存在 `provenance/compatibility-gd/` |
| 外部 GD 的 JIS 映射 | PHP 只在内置 GD 时支持 JIS 映射的日文字体 | 保留 `--enable-gd-jis-conv`（与其他版本一致、无副作用）；`gd_info()` 中 JIS-mapped Japanese Font Support 为 false |
| 安装布局与 DBA | 统一项 U1 / U2 | 恢复 `--with-layout=GNU --with-pic --enable-shared`；恢复 `--with-db4`（DBA 提供 db4 处理器）与 `--with-mhash` |
| MongoDB 2.x | 需要 libmongoc 2.x，Alpine 3.24 只有 1.30 | 使用扩展随附的 C 驱动 2.5.6，随附驱动的许可文件一并复制到镜像 |
| ionCube / SourceGuardian | ionCube 有官方 musl 版；SourceGuardian 只有 glibc 版 | 运行镜像安装 gcompat 与 libudev-zero，供 SourceGuardian 使用 |
| Composer | 默认禁用了 `proc_open` 等函数，Composer 拉取源码和执行脚本需要 | `composer` 命令只为自身进程清空禁用函数，业务 FPM / CLI 仍保持禁用 |
| Swoole 5 / 6 | 已移除 `swoole_server`、`swoole_client` 等旧短类名 | 业务需改用 `Swoole\Server`、`Swoole\Client` 等命名空间类名；编译参数统一为 `--enable-openssl --enable-sockets --enable-swoole-curl --enable-mysqlnd` |
| FPM 内存耗尽 | 官方修复在 bailout 后安全清理请求状态 | 同一 worker 继续服务，不退出重建；验收核对内存耗尽后的请求数据与内存上限复原（与 5.6 的 `_exit(1)` 缓解不同） |
| `PHP_ZTS` 类型 | PHP 8.4 起 `PHP_ZTS` 由整数改为布尔值 | 模板测试不对 `PHP_ZTS` 做整数比较；运行信息原样记录（本版为 `false`，即 NTS） |

## 已知问题

- **Swoole 旧类名**：Swoole 5 / 6 已没有 `swoole_server`、`swoole_client` 等旧短类名，旧业务代码需改用 `Swoole\Server`、`Swoole\Client`。
- **加密 Loader 只验证了加载**：没有 ionCube / SourceGuardian 加密业务样本。SourceGuardian 通过 libudev 读取硬件信息，绑定机器的加密脚本在容器内可能无法匹配。
- **外部 GD 与 PHP 内置 GD 的数值差异**：字体包围盒、缩放与旋转后的尺寸可能相差 1–2 像素（上游 GD PHPT 有 8 项因此失败，均不崩溃）。
- **HTTP 流包装器与 5.6 镜像的差异**（均为 PHP 8 上游行为，同源、不越界，不对应 CVE / GHSA）：长度为 1 的相对 `Location`（如 `a`）解析为根路径 `/a`；空 `Location` 会同源跳转到 `/` 一次；响应头字段值中的 NUL 字节不会被拒绝，但会按长度完整保留在 `$http_response_header` 中，不截断也不拆分成新字段（5.6 镜像的本地重写会直接拒绝）。
- **Hprose 不可用**：见“本版本不提供的开关”。

## 构建与验收

所有分支使用同一套脚本，版本差异只在以下数据文件中：

| 文件 | 内容 |
|---|---|
| `config/extensions.json` | PHP 版本、原生模块清单、PECL 扩展（版本、编译参数、开关）、Loader、Swoole 变体、OPcache / FPM 特性、Composer 版本 |
| `config/php-configure.txt` | PHP configure 参数 |
| `config/build-packages.txt` / `config/runtime-packages.txt` | 构建期 / 运行期 apk 包 |
| `sources.lock.json` | 全部源码、扩展、Loader 的下载地址与 SHA-256 |
| `patches/series` 与 `patches/` | PHP 补丁及应用顺序 |
| `extension-patches.lock.json` 与 `extension-patches/` | 扩展补丁 |
| `libgd/` | 补丁版 libgd 的源码锁与补丁 |

```bash
# 在指定的远程 Linux 构建节点执行（默认 linux/amd64,linux/arm64，不推送；PLATFORMS 可只构建部分架构）
bash scripts/build-image.sh       # 产物：artifacts/<变体>/php-8.4.27.oci.tar（多架构 OCI 索引）
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

最近一次构建（2026-10-23，linux/amd64 与 linux/arm64，两种架构分别验收）：

| 镜像标签（已推送） | 索引摘要（仓库端与归档一致） | amd64 清单 | arm64 清单 | 压缩层 amd64 / arm64 | OCI 归档 SHA-256 |
|---|---|---|---|---|---|
| `benyoo/php-alpine:8.4.27.20261023-swoole6` | `sha256:a0f24c4a8b41eb0c13f1980be947c527483243b66f460e386915528fdc9be65d` | `sha256:03f0cc67e4fb2a4a930a218e9aff3a7982c7e4eefbc72f05717fb748d2af192e` | `sha256:abe79b1bfe52b6113c77a5c4a101cf77103685417d4b4e1fb3d1002723021376` | 约 126 / 125 MB | `2176700dea19bd8da0ac0b0e376b11bb1380b468e4fc3d266d94e9bb7b91b418` |

无后缀标签 `benyoo/php-alpine:8.4.27.20261023` 是 swoole6 标签的别名，指向同一索引摘要。

Trivy 扫描（每个变体与架构）：amd64 0、arm64 0 项。

- **全套验收通过（每个变体）**：PHP 版本与 63 个原生模块；扩展与 Loader 版本逐项核对；默认关闭与开关加载、不支持的开关报错；libgd 旋转回归 210 组且链接 `/opt/libgd`、未安装系统 libgd；可选扩展离线功能（含 FFI、Imagick、APCu、zstd、Event）；git 与 Composer（默认禁用函数下执行成功，业务禁用保持）；Swoole TCP 服务与客户端收发、Xdebug 3 覆盖率与跟踪；MySQL / PostgreSQL / Redis / Memcache / Memcached 真实读写；MongoDB 8.0 认证与读写；Redis 公开接口与基线一致；安全冒烟、31 项 MySQL 协议回归、HTTP 凭据 / 重定向 / 响应头、SOAP、CGI；TLS 与 CA（新增 CA 后信任、错误主机名与 SAN 不匹配拒绝、wildcard 边界）；FPM 同 worker 请求、内存耗尽后恢复、重启与退出；Trivy 扫描 0 项（扫描器无法识别自编译 PHP 与闭源 Loader，0 项不等于没有漏洞）。
- **上游 PHPT**（官方 `run-tests.php`，nobody 用户、断网，`swoole6` 变体的构建阶段）：linux/amd64 与 linux/arm64 结果相同、失败清单一致，没有 arm64 独有失败；共 612 个用例（补丁附带 0 个 + 上游安全回归、FPM 安全、mysqlnd GHSA-r6x9、PCRE、GD 全套），通过 530、失败 8、跳过 74、XFAIL 0。**安全回归用例 0 失败**。失败项逐项核实，均为外部 libgd 2.3.3 / FreeType 与 PHP 内置 GD 的数值差异，没有崩溃：`bug43073.phpt`、`bug48732-mb.phpt`、`bug48732.phpt`、`bug48801-mb.phpt`、`bug48801.phpt`、`bug53504.phpt`、`bug65148.phpt`、`bug73272.phpt`。跳过原因：requires bundled GD library 25 项；test requires GD 2.3.2 or older 20 项；Run only on Windows 6 项；upstream bugfix has not been released 3 项；resource-heavy test 3 项；slow test 3 项；meaningful only for bundled libgd 2 项；setlocale() is broken /w musl 2 项；IPv6 is not supported. 2 项；only for external libgd < 2.2.4 1 项；only for bundled libgd 1 项；windows only test 1 项；this test is for 32bit platforms only 1 项；function only available in bundled, external GD detected 1 项；windows only 1 项；Required extension missing: zend_test 1 项；Windows only 1 项。
