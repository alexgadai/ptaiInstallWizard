# Инсталлятор AI Enterprise и его окружения
# Генерация сертификатов
# версия 0.5 от 13.07.2020

Param (
[switch]$noad
)

$myFQDN = (Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain
$hostname = (Get-WmiObject win32_computersystem).DNSHostName
if ($noad) {
	$current_domain = $env:ComputerName
}
else {
	$current_domain = (Get-WmiObject win32_computersystem).Domain
}
$IP = Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -ne "Disconnected"} | Select -ExpandProperty IPv4Address | Select -ExpandProperty IPAddress
Set-Location -Path $PSScriptRoot

# патчим конфиги
Write-Host 'Запускаю процедуру генерации самоподписанных сертификатов...' -ForegroundColor Yellow
$int_conf  = Get-Content -path "C:\TOOLS\certs\conf\int_ca.conf" -Raw
$int_client  = Get-Content -path "C:\TOOLS\certs\conf\ssl.client.conf" -Raw
$int_server  = Get-Content -path "C:\TOOLS\certs\conf\ssl.server.conf" -Raw
$root_conf = Get-Content -path "C:\TOOLS\certs\conf\root_ca.conf" -Raw
$int_conf = $int_conf -ireplace '(organizationName\s{1,}=\s{1,})(\".*)',"`$1`"$current_domain`""
$int_conf -ireplace '(commonName\s{1,}=\s{1,})(\".*)',"`$1`"$current_domain Intermediate CA`"" | Set-Content -Path 'C:\TOOLS\certs\conf\int_ca.conf'
$int_client = $int_client -ireplace '(organizationName\s{1,}=\s{1,})(\".*)',"`$1`"$current_domain`""
$int_client = $int_client -ireplace '(commonName\s{1,}=\s{1,})(.*)',"`$1$current_domain PTAI agent #01"
$int_client -ireplace '(email\s{1,}=\s{1,}ptai.agent.01@)(.*)',"`$1$current_domain" | Set-Content -Path 'C:\TOOLS\certs\conf\ssl.client.conf'
$int_server = $int_server -ireplace '(organizationName\s{1,}=\s{1,})(\".*)',"`$1`"$current_domain`""
$int_server = $int_server -ireplace '(commonName\s{1,}=\s{1,})(.*)',"`$1$current_domain CI server #01"
if ($noad) {
	$int_server -ireplace '(subjectAltName\s{1,}=\s{1,}DNS:)(.*)',"`$1$current_domain,DNS:localhost,IP:$IP" | Set-Content -Path 'C:\TOOLS\certs\conf\ssl.server.conf'
}
else {
	$int_server -ireplace '(subjectAltName\s{1,}=\s{1,}DNS:)(.*)',"`$1$hostname.$current_domain,DNS:localhost" | Set-Content -Path 'C:\TOOLS\certs\conf\ssl.server.conf'
}
$root_conf = $root_conf -ireplace '(organizationName\s{1,}=\s{1,})(\".*)',"`$1`"$current_domain`""
$root_conf -ireplace '(commonName\s{1,}=\s{1,})(\".*)',"`$1`"$current_domain Root CA`"" | Set-Content -Path 'C:\TOOLS\certs\conf\root_ca.conf'


$ROOT_CA_HOME = "C:\TOOLS\certs\ROOT"
$ROOT_CA_NAME = "RootCA"
$ca_keylen = 4096
$CA_CONF_DIR = "C:\TOOLS\certs\conf"

# зачищаем каталог в случае повторного использования скрипта
Remove-Item -path "$ROOT_CA_HOME\private" -recurse -ErrorAction Ignore
Remove-Item -path "$ROOT_CA_HOME\certs" -recurse -ErrorAction Ignore
Remove-Item -path "$ROOT_CA_HOME\newcerts" -recurse -ErrorAction Ignore
Remove-Item -path "$ROOT_CA_HOME\db" -recurse -ErrorAction Ignore
Remove-Item -path "$ROOT_CA_HOME\*"  -include *.crl -ErrorAction Ignore
New-Item -Path "$ROOT_CA_HOME\private" -ItemType Directory 
New-Item -Path "$ROOT_CA_HOME\certs" -ItemType Directory 
New-Item -Path "$ROOT_CA_HOME\newcerts" -ItemType Directory 
New-Item -Path "$ROOT_CA_HOME\db" -ItemType Directory 

