<?php

$request = <<<XML
<?xml version="1.0" encoding="UTF-8"?>
<soap:Envelope
    xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:apache="http://xml.apache.org/xml-soap">

    <soap:Body>
        <test>
            <map xsi:type="apache:Map">
                <item><key>hello</key></item>
            </map>
        </test>
    </soap:Body>
</soap:Envelope>
XML;

$server = new SoapServer(null, [
    'uri' => 'urn:test',
    'typemap' => [['type_name' => 'anything']],
]);
$server->addFunction('test');
function test($m) { return null; }
$server->handle($request);

?>
