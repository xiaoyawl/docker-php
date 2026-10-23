<?php
// LookBack：PHP 7.1 安全回补与新增原生模块的离线回归。
function check_security($condition, $message) {
    if (!$condition) {
        fwrite(STDERR, "安全回归失败：" . $message . "\n");
        exit(1);
    }
}

check_security(@password_hash("\0audit", PASSWORD_BCRYPT) === null, '拒绝含 NUL 的 bcrypt 密码');
foreach (array('https://example.com:\\@test.com/', 'https://user:\\epass@test.com') as $url) {
    check_security(filter_var($url, FILTER_VALIDATE_URL) === false, '拒绝畸形 URL userinfo');
}
check_security(filter_var("\xff\xfeabc", FILTER_SANITIZE_ENCODED) === '%FF%FEabc', '编码完整的 256 字节查找表');
foreach (array('convert.base64-encode', 'convert.quoted-printable-encode') as $name) {
    $fp = fopen('php://temp', 'w+');
    $filter = stream_filter_append($fp, $name, STREAM_FILTER_WRITE, array('line-length' => 4, 'line-break-chars' => "\0X"));
    fwrite($fp, str_repeat('a', 24));
    stream_filter_remove($filter);
    rewind($fp);
    $value = stream_get_contents($fp);
    check_security(strpos($value, "\0X") !== false, '流过滤器保留含 NUL 的分隔符：' . $name);
    fclose($fp);
}
$parser = xml_parser_create();
xml_parser_set_option($parser, XML_OPTION_SKIP_TAGSTART, 100);
$values = $index = array();
xml_parse_into_struct($parser, '<test><child/></test>', $values, $index);
foreach ($values as $value) check_security($value['tag'] === '', 'XML tag offset 边界');
xml_parser_free($parser);
$dns = @dns_get_record("example.com\0invalid");
check_security($dns === false || $dns === null, 'DNS 主机名拒绝 NUL');
check_security(bzdecompress(bzcompress('中文回归')) === '中文回归', 'bzip2 往返');
check_security(gmp_strval(gmp_mul('123456789', '9')) === '1111111101', 'GMP 大数运算');
check_security(cal_days_in_month(CAL_GREGORIAN, 2, 2024) === 29, 'calendar 闰年');
check_security(is_string(wddx_serialize_value(array('中文' => 42))), 'WDDX 原生编码');
$db = dba_open('/tmp/php-security.db', 'n', 'gdbm');
check_security($db !== false && dba_insert('key', '中文', $db) && dba_fetch('key', $db) === '中文', 'DBA gdbm 读写');
dba_close($db);
unlink('/tmp/php-security.db');
$finfo = new finfo(FILEINFO_MIME_TYPE);
check_security($finfo->buffer('plain text') === 'text/plain', 'fileinfo 文本识别');
check_security(strpos(tidy_repair_string('<p>中文', array(), 'utf8'), '中文') !== false, 'tidy-html5 解析');
check_security(ldap_escape('a*(b)', '', LDAP_ESCAPE_FILTER) === 'a\2a\28b\29', 'LDAP filter 转义');
$key = openssl_pkey_new(array('private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA));
check_security($key !== false && openssl_pkey_export($key, $pem), '生成临时 OpenSSL 密钥');
$keyFile = tempnam('/tmp', 'php-openssl-');
file_put_contents($keyFile, $pem);
check_security(@openssl_pkey_export_to_file('file://'.$keyFile, '/tmp') === false, 'OpenSSL 输出打开失败时受控返回，不崩溃');
unlink($keyFile);
openssl_pkey_free($key);
foreach (array('pgsql', 'pdo_pgsql', 'odbc', 'pdo_odbc', 'pdo_dblib', 'snmp', 'enchant', 'pspell', 'readline', 'sysvmsg', 'sysvshm') as $extension) {
    check_security(extension_loaded($extension), '新增原生扩展加载：' . $extension);
}
echo "安全边界与新增原生模块回归通过\n";
