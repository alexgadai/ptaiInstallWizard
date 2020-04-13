# извлекаем мастер токен консула
$AIconfig = Get-Content -Path "C:\Program Files (x86)\Positive Technologies\Application Inspector Server\config.json" | ConvertFrom-Json
$ConsulToken=$AIconfig.Config.ConsulMasterToken

# добавляем политику ServiceRegister
$ServiceRegister = Invoke-WebRequest -Uri "http://localhost:8500/v1/acl/policy?dc=dc1" -Method "PUT" -Headers @{"X-Consul-Token"="$($ConsulToken)"} -ContentType "application/json; charset=UTF-8" -Body "{`"Name`":`"devel-AIE-integrationService-ServiceRegister`",`"Description`":`"`",`"Rules`":`"service_prefix \`"integrationService\`" {\n    policy = \`"write\`" intentions = \`"write\`"\n}`"}" | ConvertFrom-Json

# добавляем политику SettingsRead
$SettingsRead = Invoke-WebRequest -Uri "http://localhost:8500/v1/acl/policy?dc=dc1" -Method "PUT" -Headers @{"X-Consul-Token"="$($ConsulToken)"} -ContentType "application/json; charset=UTF-8" -Body "{`"Name`":`"devel-AIE-integrationService-SettingsRead`",`"Description`":`"`",`"Rules`":`"key_prefix \`"services/integrationService/data\`" {\n\tpolicy = \`"read\`"\n}`"}" | ConvertFrom-Json

# добавляем политику CatalogRead
$CatalogRead = Invoke-WebRequest -Uri "http://localhost:8500/v1/acl/policy?dc=dc1" -Method "PUT" -Headers @{"X-Consul-Token"="$($ConsulToken)"} -ContentType "application/json; charset=UTF-8" -Body "{`"Name`":`"devel-AIE-integrationService-CatalogRead`",`"Description`":`"`",`"Rules`":`"service_prefix \`"\`" {\n    policy = \`"read\`"\n}\nnode_prefix \`"\`" {\n    policy = \`"read\`"\n}`"}" | ConvertFrom-Json

# добавляем токен и присоединяем к нему добавленные политики
$Token = Invoke-WebRequest -Uri "http://localhost:8500/v1/acl/token?dc=dc1" -Method "PUT" -Headers @{"X-Consul-Token"="$($ConsulToken)"} -ContentType "application/json; charset=UTF-8" -Body "{`"AccessorID`":null,`"Type`":null,`"Name`":`"`",`"Rules`":null,`"Description`":`"Token for service: integrationService`",`"Local`":false,`"Policies`":[{`"ID`":`"$($ServiceRegister.ID)`",`"Name`":`"devel-AIE-integrationService-ServiceRegister`"},{`"ID`":`"$($SettingsRead.ID)`",`"Name`":`"devel-AIE-integrationService-SettingsRead`"},{`"ID`":`"$($CatalogRead.ID)`",`"Name`":`"devel-AIE-integrationService-CatalogRead`"}],`"Roles`":[],`"ServiceIdentities`":[]}" | ConvertFrom-Json

# патчим bootstrap.yml
Write-Host 'Прописываю токен в bootstrap.yml...' -ForegroundColor Yellow
$patchBS = Get-Content -Path "C:\TOOLS\BOOT-INF\classes\bootstrap.yml" | Out-String
$patchBS -replace '(token\:)(.*)',"`$1 $($Token.SecretID)" | Set-Content -Path "C:\TOOLS\BOOT-INF\classes\bootstrap.yml"
echo "Success!" > C:\TOOLS\consulpatch.txt