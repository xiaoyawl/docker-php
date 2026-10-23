<?php
// 用途：只读导出 Redis 扩展公开接口和新对象默认选项；不连接 Redis 服务。
$snapshot = array('version' => phpversion('redis'), 'classes' => array(), 'defaults' => array());
foreach (array('Redis', 'RedisArray', 'RedisCluster', 'RedisException') as $class) {
    if (!class_exists($class, false)) { fwrite(STDERR, '缺少扩展类：'.$class."\n"); exit(1); }
    $reflection = new ReflectionClass($class);
    $methods = array();
    foreach ($reflection->getMethods(ReflectionMethod::IS_PUBLIC) as $method) {
        $parameters = array();
        foreach ($method->getParameters() as $parameter) {
            $parameters[] = array($parameter->getName(), $parameter->isOptional(), $parameter->isPassedByReference());
        }
        $methods[$method->getName()] = array($method->getNumberOfRequiredParameters(),
            $method->getNumberOfParameters(), $method->isStatic(), $parameters);
    }
    ksort($methods);
    $constants = $reflection->getConstants();
    ksort($constants);
    $snapshot['classes'][$class] = array('methods' => $methods, 'constants' => $constants);
}
$redis = new Redis();
foreach (array('OPT_SERIALIZER', 'OPT_PREFIX', 'OPT_READ_TIMEOUT', 'OPT_SCAN', 'OPT_TCP_KEEPALIVE') as $name) {
    if (defined('Redis::'.$name)) {
        try { $snapshot['defaults'][$name] = $redis->getOption(constant('Redis::'.$name)); }
        catch (RedisException $error) { $snapshot['defaults'][$name] = array('exception' => get_class($error), 'message' => $error->getMessage()); }
    }
}
if (isset($argv[1]) && $argv[1] === '--fingerprint') {
    echo json_encode($snapshot, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)."\n";
} else {
    // 基线按实际 Redis 扩展版本选取：tests/fixtures/redis-<版本>-api.json，由 --fingerprint 导出。
    $version = phpversion('redis');
    $baseline = __DIR__.'/fixtures/redis-'.$version.'-api.json';
    if (!is_file($baseline)) { fwrite(STDERR, "缺少 Redis $version 接口基线：$baseline\n"); exit(1); }
    $expected = json_decode(file_get_contents($baseline), true);
    // 基线经 JSON 导出（0.0 会写成 0），比较前把实际快照同样做一次 JSON 往返，统一数值类型。
    $actual = json_decode(json_encode($snapshot), true);
    if ($actual !== $expected) { fwrite(STDERR, "Redis 接口或默认选项与 $version 基线不一致\n"); exit(1); }
    echo "Redis $version 公开接口、常量和默认选项与基线一致\n";
}
