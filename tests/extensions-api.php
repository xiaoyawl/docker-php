<?php
// 用途：只读记录历史 PECL 扩展的公开接口，用于升级前后差异核对。
function extension_signature($function) {
    $parameters = array();
    foreach ($function->getParameters() as $parameter) {
        $parameters[] = array($parameter->getName(), $parameter->isOptional(), $parameter->isPassedByReference());
    }
    return array($function->getNumberOfRequiredParameters(), $function->getNumberOfParameters(), $parameters);
}
$result = array();
foreach (array('memcache', 'memcached', 'redis', 'swoole', 'xdebug') as $name) {
    $extension = new ReflectionExtension($name);
    $data = array('version' => $extension->getVersion(), 'functions' => array(), 'classes' => array());
    foreach ($extension->getFunctions() as $function) {
        $data['functions'][$function->getName()] = extension_signature($function);
    }
    // PHP 类名不区分大小写；保留可调用的旧类名及命名空间别名，避免误报重命名。
    foreach (get_declared_classes() as $alias) {
        $class = new ReflectionClass($alias);
        if (strcasecmp($class->getExtensionName(), $name) !== 0) { continue; }
        $methods = array();
        foreach ($class->getMethods(ReflectionMethod::IS_PUBLIC) as $method) {
            $methods[$method->getName()] = extension_signature($method);
        }
        ksort($methods);
        $constants = $class->getConstants();
        ksort($constants);
        $data['classes'][strtolower($alias)] = array('methods' => $methods, 'constants' => $constants);
    }
    ksort($data['functions']);
    ksort($data['classes']);
    $result[$name] = $data;
}
echo json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)."\n";
