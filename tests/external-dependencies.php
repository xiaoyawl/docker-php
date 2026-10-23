<?php
// 外部库切换回归：保留中文正则、图像处理和 ZIP 读写能力。
function dependency_check($ok, $message) {
    if (!$ok) { fwrite(STDERR, '外部依赖验证失败：'.$message."\n"); exit(1); }
}
// PHP 7.3 起使用 PCRE2（10.x），此前使用 PCRE1（8.x）；两者均应为系统库版本。
dependency_check(preg_match('/^(8|10)\.\d+ /', PCRE_VERSION) === 1, '系统 PCRE 版本');
dependency_check(preg_match('/^(中文)+$/u', '中文中文') === 1, 'PCRE Unicode 匹配');
dependency_check(preg_replace('/(中文)/u', '[$1]', '中文') === '[中文]', 'PCRE 替换');
mb_regex_encoding('UTF-8');
dependency_check(mb_ereg('^中文[0-9]+$', '中文123') !== false, 'Oniguruma 多字节匹配');
dependency_check(mb_ereg_replace('[0-9]+', '完成', '中文123') === '中文完成', 'Oniguruma 替换');
$gd = gd_info();
dependency_check(GD_BUNDLED === 0 && strpos($gd['GD Version'], '2.3.3') !== false, '系统 libgd 版本');
$image = imagecreatetruecolor(16, 16);
dependency_check(imageantialias($image, true), '外部 GD 抗锯齿接口');
$red = imagecolorallocate($image, 255, 0, 0);
imageline($image, 0, 0, 15, 9, $red);
foreach (array('png', 'jpeg') as $format) {
    ob_start();
    $write = 'image'.$format;
    dependency_check($write($image), 'GD '.$format.' 编码');
    $binary = ob_get_clean();
    $read = imagecreatefromstring($binary);
    dependency_check($read !== false && imagesx($read) === 16 && imagesy($read) === 16, 'GD '.$format.' 解码');
    imagedestroy($read);
}
$crop = imagecrop($image, array('x'=>1, 'y'=>1, 'width'=>8, 'height'=>8));
dependency_check($crop !== false && imagesx($crop) === 8, 'GD 裁剪');
imagedestroy($crop);
$rotated = imagerotate($image, 90, 0);
dependency_check($rotated !== false && imagesx($rotated) === 16, 'GD 旋转');
imagedestroy($rotated);
imagedestroy($image);
$file = tempnam('/tmp', 'external-zip-');
unlink($file);
$zip = new ZipArchive();
dependency_check($zip->open($file, ZipArchive::CREATE) === true, '系统 libzip 创建');
dependency_check($zip->addFromString('中文.txt', "中文\0ZIP"), '系统 libzip 二进制内容');
dependency_check($zip->close(), '系统 libzip 关闭');
dependency_check($zip->open($file) === true && $zip->getFromName('中文.txt') === "中文\0ZIP", '系统 libzip 中文文件名及内容');
$zip->close();
unlink($file);
echo "系统 PCRE、Oniguruma、GD 与 libzip 功能回归通过\n";
