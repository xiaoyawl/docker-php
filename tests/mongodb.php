<?php
// 仅连接测试脚本启动的临时 MongoDB；使用临时口令，禁止传入线上地址。
function mongo_check($ok, $message) {
    if (!$ok) { fwrite(STDERR, 'MongoDB 验证失败：'.$message."\n"); exit(1); }
}
$manager = new MongoDB\Driver\Manager('mongodb://mongo:27017', array(
    'username'=>'audit', 'password'=>getenv('PHP_TEST_MONGO_PASSWORD'),
    'authSource'=>'admin', 'authMechanism'=>'SCRAM-SHA-256',
    'serverSelectionTimeoutMS'=>3000
));
$namespace = 'php_image_audit.sample';
$text = '中文🚀';
$binary = new MongoDB\BSON\Binary("二进制\x00\xff", MongoDB\BSON\Binary::TYPE_GENERIC);
$bulk = new MongoDB\Driver\BulkWrite();
$id = $bulk->insert(array('text'=>$text, 'binary'=>$binary, 'count'=>1));
$result = $manager->executeBulkWrite($namespace, $bulk);
mongo_check($result->getInsertedCount() === 1, '写入');
$rows = $manager->executeQuery($namespace, new MongoDB\Driver\Query(array('_id'=>$id)))->toArray();
mongo_check(count($rows) === 1 && $rows[0]->text === $text && $rows[0]->binary->getData() === "二进制\x00\xff", '中文和二进制读取');
$bulk = new MongoDB\Driver\BulkWrite();
$bulk->update(array('_id'=>$id), array('$inc'=>array('count'=>2)));
mongo_check($manager->executeBulkWrite($namespace, $bulk)->getModifiedCount() === 1, '更新');
$rows = $manager->executeQuery($namespace, new MongoDB\Driver\Query(array('_id'=>$id)))->toArray();
mongo_check($rows[0]->count === 3, '更新后读取');
$bulk = new MongoDB\Driver\BulkWrite();
$bulk->delete(array('_id'=>$id));
mongo_check($manager->executeBulkWrite($namespace, $bulk)->getDeletedCount() === 1, '删除');
$rows = $manager->executeQuery($namespace, new MongoDB\Driver\Query(array('_id'=>$id)))->toArray();
mongo_check(count($rows) === 0, '空结果');
$version = $manager->executeCommand('admin', new MongoDB\Driver\Command(array('buildInfo'=>1)))->toArray();
echo 'MongoDB '.$version[0]->version.'：SCRAM-SHA-256 认证、增删改查、中文和二进制回归通过'."\n";
