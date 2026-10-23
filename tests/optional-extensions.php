<?php
// 在一次性断网容器验证可选扩展的离线功能；扩展未编入当前版本时跳过，版本由 tests/verify.py 统一核对。
function optional_check($ok, $message) {
    if (!$ok) { fwrite(STDERR, '可选扩展验证失败：'.$message."\n"); exit(1); }
}
$passed = array();
$text = "中文\0二进制🚀";

if (extension_loaded('imagick')) {
    // Imagick：生成、缩放、PNG/JPEG 编解码往返与损坏输入拒绝。
    $image = new Imagick();
    $image->newImage(64, 32, new ImagickPixel('#ff0000'));
    $image->setImageFormat('png');
    $image->resizeImage(32, 16, Imagick::FILTER_LANCZOS, 1);
    $png = $image->getImageBlob();
    optional_check(substr($png, 0, 8) === "\x89PNG\r\n\x1a\n", 'PNG 编码');
    $decoded = new Imagick();
    $decoded->readImageBlob($png);
    optional_check($decoded->getImageWidth() === 32 && $decoded->getImageHeight() === 16, 'PNG 解码尺寸');
    $color = $decoded->getImagePixelColor(5, 5)->getColor();
    optional_check($color['r'] === 255 && $color['g'] === 0 && $color['b'] === 0, 'PNG 像素颜色');
    $decoded->setImageFormat('jpeg');
    optional_check(substr($decoded->getImageBlob(), 0, 2) === "\xff\xd8", 'JPEG 编码');
    optional_check(count(Imagick::queryFormats('PNG')) === 1 && count(Imagick::queryFormats('JPEG')) === 1, '格式模块可用');
    $rejected = false;
    try {
        $bad = new Imagick();
        $bad->readImageBlob("\x89PNG\r\n\x1a\n损坏数据");
    } catch (ImagickException $e) {
        $rejected = true;
    }
    optional_check($rejected, '拒绝损坏 PNG');
    $passed[] = 'Imagick';
}

if (extension_loaded('SourceGuardian')) {
    optional_check(function_exists('sg_load'), 'SourceGuardian 加载函数');
    $passed[] = 'SourceGuardian';
}

if (extension_loaded('mongo')) {
    // 旧版 mongo 驱动：BSON 与 MongoId 离线往返，不连接服务端。
    $document = bson_decode(bson_encode(array('text' => $text, 'n' => 42, 'bin' => new MongoBinData("\x00\xff", MongoBinData::GENERIC))));
    optional_check($document['text'] === $text && $document['n'] === 42 && $document['bin']->bin === "\x00\xff", '旧 mongo BSON 往返');
    $id = new MongoId();
    optional_check(MongoId::isValid((string) $id) && strlen((string) $id) === 24, 'MongoId');
    $passed[] = '旧版 mongo';
}

if (extension_loaded('apcu')) {
    // APCu：CLI 下需 apc.enable_cli=1（由 tests/verify.py 以 -d 传入）。
    optional_check(apcu_store('lookback-key', $text, 60), 'APCu 写入');
    optional_check(apcu_fetch('lookback-key') === $text, 'APCu 读取二进制字符串');
    apcu_store('lookback-counter', 41);
    optional_check(apcu_inc('lookback-counter') === 42, 'APCu 自增');
    optional_check(apcu_delete('lookback-key') && apcu_fetch('lookback-key') === false, 'APCu 删除');
    $passed[] = 'APCu';
}

if (extension_loaded('FFI')) {
    // FFI（PHP 7.4 起）：调用 libc 函数并做内存往返。
    $libc = FFI::cdef('int abs(int value); void *memcpy(void *dest, const void *src, size_t n);');
    optional_check($libc->abs(-42) === 42, 'FFI 调用 libc abs');
    $chinese = '中文';
    // PHP 5.6 不允许 new 作方法名（即使不执行也无法解析），改用 call_user_func 调用 FFI::new。
    $buffer = call_user_func(array('FFI', 'new'), 'char[' . (strlen($chinese) + 1) . ']');
    FFI::memcpy($buffer, $chinese, strlen($chinese));
    optional_check(FFI::string($buffer, strlen($chinese)) === $chinese, 'FFI 内存中文往返');
    $passed[] = 'FFI';
}

if (extension_loaded('hprose')) {
    $value = array('text' => $text, 'n' => 42, 'list' => array(1, 2, 3), 'null' => null);
    optional_check(hprose_unserialize(hprose_serialize($value)) === $value, 'Hprose 序列化往返');
    $passed[] = 'Hprose';
}

echo '可选扩展离线验证通过：', ($passed ? implode('、', $passed) : '无已加载的可选扩展'), PHP_EOL;
