<?php
header('Content-Type: application/json');
if (isset($_GET['oom'])) {
    ini_set('memory_limit', '16M');
    $payload = str_repeat('X', 64 * 1024 * 1024);
}
if (isset($_GET['fatal'])) {
    trigger_error('请求生命周期回归测试', E_USER_ERROR);
}
echo json_encode(array('pid'=>getmypid(), 'version'=>PHP_VERSION, 'post'=>$_POST,
    'memory_limit'=>ini_get('memory_limit'), 'timezone'=>date_default_timezone_get(),
    'files'=>count($_FILES)));
