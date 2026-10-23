<?php
$curl = curl_version();
$sqlite = SQLite3::version();
$extensions = array();
$allVersions = array();
foreach (get_loaded_extensions() as $extension) {
    $allVersions[$extension] = phpversion($extension);
}
ksort($allVersions);
foreach (array('memcache','memcached','redis','swoole','xdebug','mongodb','zstd','event','mongo','apcu','imagick','hprose','SourceGuardian','ionCube Loader','Zend OPcache') as $extension) {
    $extensions[$extension] = phpversion($extension);
}
echo json_encode(array(
    'php'=>PHP_VERSION,
    'pcre'=>PCRE_VERSION,
    'timezone_database'=>timezone_version_get(),
    'zts'=>PHP_ZTS,
    'machine'=>php_uname('m'),
    'iconv_implementation'=>ICONV_IMPL,
    'iconv_reported_version'=>ICONV_VERSION,
    'iconv_version_note'=>'旧 PHP 用 0x0f 截取版本号，GNU libiconv 1.18 会显示为 1.2；实际版本另用 iconv --version 验证',
    'openssl'=>OPENSSL_VERSION_TEXT,
    'icu'=>INTL_ICU_VERSION,
    'libxml'=>LIBXML_DOTTED_VERSION,
    'curl'=>$curl['version'],
    'sqlite'=>$sqlite['versionString'],
    'session_upload_progress'=>ini_get('session.upload_progress.enabled'),
    'ca_file'=>ini_get('openssl.cafile'),
    'curl_ca_file'=>ini_get('curl.cainfo'),
    'ca_bundle_sha256'=>hash_file('sha256', ini_get('openssl.cafile')),
    'native_and_loaded_modules'=>get_loaded_extensions(),
    'all_extension_versions'=>$allVersions,
    'gd'=>gd_info(),
    'pdo_drivers'=>PDO::getAvailableDrivers(),
    'dba_handlers'=>dba_handlers(),
    'extensions'=>$extensions
), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)."\n";
