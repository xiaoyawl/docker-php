<?php
// 用途：仅连接一次性隔离 Redis，验证常用接口与数据格式。
ob_start();
function redis_check($condition, $message) {
    if (!$condition) { fwrite(STDERR, 'Redis 兼容验证失败：'.$message."\n"); exit(1); }
}
require __DIR__.'/redis-api.php';
$host = getenv('PHP_TEST_REDIS_HOST') ?: 'services';
$redis = new Redis();
redis_check($redis->connect($host, 6379, 3.0), '连接');
redis_check($redis->getOption(Redis::OPT_SERIALIZER) === Redis::SERIALIZER_NONE, '默认序列化关闭');
redis_check($redis->getOption(Redis::OPT_PREFIX) === null, '默认未设置键名前缀');
$prefix = 'php_compat_'.bin2hex(openssl_random_pseudo_bytes(8)).':';
redis_check($redis->setOption(Redis::OPT_PREFIX, $prefix), '键名前缀');
redis_check($redis->get('missing') === false, '不存在的键返回 false');
redis_check($redis->set('text', '中文🚀') === true && $redis->get('text') === '中文🚀', '中文字符串及布尔返回值');
redis_check($redis->set('binary', "\0\xff\r\n") && $redis->get('binary') === "\0\xff\r\n", '二进制字符串');
redis_check($redis->set('number', 42) && $redis->get('number') === '42', '默认模式数字返回字符串');
redis_check($redis->set('expire', 'ok', array('nx', 'ex' => 60)) === true, 'SET NX EX');
redis_check($redis->set('expire', 'other', array('nx', 'ex' => 60)) === false, 'SET NX 冲突返回 false');
redis_check($redis->ttl('expire') > 0, '过期时间');
redis_check($redis->hMSet('hash', array('a' => '中文', 'b' => '2')) === true, 'Hash 写入');
redis_check($redis->hMGet('hash', array('a', 'missing')) === array('a' => '中文', 'missing' => false), 'Hash 返回值与缺失字段');
redis_check($redis->rPush('list', 'a', 'b') === 2 && $redis->lRange('list', 0, -1) === array('a', 'b'), 'List');
redis_check($redis->sAdd('set', 'a', 'b') === 2 && $redis->sIsMember('set', 'a') === true, 'Set');
redis_check($redis->zAdd('zset', 1, 'a', 2, 'b') === 2, 'Sorted Set 写入');
redis_check($redis->zPopMax('zset') === array('b' => 2.0), 'ZPOPMAX');
redis_check($redis->zPopMin('zset') === array('a' => 1.0), 'ZPOPMIN');
$pipeline = $redis->multi(Redis::PIPELINE)->set('pipeline', 'ok')->get('pipeline')->exec();
redis_check($pipeline === array(true, 'ok'), 'Pipeline 返回值');
$transaction = $redis->multi()->incr('counter')->get('counter')->exec();
redis_check($transaction === array(1, '1'), '事务返回值');
redis_check($redis->eval('return redis.call("GET", KEYS[1])', array('text'), 1) === '中文🚀', 'Lua EVAL 自动应用键名前缀');
$raw = new Redis();
redis_check($raw->connect($host, 6379, 3.0), '原始数据连接');
$value = array('中文' => '🚀', 'zero' => 0, 'false' => false, 'null' => null, 'nested' => array(1, '2'));
redis_check($redis->setOption(Redis::OPT_SERIALIZER, Redis::SERIALIZER_PHP), 'PHP 序列化开关');
redis_check($redis->set('serialized', $value) && $redis->get('serialized') === $value, 'PHP 序列化往返');
redis_check($raw->get($prefix.'serialized') === serialize($value), '现网 PHP 序列化存储格式');
redis_check($redis->setOption(Redis::OPT_SERIALIZER, Redis::SERIALIZER_NONE), '恢复默认序列化');
$persistent = new Redis();
redis_check($persistent->pconnect($host, 6379, 3.0, $prefix.'persistent'), '持久连接');
redis_check($persistent->get($prefix.'text') === '中文🚀', '持久连接读取');
$persistent->close();
// 在测试进程中切换 Session 存储，不修改镜像配置及业务 Session。
ini_set('session.save_handler', 'redis');
ini_set('session.save_path', 'tcp://'.$host.':6379?prefix='.$prefix.'session:');
ini_set('session.use_cookies', '0');
ini_set('session.cache_limiter', '');
$id = bin2hex(openssl_random_pseudo_bytes(16));
session_id($id);
redis_check(session_start(), 'Redis Session 启动');
$_SESSION['compat'] = $value;
session_write_close();
$_SESSION = array();
session_id($id);
redis_check(session_start() && $_SESSION['compat'] === $value, 'Redis Session 写入后重新读取');
session_destroy();
$keys = $raw->keys($prefix.'*');
if ($keys) { $raw->del($keys); }
$redis->close();
$raw->close();
echo 'Redis ', phpversion('redis'), " 字符串、二进制、类型与返回值、过期、数据结构、Pipeline、事务、Lua、序列化、持久连接和 Session 验证通过\n";
ob_end_flush();