$uuid = '0000'
New-Item "$ROOT_CA_HOME\db\$ROOT_CA_NAME.crt.srl"
Set-Content "$ROOT_CA_HOME\db\$ROOT_CA_NAME.crt.srl" $uuid
$uuid1 = '00'
New-Item "$ROOT_CA_HOME\db\$ROOT_CA_NAME.crl.srl"
Set-Content "$ROOT_CA_HOME\db\$ROOT_CA_NAME.crl.srl" $uuid1
New-Item "$ROOT_CA_HOME\db\$ROOT_CA_NAME.db"
New-Item "$ROOT_CA_HOME\db\$ROOT_CA_NAME.db.attr"

# генерируем корневой сертификат
openssl genrsa -out $ROOT_CA_HOME\private\$ROOT_CA_NAME.pem.key $ca_keylen
openssl req -new -config $CA_CONF_DIR\root_ca.conf -out $ROOT_CA_HOME\$ROOT_CA_NAME.pem.csr -key $ROOT_CA_HOME\private\$ROOT_CA_NAME.pem.key
openssl ca -selfsign -batch -config $CA_CONF_DIR\root_ca.conf -in $ROOT_CA_HOME\$ROOT_CA_NAME.pem.csr -out $ROOT_CA_HOME\certs\$ROOT_CA_NAME.pem.crt -extensions root_ca_ext -notext
openssl x509 -outform DER -in $ROOT_CA_HOME\certs\$ROOT_CA_NAME.pem.crt -out $ROOT_CA_HOME\certs\$ROOT_CA_NAME.der.crt
openssl ca -gencrl -batch -config $CA_CONF_DIR\root_ca.conf -out $ROOT_CA_HOME\$ROOT_CA_NAME.pem.crl
openssl crl -in $ROOT_CA_HOME\$ROOT_CA_NAME.pem.crl -outform DER -out $ROOT_CA_HOME\$ROOT_CA_NAME.der.crl
remove-item   -path "$ROOT_CA_HOME\$ROOT_CA_NAME.pem.csr"

copy $ROOT_CA_HOME\certs\$ROOT_CA_NAME.pem.crt C:\TOOLS\certs\$ROOT_CA_NAME.pem.crt

# INTER
$INT_CA_HOME = "C:\TOOLS\certs\INT"
$INT_CA_NAME = "IntermediateCA"

# зачищаем каталог в случае повторного использования скрипта
Remove-Item -path "$INT_CA_HOME\private" -recurse -ErrorAction Ignore
Remove-Item -path "$INT_CA_HOME\certs" -recurse -ErrorAction Ignore
Remove-Item -path "$INT_CA_HOME\newcerts" -recurse -ErrorAction Ignore
Remove-Item -path "$INT_CA_HOME\db" -recurse -ErrorAction Ignore
Remove-Item -path "$INT_CA_HOME\out" -recurse -ErrorAction Ignore
Remove-Item -path "$INT_CA_HOME\*"  -include *.crl -ErrorAction Ignore
New-Item -Path "$INT_CA_HOME\private" -ItemType Directory 
New-Item -Path "$INT_CA_HOME\certs" -ItemType Directory 
New-Item -Path "$INT_CA_HOME\newcerts" -ItemType Directory 
New-Item -Path "$INT_CA_HOME\db" -ItemType Directory
New-Item -Path "$INT_CA_HOME\out" -ItemType Directory 

$uuid = '0000'
New-Item "$INT_CA_HOME\db\$INT_CA_NAME.crt.srl"
Set-Content "$INT_CA_HOME\db\$INT_CA_NAME.crt.srl" $uuid
$uuid1 = '00'
New-Item "$INT_CA_HOME\db\$INT_CA_NAME.crl.srl"
Set-Content "$INT_CA_HOME\db\$INT_CA_NAME.crl.srl" $uuid1
New-Item "$INT_CA_HOME\db\$INT_CA_NAME.db"
New-Item "$INT_CA_HOME\db\$INT_CA_NAME.db.attr"

