<?php
// 在一次性断网容器验证新增模块，不连接业务数据库或缓存。
function additional_check($ok, $message) {
    if (!$ok) { fwrite(STDERR, '新增扩展验证失败：'.$message."\n"); exit(1); }
}
// 扩展版本由 tests/verify.py 按 config/extensions.json 统一核对，此处只验证功能。
foreach (array('mongodb', 'event', 'zstd') as $module) {
    additional_check(extension_loaded($module), $module.' 已加载');
}
$text = str_repeat("中文\0🚀", 1024);
additional_check(bzdecompress(bzcompress($text)) === $text, 'bz2 二进制往返');
additional_check(zstd_uncompress(zstd_compress($text)) === $text, 'zstd 二进制往返');
additional_check(zstd_uncompress(zstd_compress('')) === '', 'zstd 空字符串往返');
additional_check(@zstd_uncompress("\x00\xff损坏帧") === false, 'zstd 拒绝损坏帧');
additional_check(@zstd_compress($text, 9999) === false, 'zstd 拒绝越界压缩级别');
$dictionary = str_repeat('字典内容', 128);
$compressed = zstd_compress_dict($text, $dictionary);
additional_check(is_string($compressed) && zstd_uncompress_dict($compressed, $dictionary) === $text, 'zstd 字典往返');
$path = sys_get_temp_dir().'/php-zstd-'.getmypid();
$stream = fopen('compress.zstd://'.$path, 'wb');
additional_check($stream !== false && fwrite($stream, $text) === strlen($text), 'zstd 写入流');
fclose($stream);
additional_check(file_get_contents('compress.zstd://'.$path) === $text, 'zstd 读取流');
unlink($path);
// mongodb 1.x 提供 fromPHP/toPHP 函数，2.x 起改为 MongoDB\BSON\Document 类。
if (function_exists('MongoDB\\BSON\\fromPHP')) {
    $document = MongoDB\BSON\toPHP(MongoDB\BSON\fromPHP(array('text'=>$text, 'number'=>42, 'null'=>null)));
} else {
    $document = MongoDB\BSON\Document::fromPHP(array('text'=>$text, 'number'=>42, 'null'=>null))->toPHP();
}
additional_check($document->text === $text && $document->number === 42 && $document->null === null, 'BSON 二进制往返');
$rejected = false;
try {
    if (function_exists('MongoDB\\BSON\\toPHP')) { MongoDB\BSON\toPHP("\x01\x00\x00\x00\x00"); }
    else { MongoDB\BSON\Document::fromBSON("\x01\x00\x00\x00\x00")->toPHP(); }
}
catch (Exception $e) { $rejected = true; }
additional_check($rejected, 'BSON 拒绝不合法长度');
$base = new EventBase();
$fired = false;
$timer = Event::timer($base, function () use (&$fired) { $fired = true; });
additional_check($timer->add(0.01), 'Event 添加定时器');
$base->dispatch();
additional_check($fired, 'Event 定时回调');
$pair = EventBufferEvent::createPair($base);
$received = '';
$pair[1]->setCallbacks(function ($buffer) use (&$received, $base) {
    $received .= $buffer->read(4096);
    $base->stop();
}, null, null);
$pair[0]->enable(Event::WRITE);
$pair[1]->enable(Event::READ);
$timeout = Event::timer($base, function () use ($base) { $base->stop(); });
$timeout->add(2);
$pair[0]->write('Event套接字数据');
$base->dispatch();
additional_check($received === 'Event套接字数据', 'Event 成对缓冲套接字收发');
$pair[0]->free();
$pair[1]->free();
$base = new EventBase();
$pair = EventBufferEvent::createPair($base);
$pair[1]->setCallbacks(function ($buffer) {
    throw new Exception('预期的读回调异常');
}, null, null);
$pair[0]->enable(Event::WRITE);
$pair[1]->enable(Event::READ);
$pair[0]->write('触发读回调异常');
$caught = false;
try { $base->dispatch(); }
catch (Exception $e) { $caught = $e->getMessage() === '预期的读回调异常'; }
additional_check($caught, 'Event 读回调异常受控返回');
$pair[0]->free();
$pair[1]->free();
$base = new EventBase();
$buffer = new EventBufferEvent($base);
$buffer->setCallbacks(null, null, function ($self, $flags) {
    throw new Exception('预期的状态回调异常');
});
$buffer->connect('127.0.0.1:1');
$caught = false;
try { $base->dispatch(); }
catch (Exception $e) { $caught = $e->getMessage() === '预期的状态回调异常'; }
additional_check($caught, 'Event 状态回调异常受控返回');
$buffer->free();
echo "MongoDB BSON、bz2/zstd 压缩与流、畸形输入、Event 定时和缓冲套接字验证通过\n";
