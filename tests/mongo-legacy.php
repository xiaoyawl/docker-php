<?php
// 旧版 mongo 驱动（MongoClient）在隔离网络连接临时 MongoDB，验证认证与实际读写。
function legacy_check($ok, $message) {
    if (!$ok) { fwrite(STDERR, '旧版 mongo 驱动验证失败：'.$message."\n"); exit(1); }
}
legacy_check(phpversion('mongo') === '1.6.16', 'mongo 版本');
legacy_check(!extension_loaded('mongodb'), '本测试单独加载旧驱动');
$password = getenv('PHP_TEST_MONGO_PASSWORD');
legacy_check(is_string($password) && $password !== '', '测试口令');
$client = new MongoClient('mongodb://mongo:27017', array(
    'username' => 'audit', 'password' => $password, 'db' => 'admin',
    'authMechanism' => 'SCRAM-SHA-1', 'connectTimeoutMS' => 5000,
));
$build = $client->selectDB('admin')->command(array('buildInfo' => 1));
legacy_check(!empty($build['ok']) && isset($build['version']), '认证后执行命令');
$collection = $client->selectCollection('php_legacy_audit', 'items');
$collection->drop();
$text = "中文\0二进制🚀";
$id = new MongoId();
$collection->insert(array('_id' => $id, 'name' => '测试', 'text' => $text,
    'bin' => new MongoBinData("\x00\xff\x10", MongoBinData::GENERIC), 'n' => 1), array('w' => 1));
$found = $collection->findOne(array('_id' => $id));
legacy_check($found['name'] === '测试' && $found['text'] === $text, '中文与 NUL 字符串往返');
legacy_check($found['bin'] instanceof MongoBinData && $found['bin']->bin === "\x00\xff\x10", '二进制往返');
$collection->update(array('_id' => $id), array('$inc' => array('n' => 41)), array('w' => 1));
$updated = $collection->findOne(array('_id' => $id));
legacy_check($updated['n'] === 42, '更新');
legacy_check($collection->count() === 1, '计数');
legacy_check(iterator_to_array($collection->find(array('name' => '不存在'))) === array(), '空结果');
$collection->remove(array('_id' => $id), array('w' => 1));
legacy_check($collection->findOne(array('_id' => $id)) === null, '删除');
$collection->drop();
$denied = false;
try {
    $bad = new MongoClient('mongodb://mongo:27017', array('username' => 'audit', 'password' => 'wrong-'.$password,
        'db' => 'admin', 'authMechanism' => 'SCRAM-SHA-1', 'connectTimeoutMS' => 5000));
    $bad->selectDB('admin')->command(array('buildInfo' => 1));
} catch (MongoException $e) {
    $denied = true;
}
legacy_check($denied, '错误口令被拒绝');
echo '旧版 mongo 驱动 SCRAM-SHA-1 认证、增删改查、中文、二进制与空结果验证通过；服务端 ', $build['version'], PHP_EOL;