# генерируем промежуточный сертификат
openssl genrsa -out $INT_CA_HOME\private\$INT_CA_NAME.pem.key $ca_keylen
openssl req -new -config $CA_CONF_DIR\int_ca.conf -out $INT_CA_HOME\$INT_CA_NAME.pem.csr -key $INT_CA_HOME\private\$INT_CA_NAME.pem.key
openssl ca -batch -config $CA_CONF_DIR\root_ca.conf -in $INT_CA_HOME\$INT_CA_NAME.pem.csr -out $INT_CA_HOME\certs\$INT_CA_NAME.pem.crt -extensions signing_ca_ext -policy extern_pol -notext
openssl x509 -outform DER -in $INT_CA_HOME\certs\$INT_CA_NAME.pem.crt -out $INT_CA_HOME\certs\$INT_CA_NAME.der.crt
openssl ca -gencrl -batch  -config $CA_CONF_DIR\int_ca.conf -out $INT_CA_HOME\$INT_CA_NAME.pem.crl
openssl crl -in $INT_CA_HOME\$INT_CA_NAME.pem.crl -outform DER -out $INT_CA_HOME\$INT_CA_NAME.der.crl
remove-item   -path "$INT_CA_HOME\$INT_CA_NAME.pem.csr"

copy $INT_CA_HOME\certs\$INT_CA_NAME.pem.crt C:\TOOLS\certs\$INT_CA_NAME.pem.crt

# ssl.server
Remove-Item -path "$INT_CA_HOME\temp" -recurse -ErrorAction Ignore
New-Item -Path "$INT_CA_HOME\temp" -ItemType Directory

# генерируем серверный сертификат
openssl req -new -config $CA_CONF_DIR/ssl.server.conf -out $INT_CA_HOME/temp/ssl.server.pem.csr -keyout $INT_CA_HOME/temp/ssl.server.pem.key
openssl ca -batch -config $CA_CONF_DIR/int_ca.conf -in $INT_CA_HOME/temp/ssl.server.pem.csr -out $INT_CA_HOME/temp/ssl.server.pem.crt -policy extern_pol -extensions server_ext -notext
$out = openssl x509 -in $INT_CA_HOME/temp/ssl.server.pem.crt -serial -noout
$path = ([regex]"serial=([\d]{1,})").Matches($out)[0].Groups[1].Value
$OUT_FOLDER_SRV = "C:/TOOLS/certs/INT/out/$path"
$OUT_FOLDER_B = "$INT_CA_HOME\out\$path"
New-Item -Path "$OUT_FOLDER_B" -ItemType Directory
Move-Item -Path "$INT_CA_HOME\temp\*" -Destination "$OUT_FOLDER_B"
openssl x509 -outform DER -in $OUT_FOLDER_SRV/ssl.server.pem.crt -out $OUT_FOLDER_SRV/ssl.server.der.crt

Get-Content $ROOT_CA_HOME\certs\$ROOT_CA_NAME.pem.crt, $INT_CA_HOME\certs\$INT_CA_NAME.pem.crt | out-file $OUT_FOLDER_B\ca.chain.pem.crt

openssl pkcs12 -export -name "SSL server certificate" -inkey $OUT_FOLDER_SRV/ssl.server.pem.key -in $OUT_FOLDER_SRV/ssl.server.pem.crt -CAfile $OUT_FOLDER_SRV/ca.chain.pem.crt -out $OUT_FOLDER_SRV/ssl.server.full.pfx -password pass:"$($passwords['serverCertificate'])"
openssl pkcs12 -export -name "SSL server certificate" -inkey $OUT_FOLDER_SRV/ssl.server.pem.key -in $OUT_FOLDER_SRV/ssl.server.pem.crt -out $OUT_FOLDER_SRV/ssl.server.brief.pfx -password pass:"$($passwords['serverCertificate'])"
openssl pkcs12 -in $OUT_FOLDER_SRV/ssl.server.full.pfx -out $OUT_FOLDER_SRV/ssl.server.full.pem -passin pass:"$($passwords['serverCertificate'])" -passout pass:"$($passwords['serverCertificate'])"
openssl pkcs12 -in $OUT_FOLDER_SRV/ssl.server.brief.pfx -out $OUT_FOLDER_SRV/ssl.server.brief.pem -passin pass:"$($passwords['serverCertificate'])" -passout pass:"$($passwords['serverCertificate'])"

