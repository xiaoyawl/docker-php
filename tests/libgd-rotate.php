<?php
// libgd 旋转回归：调色板与真彩色图像在多角度、全部插值方式下旋转，原图在旋转后仍可安全使用和销毁。
function rotate_check($ok, $message) {
    if (!$ok) { fwrite(STDERR, 'libgd 旋转回归失败：'.$message."\n"); exit(1); }
}
$methods = array(IMG_BELL, IMG_BESSEL, IMG_BICUBIC, IMG_BICUBIC_FIXED, IMG_BILINEAR_FIXED, IMG_BLACKMAN,
    IMG_BOX, IMG_BSPLINE, IMG_CATMULLROM, IMG_GAUSSIAN, IMG_GENERALIZED_CUBIC, IMG_HERMITE, IMG_HAMMING,
    IMG_HANNING, IMG_MITCHELL, IMG_POWER, IMG_QUADRATIC, IMG_SINC, IMG_NEAREST_NEIGHBOUR, IMG_WEIGHTED4, IMG_TRIANGLE);
$count = 0;
foreach (array('palette', 'truecolor') as $kind) {
    foreach (array(0, 90, 180, 270, -5) as $angle) {
        foreach ($methods as $method) {
            $img = $kind === 'palette' ? imagecreate(40, 20) : imagecreatetruecolor(40, 20);
            imagecolorallocate($img, 255, 255, 255);
            imagesetinterpolation($img, $method);
            $bg = imagecolorallocatealpha($img, 0, 0, 0, 127);
            $rotated = imagerotate($img, $angle, $bg);
            rotate_check($rotated !== false, "$kind {$angle}° 方法 $method 返回失败");
            $expected = ($angle === 90 || $angle === 270) ? array(20, 40) : array(40, 20);
            if ($angle !== -5) {
                rotate_check(array(imagesx($rotated), imagesy($rotated)) === $expected, "$kind {$angle}° 尺寸");
            }
            imagesetpixel($img, 1, 1, $bg);
            rotate_check(imagesx($img) === 40 && imagesy($img) === 20, "$kind {$angle}° 原图仍可使用");
            imagedestroy($rotated);
            imagedestroy($img);
            $count++;
        }
    }
}
echo "libgd 旋转回归通过：$count 组（调色板/真彩色 × 5 个角度 × 21 种插值）", PHP_EOL;
