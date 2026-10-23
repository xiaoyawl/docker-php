<?php
// 用途：验证 Xdebug 覆盖率和函数跟踪，不连接远程调试器。Xdebug 3 需以 xdebug.mode=coverage,trace 运行。
function xdebug_compat_add($value) {
    return $value + 1;
}
// Xdebug 版本由 tests/verify.py 按 config/extensions.json 统一核对。
xdebug_start_code_coverage();
$result = xdebug_compat_add(41);
$coverage = xdebug_get_code_coverage();
xdebug_stop_code_coverage();
if ($result !== 42 || empty($coverage[__FILE__])) { fwrite(STDERR, "Xdebug 覆盖率验证失败\n"); exit(1); }
$base = tempnam('/tmp', 'php-xdebug-');
unlink($base);
$trace = xdebug_start_trace($base, XDEBUG_TRACE_COMPUTERIZED);
// Xdebug 3 若按配置在请求开始时已启动跟踪，再次启动返回空值，改取当前跟踪文件。
if (!$trace && function_exists('xdebug_get_tracefile_name')) { $trace = xdebug_get_tracefile_name(); }
xdebug_compat_add(1);
xdebug_stop_trace();
$content = file_get_contents($trace);
// Xdebug 3.1 起默认压缩跟踪文件（xdebug.use_compression=1），按 gzip 头判断后解压。
if (substr($content, 0, 2) === "\x1f\x8b") { $content = gzdecode($content); }
unlink($trace);
if (strpos($content, 'xdebug_compat_add') === false) { fwrite(STDERR, "Xdebug 函数跟踪验证失败\n"); exit(1); }
echo 'Xdebug ', phpversion('xdebug'), " 代码覆盖率和函数跟踪验证通过\n";
