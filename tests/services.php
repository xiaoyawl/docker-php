<?php
function ensure($ok, $message) {
    if (!$ok) { fwrite(STDERR, '集成验证失败：'.$message."\n"); exit(1); }
}
$host = 'services'; $user = 'php_test'; $pass = getenv('PHP_TEST_DB_PASSWORD');
ensure(is_string($pass) && $pass !== '', '缺少临时数据库口令');
$mysqli = new mysqli($host, $user, $pass, 'php_test');
ensure(!$mysqli->connect_errno, 'mysqli 连接');
ensure($mysqli->set_charset('utf8mb4'), 'mysqli 字符集');
ensure($mysqli->query('CREATE TABLE IF NOT EXISTS sample (value VARCHAR(100)) CHARACTER SET utf8mb4'), '建表');
$text = '中文🚀';
$stmt = $mysqli->prepare('INSERT INTO sample(value) VALUES (?)');
$stmt->bind_param('s', $text);
ensure($stmt->execute(), 'mysqli 参数查询');
$pdo = new PDO('mysql:host='.$host.';dbname=php_test;charset=utf8mb4', $user, $pass);
ensure($pdo->query('SELECT value FROM sample LIMIT 1')->fetchColumn() === $text, 'PDO MySQL 中文读取');
// ext/mysql 只在 PHP 5 提供，PHP 7 起上游已移除。
if (function_exists('mysql_connect')) {
    $mysql = mysql_connect($host, $user, $pass);
    ensure($mysql && mysql_select_db('php_test', $mysql) && mysql_set_charset('utf8mb4', $mysql), 'mysql 兼容接口');
    $row = mysql_fetch_row(mysql_query('SELECT value FROM sample LIMIT 1', $mysql));
    ensure($row[0] === $text, 'mysql 中文读取');
}
$stmt = $mysqli->prepare('SELECT value, CAST(42 AS SIGNED), CAST(1.25 AS DOUBLE), CAST(\'2026-10-22\' AS DATE), CAST(\'12:34:56\' AS TIME) FROM sample LIMIT 1');
ensure($stmt->execute(), 'mysqlnd 预处理二进制行协议');
$stmt->bind_result($binaryText, $binaryInt, $binaryFloat, $binaryDate, $binaryTime);
ensure($stmt->fetch() && $binaryText === $text && $binaryInt == 42 && $binaryFloat == 1.25 && $binaryDate === '2026-10-22' && $binaryTime === '12:34:56', 'mysqlnd 二进制类型解码');
$pg = pg_connect('host='.$host.' dbname=php_test user='.$user.' password='.$pass);
ensure($pg !== false, 'PostgreSQL 原生接口连接');
ensure(pg_query($pg, 'CREATE TABLE sample (value TEXT)') !== false, 'PostgreSQL 建表');
ensure(pg_query_params($pg, 'INSERT INTO sample(value) VALUES ($1)', array($text)) !== false, 'PostgreSQL 中文参数查询');
$pgPdo = new PDO('pgsql:host='.$host.';dbname=php_test', $user, $pass);
ensure($pgPdo->query('SELECT value FROM sample LIMIT 1')->fetchColumn() === $text, 'PDO PostgreSQL 中文读取');
$attack = "audit\\' OR 1=1 --";
ensure(pg_query_params($pg, 'INSERT INTO sample(value) VALUES ($1)', array($attack)) !== false, 'PostgreSQL 插入转义边界样本');
$sql = pg_select($pg, 'sample', array('value' => $attack), PGSQL_DML_STRING);
ensure(is_string($sql), 'PostgreSQL 生成条件 SQL：'.var_export($sql, true));
$selected = pg_query($pg, $sql);
ensure($selected !== false && pg_num_rows($selected) === 1 && pg_fetch_result($selected, 0, 0) === $attack,
    'PostgreSQL 字符串字面量不允许反斜线突破：'.$sql);
// GHSA-hrwm-9436-5mv3（CVE-2025-1735）：无效 UTF-8 转义必须受控失败，不能返回未转义字符串。
// 5.6 回补返回 false；7.x 抛出 Exception；8.x 抛出 ValueError（Error 子类）。PHP 5.6 能解析 Throwable，只是不会匹配。
$escapeFailed = false;
try {
    $escapeFailed = @pg_escape_string($pg, "\xff") === false;
} catch (Exception $error) {
    $escapeFailed = $error->getMessage() === 'Escaping string failed';
} catch (Throwable $error) {
    $escapeFailed = $error instanceof ValueError;
}
ensure($escapeFailed, 'PostgreSQL 无效 UTF-8 转义受控失败（返回 false 或抛出异常）');
require __DIR__.'/redis-compat.php';
$memcache = new Memcache();
ensure($memcache->connect($host, 11211), 'Memcache 连接');
ensure($memcache->set('php_test', $text, 0, 60) && $memcache->get('php_test') === $text, 'Memcache 读写');
$memcached = new Memcached();
$memcached->addServer($host, 11211);
ensure($memcached->set('php_test_2', $text, 60) && $memcached->get('php_test_2') === $text, 'Memcached 读写');
echo "MySQL 三类接口及二进制行、PostgreSQL 两类接口与转义边界、中文、Redis、Memcache、Memcached 真实读写验证通过\n";