# записываем серверный сертификат в jks
Set-Location -Path $OUT_FOLDER_SRV
keytool -importcert -keystore private.jks -storepass "$($passwords['serverCertificate'])" -alias RootCA -file $ROOT_CA_HOME/certs/$ROOT_CA_NAME.pem.crt -noprompt
keytool -importcert -keystore private.jks -storepass "$($passwords['serverCertificate'])" -alias IntermediateCA -file $INT_CA_HOME/certs/$INT_CA_NAME.pem.crt -noprompt
keytool -importkeystore -srckeystore $OUT_FOLDER_SRV/ssl.server.brief.pfx -srcstoretype pkcs12 -destkeystore private.jks -deststoretype JKS -deststorepass "$($passwords['serverCertificate'])" -srcstorepass "$($passwords['serverCertificate'])"

# копируем сертификаты для подключения к интеграционному сервису
copy $OUT_FOLDER_B\ca.chain.pem.crt C:\TOOLS\certs\server-cert.txt
copy $OUT_FOLDER_B\private.jks C:\TOOLS\certs\server-private.jks

Set-Location -Path "C:/TOOLS/certs/src"

# ssl.client
Remove-Item -path "$INT_CA_HOME\temp" -recurse -ErrorAction Ignore
New-Item -Path "$INT_CA_HOME\temp" -ItemType Directory 

# генерируем клиентский сертификат
openssl req -new -config $CA_CONF_DIR/ssl.client.conf -out $INT_CA_HOME/temp/ssl.client.pem.csr -keyout $INT_CA_HOME/temp/ssl.client.pem.key
openssl ca -batch -config $CA_CONF_DIR/int_ca.conf -in $INT_CA_HOME/temp/ssl.client.pem.csr -out $INT_CA_HOME/temp/ssl.client.pem.crt -policy extern_pol -extensions server_ext -notext
$out = openssl x509 -in $INT_CA_HOME/temp/ssl.client.pem.crt -serial -noout
$path = ([regex]"serial=([\d]{1,})").Matches($out)[0].Groups[1].Value
$OUT_FOLDER_CLT = "C:/TOOLS/certs/INT/out/$path"
$OUT_FOLDER_B = "$INT_CA_HOME\out\$path"
New-Item -Path "$OUT_FOLDER_B" -ItemType Directory
Move-Item -Path "$INT_CA_HOME\temp\*" -Destination "$OUT_FOLDER_B"
openssl x509 -outform DER -in $OUT_FOLDER_CLT/ssl.client.pem.crt -out $OUT_FOLDER_CLT/ssl.client.der.crt

Get-Content $ROOT_CA_HOME\certs\$ROOT_CA_NAME.pem.crt, $INT_CA_HOME\certs\$INT_CA_NAME.pem.crt | out-file $OUT_FOLDER_B\ca.chain.pem.crt

openssl pkcs12 -export -name "SSL client certificate" -inkey $OUT_FOLDER_CLT/ssl.client.pem.key -in $OUT_FOLDER_CLT/ssl.client.pem.crt -CAfile $OUT_FOLDER_CLT/ca.chain.pem.crt -out $OUT_FOLDER_CLT/ssl.client.full.pfx -password pass:"$($passwords['clientCertificate'])"
openssl pkcs12 -export -name "SSL client certificate" -inkey $OUT_FOLDER_CLT/ssl.client.pem.key -in $OUT_FOLDER_CLT/ssl.client.pem.crt -out $OUT_FOLDER_CLT/ssl.client.brief.pfx -password pass:"$($passwords['clientCertificate'])"
openssl pkcs12 -in $OUT_FOLDER_CLT/ssl.client.full.pfx -out $OUT_FOLDER_CLT/ssl.client.full.pem -passin pass:"$($passwords['clientCertificate'])" -passout pass:"$($passwords['clientCertificate'])"
openssl pkcs12 -in $OUT_FOLDER_CLT/ssl.client.brief.pfx -out $OUT_FOLDER_CLT/ssl.client.brief.pem -passin pass:"$($passwords['clientCertificate'])" -passout pass:"$($passwords['clientCertificate'])"

copy $OUT_FOLDER_B\ssl.client.brief.pfx C:\TOOLS\certs\ssl.client.brief.pfx

Set-Location -Path $PSScriptRoot