<?php
// 用途：在 FPM worker 中报告官方 Loader 的加载版本，供 tests/verify.py 核对。
echo 'LOADERS ', json_encode(array(
    'ionCube Loader' => phpversion('ionCube Loader'),
    'SourceGuardian' => phpversion('SourceGuardian'),
)), "\n";
