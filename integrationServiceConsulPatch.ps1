# Инсталлятор AI Enterprise и его окружения
# Настройка интеграционного сервиса
# версия 0.5 от 13.07.2020

if ([System.IO.File]::Exists("C:\Program Files (x86)\Positive Technologies\Application Inspector Server\config.json")) {
	if ((Get-Service Consul -ErrorAction SilentlyContinue).Status -eq 'Running') {
		Set-Location -Path $PSScriptRoot
		# извлекаем мастер токен консула
		$AIconfig = Get-Content -Path "C:\Program Files (x86)\Positive Technologies\Application Inspector Server\config.json" | ConvertFrom-Json
		$ConsulToken = $AIconfig.Config.ConsulMasterToken
		
		# добавляем политику ServiceRegister
		$ServiceRegister = Invoke-WebRequest -Uri "http://localhost:8500/v1/acl/policy?dc=dc1" -Method "PUT" -Headers @{"X-Consul-Token"="$($ConsulToken)"} -ContentType "application/json; charset=UTF-8" -Body "{`"Name`":`"devel-AIE-integrationService-ServiceRegister`",`"Description`":`"`",`"Rules`":`"service_prefix \`"integrationService\`" {\n    policy = \`"write\`" intentions = \`"write\`"\n}`"}" | ConvertFrom-Json
		
		# добавляем политику SettingsRead
		$SettingsRead = Invoke-WebRequest -Uri "http://localhost:8500/v1/acl/policy?dc=dc1" -Method "PUT" -Headers @{"X-Consul-Token"="$($ConsulToken)"} -ContentType "application/json; charset=UTF-8" -Body "{`"Name`":`"devel-AIE-integrationService-SettingsRead`",`"Description`":`"`",`"Rules`":`"key_prefix \`"services/integrationService/data\`" {\n\tpolicy = \`"read\`"\n}`"}" | ConvertFrom-Json
		
		# добавляем политику CatalogRead
		$CatalogRead = Invoke-WebRequest -Uri "http://localhost:8500/v1/acl/policy?dc=dc1" -Method "PUT" -Headers @{"X-Consul-Token"="$($ConsulToken)"} -ContentType "application/json; charset=UTF-8" -Body "{`"Name`":`"devel-AIE-integrationService-CatalogRead`",`"Description`":`"`",`"Rules`":`"service_prefix \`"\`" {\n    policy = \`"read\`"\n}\nnode_prefix \`"\`" {\n    policy = \`"read\`"\n}`"}" | ConvertFrom-Json
		
		# добавляем токен и присоединяем к нему добавленные политики
		$Token = Invoke-WebRequest -Uri "http://localhost:8500/v1/acl/token?dc=dc1" -Method "PUT" -Headers @{"X-Consul-Token"="$($ConsulToken)"} -ContentType "application/json; charset=UTF-8" -Body "{`"AccessorID`":null,`"Type`":null,`"Name`":`"`",`"Rules`":null,`"Description`":`"Token for service: integrationService`",`"Local`":false,`"Policies`":[{`"ID`":`"$($ServiceRegister.ID)`",`"Name`":`"devel-AIE-integrationService-ServiceRegister`"},{`"ID`":`"$($SettingsRead.ID)`",`"Name`":`"devel-AIE-integrationService-SettingsRead`"},{`"ID`":`"$($CatalogRead.ID)`",`"Name`":`"devel-AIE-integrationService-CatalogRead`"}],`"Roles`":[],`"ServiceIdentities`":[]}" | ConvertFrom-Json
		
		# патчим bootstrap.yml
		if ($Token.SecretID) {
			Write-Host 'Прописываю токен в bootstrap.yml...' -ForegroundColor Yellow
			((Get-Content config\bootstrap.yml -Raw) -replace '(token\:)(.*)',"`$1 $($Token.SecretID)") | Set-Content -Path "C:\TOOLS\BOOT-INF\classes\bootstrap.yml"
		}
		else {
			Write-Host 'Ошибка: токен не найден. Пожалуйста, устраните ошибку и перезапустите установку с шага 6.' -ForegroundColor Red
			Exit
		}
	}
	else {
		Write-Host 'Ошибка: служба Consul не запущена. Пожалуйста, устраните ошибку и перезапустите установку с шага 6.' -ForegroundColor Red
		Exit
	}
}
else {
	Write-Host 'Ошибка: AI Server не установлен. Пожалуйста, устраните ошибку и перезапустите установку с шага 6.' -ForegroundColor Red
	Exit
}