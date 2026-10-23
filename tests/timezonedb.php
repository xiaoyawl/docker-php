<?php
function timezone_check($ok, $message) {
    if (!$ok) { fwrite(STDERR, '时区验证失败：'.$message."\n"); exit(1); }
}
timezone_check(extension_loaded('timezonedb') && timezone_version_get() === '2026.5', '官方数据库实际加载');
timezone_check(in_array('America/Coyhaique', DateTimeZone::listIdentifiers(), true), '新时区标识');
foreach (array('2026-01-15', '2026-07-15') as $date) {
    $value = new DateTime($date.' 12:00:00', new DateTimeZone('America/Coyhaique'));
    timezone_check($value->format('P') === '-03:00', 'Coyhaique 当前全年时差 '.$date);
    $epoch = $value->getTimestamp();
    $value->setTimezone(new DateTimeZone('Asia/Shanghai'));
    timezone_check($value->getTimestamp() === $epoch, '转换时区保持同一时刻');
    $value->setTimezone(new DateTimeZone('UTC'));
    timezone_check($value->format('H:i:s') === '15:00:00', 'UTC 转换');
}
echo "官方时区数据库版本、新时区与时间转换回归通过\n";
