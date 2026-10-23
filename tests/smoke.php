<?php
function check($ok, $message) {
    if (!$ok) { fwrite(STDERR, '验证失败：'.$message."\n"); exit(1); }
}
// 期望的 PHP 版本与原生模块清单由 tests/verify.py 从 config/extensions.json 读取后传入。
check(PHP_VERSION === getenv('PHP_EXPECTED_VERSION'), 'PHP 版本');
check(!ini_get('session.upload_progress.enabled'), 'session 上传进度追踪默认禁用');
$modules = json_decode(getenv('PHP_NATIVE_MODULES'), true);
check(is_array($modules) && count($modules) > 0, '原生模块清单');
foreach ($modules as $name) { check(extension_loaded($name), '扩展 '.$name); }
$text = '中文编码测试';
foreach (array('GBK','GB18030') as $encoding) {
    $encoded = iconv('UTF-8', $encoding, $text);
    check($encoded !== false && iconv($encoding, 'UTF-8', $encoded) === $text, 'iconv '.$encoding);
}
check(iconv('UTF-8', 'UTF-8//IGNORE', "A\xffB") === 'AB', 'iconv IGNORE');
check(Normalizer::normalize("e\xcc\x81") === "\xc3\xa9", 'ICU 规范化');
$db = new PDO('sqlite::memory:');
check($db->query('SELECT 123')->fetchColumn() == 123, 'SQLite 查询');
$xml = simplexml_load_string('<root><item>中文</item></root>');
check((string)$xml->item === '中文', 'XML 解析');
libxml_use_internal_errors(true);
simplexml_load_string('<root>');
check(count(libxml_get_errors()) > 0, 'libxml 错误回调');
libxml_clear_errors();
libxml_use_internal_errors(false);
$dom = new DOMDocument();
check($dom->loadXML('<!DOCTYPE root [<!ENTITY sample "text">]><root/>'), 'DOM 文档');
$entityCount = 0;
foreach ($dom->doctype->entities as $entity) { $entityCount++; }
check($entityCount === 1, 'DOM 实体迭代');
check(mb_convert_encoding('abc', 'ISO-2022-JP-MOBILE#KDDI', 'UTF-8') === 'abc', 'mbstring KDDI 别名');
ini_set('session.serialize_handler', 'php_serialize');
ini_set('session.save_path', '/tmp');
session_id('phpregression');
session_start();
$_SESSION = array('value'=>$text);
$serialized = session_encode();
$_SESSION = array();
check(session_decode($serialized) && $_SESSION['value'] === $text, 'session php_serialize');
session_destroy();
$im = imagecreatetruecolor(4, 4);
check(imagepng($im, '/tmp/php-test.png'), 'GD PNG');
imagedestroy($im);
$zip = new ZipArchive();
check($zip->open('/tmp/php-test.zip', ZipArchive::CREATE) === true, 'ZIP 创建');
$zip->addFromString('test.txt', $text);
$zip->close();
check($zip->open('/tmp/php-test.zip') === true && $zip->getFromName('test.txt') === $text, 'ZIP 读取');
$zip->close();
$key = str_repeat('k', 32); $iv = str_repeat('i', 16);
$cipher = openssl_encrypt($text, 'aes-256-cbc', $key, OPENSSL_RAW_DATA, $iv);
check($cipher !== false && openssl_decrypt($cipher, 'aes-256-cbc', $key, OPENSSL_RAW_DATA, $iv) === $text, 'OpenSSL AES');
$wrapKey = str_repeat('k', 16); $wrapIv = str_repeat("\0", 4);
if (@openssl_encrypt('test', 'aes-128-wrap-pad', $wrapKey, OPENSSL_RAW_DATA, $wrapIv) !== false) {
    for ($i = 1; $i < 258; $i++) {
        $data = str_repeat('a', $i);
        $enc = openssl_encrypt($data, 'aes-128-wrap-pad', $wrapKey, OPENSSL_RAW_DATA, $wrapIv);
        check($enc !== false && openssl_decrypt($enc, 'aes-128-wrap-pad', $wrapKey, OPENSSL_RAW_DATA, $wrapIv) === $data, 'AES-WRAP-PAD 长度 '.$i);
    }
    echo "AES-WRAP-PAD 长度 1..257 回归通过\n";
} else {
    echo "未覆盖：当前 OpenSSL/PHP 路径未提供可用 AES-WRAP-PAD\n";
}
echo "PHP 版本、内置扩展、编码、ICU、SQLite、XML、GD、ZIP、OpenSSL 验证通过\n";
