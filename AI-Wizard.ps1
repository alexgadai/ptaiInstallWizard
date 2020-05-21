#Requires -RunAsAdministrator

# Инсталлятор AI Enterprise и его окружения
# версия 0.4 от 21.05.2020

# Если сценарии Powershell не запускаются в вашей системе из-за ограничений доменной политики, перед запуском данного скрипта выполните команды:
# dir AI-Wizard.ps1 | Unblock-File
# Set-ExecutionPolicy RemoteSigned -Scope Process

Param (
[string]$step,
[switch]$genpass,
[switch]$noad,
[switch]$skipagent
)

# проверяем, заполнен ли AIHOME
function Get-AIHome {
	if ($global:AIHOME -eq $null) {
		Write-Host 'Пожалуйста, укажите путь до каталога с дистрибутивами AI Enterprise (где находятся каталоги aiv, aie, aic) без \ в конце: ' -ForegroundColor Yellow -NoNewline
		$global:AIHOME = Read-Host | ForEach-Object {$_.Trim()}
		# проверяем есть ли в указанном каталоге дистрибутив AI
		Get-Current-Version-Path "$($global:AIHOME)\aiv" "AIE.Viewer*.exe">$null
		Get-Current-Version-Path "$($global:AIHOME)\aie" "AIE.Server*.exe">$null
		Get-Current-Version-Path "$($global:AIHOME)\aic" "AIE.Agent*.exe">$null
	}
}

# проверяем что на машине есть поддерживаемый браузер
function Get-Browser-Path {
	if ([System.IO.File]::Exists("C:\Program Files (x86)\Google\Chrome\Application\chrome.exe")) {
		$global:browserPath = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"		
	}
	elseif ([System.IO.File]::Exists("C:\Program Files\Mozilla Firefox\firefox.exe")) {
		$global:browserPath = "C:\Program Files\Mozilla Firefox\firefox.exe"
	}
}

# выясняем название текущей версии дистрибутива из каталога
function Get-Current-Version-Path([String]$path, [String]$mask) {
	$filename = $path+'\'+(Get-ChildItem "$($path)\$($mask)").Name
	if (-Not [System.IO.File]::Exists($filename)) {
		Write-Host "Ошибка: файл $($mask) не найден в каталоге $($path)." -ForegroundColor Red
		Exit
	}
	return $filename
}

# проверяем версию NetFramework
function Check-NetFramework-Version {
	$nfver = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -recurse | Get-ItemProperty -name Version,Release -EA 0 | Where { $_.PSChildName -match '^(?!S)\p{L}'} | Select Release
	for ($i=0; $i -lt $nfver.Length; $i++) {
		# 4.7.2 или выше
		if ($nfver[$i].Release -ge 461808) {
			[bool] $passed = 1
		}
	}
	if ($passed -eq $null) {
		Write-Host 'Ошибка: пожалуйста, обновите версию Net Framework до 4.7.2 или выше, а затем перезапустите скрипт.' -ForegroundColor Red
		Write-Host 'Запускаю установщик обновления Net Framework...' -ForegroundColor Yellow
		start ndp48-x86-x64-allos-enu.exe
		Exit
	}
	return $passed
}

# инициализация
Set-Location -Path $PSScriptRoot
if (-Not (Test-Path logs)) {mkdir logs >$null}
date | Out-File -Append logs\install.log
if ($noad){
	$myFQDN = $env:ComputerName
} 
else {
	$myFQDN = ((Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain).ToLower()
}
$domain = ((Get-WmiObject win32_computersystem).Domain).ToLower()

# импортируем пароли из файла
if ([System.IO.File]::Exists("C:\TOOLS\passwords.xml")) {
	$passwords = Import-Clixml -Path "C:\TOOLS\passwords.xml"
}
else {
	if ($step -gt 1) {
		Write-Host "Ошибка: первый запуск скрипта должен быть выполнен с первого шага." -ForegroundColor Red
	}
	$step = 1
}


# проверяем что пререквизиты установки выполнены
if ($step -eq 1 -or $step -eq '') {
	Write-Host 'Данный скрипт поможет вам установить Application Inspector Enterprise Edition. Доступные параметры запуска:' -ForegroundColor Yellow
	Write-Host '-step <номер>: запуск скрипта с указанного шага' -ForegroundColor Yellow
	Write-Host '-genpass: генерация сложных паролей' -ForegroundColor Yellow
	Write-Host '-noad: локальная установка без Active Directory' -ForegroundColor Yellow
	Write-Host '-skipagent: пропустить этап установки агента AI, если его планируется ставить на отдельном сервере' -ForegroundColor Yellow
	Write-Host 'Пример запуска с параметрами:' -ForegroundColor Yellow
	Write-Host '.\AI-Wizard.ps1 -genpass' -ForegroundColor Yellow
	Write-Host '.\AI-Wizard.ps1 -step 5' -ForegroundColor Yellow
	Write-Host
	# показываем с какими параметрами запуск чтобы предотвратить опечатки
	if ($genpass -or $noad -or $skipagent -or ($step -gt 0)) {
		Write-Host "Запускаю инсталлятор с параметрами " -ForegroundColor Yellow -NoNewline
		if ($step -gt 1) {Write-Host "-step $($step) " -ForegroundColor Yellow -NoNewline}
		if ($genpass) {Write-Host "-genpass " -ForegroundColor Yellow -NoNewline}
		if ($noad) {Write-Host "-noad " -ForegroundColor Yellow -NoNewline}
		if ($skipagent) {Write-Host "-skipagent" -ForegroundColor Yellow}
	}
	else {
		Write-Host "Запускаю инсталлятор без параметров..." -ForegroundColor Yellow
	}
	Write-Host	
	Write-Host '---ШАГ 1---' -ForegroundColor Green
	Write-Host 'Проверяю пререквизиты установки...' -ForegroundColor Yellow
	if (-Not $noad) {
		# проверяем что машина в домене
		if (-Not (Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain) {
			Write-Host 'Ошибка: пожалуйста, введите компьютер в домен.' -ForegroundColor Red
			Exit
		}
		# проверяем что пользователь доменный
		if ($env:ComputerName -eq $env:UserDomain) {
			Write-Host 'Ошибка: пожалуйста, войдите под доменной учётной записью с правами локального администратора.' -ForegroundColor Red
			Exit
		}
	}
	# проверяем переменную %HOMEDRIVE%
	if ($env:HOMEDRIVE -ne "C:") {
		Write-Host "Предупреждение: глобальная переменная %HOMEDRIVE% установлена не на диск C:, текущее значение $($env:HOMEDRIVE)" -ForegroundColor Cyan
	}
	# проверяем версию powershell
	$psver = Get-Host | Select-Object Version
	$psver.version | Out-File -Append logs\install.log
	if ($psver.version.Major -ge 5) {
		# проверяем версию NetFramework
		if (Check-NetFramework-Version) {
			Write-Host 'Проверки пройдены успешно.' -ForegroundColor Yellow
			Get-AIHome
			if (-Not (Test-Path C:\TOOLS)) {
				Write-Host 'Создаю каталог C:\TOOLS и копирую туда необходимые компоненты для установки...' -ForegroundColor Yellow
				# разблокируем исполняемые файлы и скрипты
				Get-ChildItem -Recurse *.exe | Unblock-File
				Get-ChildItem -Recurse *.msi | Unblock-File
				Get-ChildItem -Recurse *.ps1 | Unblock-File
				Get-ChildItem -Recurse *.bat | Unblock-File
				# копируем утилиты для установки
				mkdir -p C:\TOOLS\BOOT-INF\classes\liquibase | Out-File -Append logs\install.log
				mkdir -p C:\TOOLS\certs\INT | Out-File -Append logs\install.log
				mkdir -p C:\TOOLS\certs\ROOT | Out-File -Append logs\install.log
				mkdir -p C:\TOOLS\certs\conf | Out-File -Append logs\install.log
				mkdir -p C:\TOOLS\certs\src | Out-File -Append logs\install.log
				# проверяем java и openssl
				if ($env:Path -match 'jdk|java') {
					Write-Host 'Предупреждение: в Path обнаружена Java.' -ForegroundColor Cyan
				}
				xcopy jdk1.8 C:\TOOLS\jdk1.8\ /E /Y | Out-File -Append logs\install.log
				if ($env:Path -match 'openssl') {
					Write-Host 'Предупреждение: в Path обнаружен Openssl.' -ForegroundColor Cyan
					# обновляем Path и не копируем openssl на машину
					[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\TOOLS\jdk1.8\bin", "Machine")
				}
				else {
					xcopy openssl C:\TOOLS\openssl\ /E /Y | Out-File -Append logs\install.log
					[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\TOOLS\openssl\bin;C:\TOOLS\jdk1.8\bin", "Machine")
				}
				# обновляем знания текущей сессии Powershell о Path
				$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
				copy config\root_ca.conf C:\TOOLS\certs\conf\root_ca.conf
				copy config\int_ca.conf C:\TOOLS\certs\conf\int_ca.conf
				copy config\ssl.server.conf C:\TOOLS\certs\conf\ssl.server.conf
				copy config\ssl.client.conf C:\TOOLS\certs\conf\ssl.client.conf
				copy ptai-integration-service-0.1-spring-boot.jar C:\TOOLS\ptai-integration-service-0.1-spring-boot.jar
				copy ptai-cli-plugin-0.1-jar-with-dependencies.jar C:\TOOLS\ptai-cli-plugin.jar
				copy agent.jar C:\TOOLS\agent.jar
				copy plugins\ptai-jenkins-plugin.hpi C:\TOOLS\ptai-jenkins-plugin.hpi
				copy config\run-service.bat C:\TOOLS\run-service.bat
				copy generateCertificates.ps1 C:\TOOLS\certs\src\generateCertificates.ps1
				# выключаем окно первого запуска IE чтобы работал Invoke-WebRequest
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main" -Name "DisableFirstRunCustomize" -Value 2
			}
			# создаём пароли для установки
			if (-Not [System.IO.File]::Exists("C:\TOOLS\passwords.xml")) {
				# генерируем безопасные пароли
				if ($genpass) {
					Write-Host 'Генерирую безопасные пароли...' -ForegroundColor Yellow
					Add-Type -AssemblyName System.Web
					$length = 12
					$nonAlphaChars = 2
					$passwords = @{
						# временный костыль: убираем неугодные символы
						'serverCertificate'=[System.Web.Security.Membership]::GeneratePassword($length, $nonAlphaChars) -replace '\^|\||&|<|>|-',"!";
						'clientCertificate'=[System.Web.Security.Membership]::GeneratePassword($length, $nonAlphaChars) -replace '\^|\||&|<|>|-',"!";
						'javaCacerts'=[System.Web.Security.Membership]::GeneratePassword($length, $nonAlphaChars);
						'adminJenkins'=[System.Web.Security.Membership]::GeneratePassword($length, $nonAlphaChars);
						'svc_ptaiJenkins'=[System.Web.Security.Membership]::GeneratePassword($length, $nonAlphaChars);
						'integrationServiceDB'=[System.Web.Security.Membership]::GeneratePassword($length, $nonAlphaChars);
					}
				}
				# или берём простые
				else {
					$passwords = @{
						'serverCertificate'='P@ssw0rd';
						'clientCertificate'='P@ssw0rd';
						'javaCacerts'='changeit';
						'adminJenkins'='P@ssw0rd';
						'svc_ptaiJenkins'='P@ssw0rd';
						'integrationServiceDB'='P@ssw0rd';
					}
				}
				Export-Clixml -Path "C:\TOOLS\passwords.xml" -InputObject $passwords
				$passwords | ConvertTo-JSON | Set-Content -Path "C:\TOOLS\passwords.txt"
			}
		}
		$step = 2		
	}
	else {
		Write-Host 'Ошибка: пожалуйста, обновите версию Powershell до 5-ой или выше, а затем перезапустите скрипт.' -ForegroundColor Red
		Write-Host 'Запускаю установщик обновления Powershell...' -ForegroundColor Yellow
		start powershell_5-1_Win8.1AndW2K12R2-KB3191564-x64.msu
		Check-NetFramework-Version
		Exit
	}
}

# устанавливаем AI Viewer
if ($step -eq 2) {
	Write-Host '---ШАГ 2---' -ForegroundColor Green
	# проверяем если AI Viewer уже установлен
	if ([System.IO.File]::Exists("C:\Program Files (x86)\Positive Technologies\Application Inspector Viewer\ApplicationInspector.exe")) {
		Write-Host 'Этот шаг уже был выполнен, переходим к следующему.' -ForegroundColor Yellow
	}
	else {
		Get-AIHome
		Write-Host 'Пожалуйста, следуйте указаниям установщика AI Viewer...' -ForegroundColor Yellow
		Write-Host 'По завершению установки откажитесь от перезагрузки компьютера, это не обязательно.' -ForegroundColor Yellow
		$proc = Start-Process (Get-Current-Version-Path "$($global:AIHOME)\aiv" "AIE.Viewer*.exe") -passthru
		Wait-Process $proc.Id
		# проверяем что AI Viewer установлен
		if (-Not [System.IO.File]::Exists("C:\Program Files (x86)\Positive Technologies\Application Inspector Viewer\ApplicationInspector.exe")) {
			Write-Host 'Ошибка: AI Viewer не установлен. Пожалуйста, устраните ошибку и продолжите установку с шага 3.' -ForegroundColor Red
			Exit
		}
	}
	$step = 3
}

# генерим самоподписанные сертификаты, устанавливаем сертификаты в хранилище
if ($step -eq 3) {
	Write-Host '---ШАГ 3---' -ForegroundColor Green
	# проверяем что этот шаг не выполнялся
	if ([System.IO.File]::Exists("C:\TOOLS\certs\server-private.jks")) {
		Write-Host 'Этот шаг уже был выполнен, переходим к следующему.' -ForegroundColor Yellow
	}
	else {
		# проверяем что на машине есть нормальный блокнот
		if (-Not [System.IO.File]::Exists("C:\Program Files (x86)\Notepad++\notepad++.exe")) {
			# если нет, то ставим Notepad++ в фоновом режиме
			Write-Host 'Устанавливаю Notepad++...' -ForegroundColor Yellow
			$proc = Start-Process (Get-Current-Version-Path $PSScriptRoot "npp*.exe") -ArgumentList "/S" -passthru
			Wait-Process $proc.Id
			if (-Not [System.IO.File]::Exists("C:\Program Files (x86)\Notepad++\notepad++.exe")) {
				Write-Host 'Ошибка: Notepad++ не установлен. Пожалуйста, установите его вручную.' -ForegroundColor Red
			}
		}
		
		if ($noad) {
			Invoke-expression -Command "C:\TOOLS\certs\src\generateCertificates.ps1 -noad" -ErrorAction Stop 2>&1 | Out-File -Append logs\install.log
		}
		else {
			Invoke-expression -Command C:\TOOLS\certs\src\generateCertificates.ps1 -ErrorAction Stop 2>&1 | Out-File -Append logs\install.log
		}
		Set-Location -Path $PSScriptRoot
		# проверяем что сертификаты сгенерировались
		if ([System.IO.File]::Exists("C:\TOOLS\certs\server-private.jks")) {
			Write-Host 'Сертификаты были сгенерированы успешно и сохранены в C:\TOOLS\certs\INT\out.' -ForegroundColor Yellow
			# меняем пароль на java cacerts если запуск был с параметром genpass
			if ($passwords['javaCacerts'] -ne 'changeit') {
				Write-Host 'Меняю пароль на хранилище сертификатов Java...' -ForegroundColor Yellow
				keytool -storepasswd -new "$($passwords['javaCacerts'])" -storepass changeit -keystore "C:\TOOLS\jdk1.8\jre\lib\security\cacerts" 2>&1 | Out-File -Append logs\install.log
			}
			# добавляем сертификаты в cacerts java
			Write-Host 'Добавляю сертификаты в хранилище сертификатов Java...' -ForegroundColor Yellow
			keytool -importkeystore -noprompt -srckeystore "C:/TOOLS/certs/server-private.jks" -srcstorepass "$($passwords['serverCertificate'])" -destkeystore "C:\TOOLS\jdk1.8\jre\lib\security\cacerts" -deststoretype JKS -deststorepass "$($passwords['javaCacerts'])" 2>&1 | Out-File -Append logs\install.log
			keytool -importkeystore -noprompt -srckeystore "C:/TOOLS/certs/ssl.client.brief.pfx" -srcstorepass "$($passwords['clientCertificate'])" -srcstoretype pkcs12 -destkeystore "C:\TOOLS\jdk1.8\jre\lib\security\cacerts" -deststoretype JKS -deststorepass "$($passwords['javaCacerts'])" 2>&1 | Out-File -Append logs\install.log
			Write-Host 'Импортирую сертификаты в хранилище Windows...' -ForegroundColor Yellow
			Import-Certificate -FilePath "C:\TOOLS\certs\ROOT\certs\RootCA.pem.crt" -CertStoreLocation Cert:\LocalMachine\Root | Out-File -Append logs\install.log
			Import-Certificate -FilePath "C:\TOOLS\certs\INT\certs\IntermediateCA.pem.crt" -CertStoreLocation Cert:\LocalMachine\CA | Out-File -Append logs\install.log
		}
		else {
			Write-Host 'Ошибка: сертификаты не созданы. Логи скопированы в папку logs. Пожалуйста, устраните ошибку и перезапустите установку с шага 3.' -ForegroundColor Red
			Exit
		}
	}
	$step = 4
}

# устанавливаем AI Server
if ($step -eq 4) {
	Write-Host '---ШАГ 4---' -ForegroundColor Green
	# проверяем если AI Server уже установлен
	if (-Not [System.IO.File]::Exists("C:\Program Files (x86)\Positive Technologies\Application Inspector Server\Services\gateway\AIE.Gateway.exe")) {
		Get-AIHome
		if (-Not $noad) {
			# проверяем наличие пользователя в домене
			Write-Host "Проверяю связь с домен контроллером..." -ForegroundColor Yellow
			do {
				if ($matches -ne $null) {
					$domain = $matches[0]
				}
				if ((.\ADTool.exe $domain $env:UserName) -like "Success, all users were found") {
					[bool] $domainfound = 1
					break
				}
			}
			# если не нашли в текущем домене, сокращаем название домена до следующей точки и пробуем снова
			while ($domain -match '(?<=\.).*')
		}
		
		Write-Host 'Пожалуйста, следуйте указаниям установщика AI Server.' -ForegroundColor Yellow
		Write-Host 'Данные для установки: ' -ForegroundColor Yellow
		# если домен, требуемый для инсталлятора, отличается от текущего, укажем на это пользователю
		if ($domainfound -and $domain -ne ((Get-WmiObject win32_computersystem).Domain).ToLower()) {
			Write-Host "Предупреждение: при установке укажите, пожалуйста, домен в таком виде: $($domain)" -ForegroundColor Cyan
		}
		elseif ($noad) {
			Write-Host "Домен: $($env:ComputerName)" -ForegroundColor Yellow
		}
		else {
			Write-Host "Домен: "((Get-WmiObject win32_computersystem).Domain).ToLower() -ForegroundColor Yellow
		}
		Write-Host 'Расположение сертификата: C:\TOOLS\certs\INT\out\00\ssl.server.brief.pfx' -ForegroundColor Yellow
		Write-Host "Пароль от сертификата: $($passwords['serverCertificate'])" -ForegroundColor Yellow
		if ($domainfound) {
			$proc = Start-Process (Get-Current-Version-Path "$($global:AIHOME)\aie" "AIE.Server*.exe") -passthru
		}
		# производим установку с флагом /noad если не смогли найти домен
		else {
			Write-Host "Предупреждение: домен не найден, провожу установку с флагом /noad. После установки вам будет предложено добавить пользователя в базу данных." -ForegroundColor Cyan
			$proc = Start-Process (Get-Current-Version-Path "$($global:AIHOME)\aie" "AIE.Server*.exe") -ArgumentList "/noad" -passthru
		}
		Wait-Process $proc.Id
		# проверяем что AI Server установлен
		if (-Not [System.IO.File]::Exists("C:\Program Files (x86)\Positive Technologies\Application Inspector Server\Services\gateway\AIE.Gateway.exe")) {
			Write-Host 'Ошибка: AI Server не установлен. Логи скопированы в папку logs. Пожалуйста, устраните ошибку и продолжите установку с шага 5.' -ForegroundColor Red
			xcopy "C:\ProgramData\Application Inspector\Logs\deploy" logs\deploy\ /E /Y | Out-File -Append logs\install.log
			Exit
		}
		# если домен не обнаружен, добавляем текущего пользователя в качестве админа через базу данных
		if (-Not $domainfound) {
			Write-Host 'Устанавливаю ODBC драйвер для Postgres...' -ForegroundColor Yellow
			$proc = Start-Process msiexec -ArgumentList "/i $(Get-Current-Version-Path $PSScriptRoot "psqlodbc*.msi") /quiet /l*v `"$($PSScriptRoot)\logs\psqlodbc.log`"" -passthru
			Wait-Process $proc.Id
			Write-Host "Для добавления текущего пользователя в базу данных, пожалуйста, укажите пароль от Postgres, который вы задали при установке: " -ForegroundColor Yellow -NoNewLine
			$DBPass = Read-Host
			$DBConn = New-Object System.Data.Odbc.OdbcConnection
			$DBConn.ConnectionString = "Driver={PostgreSQL UNICODE(x64)};Server=$myFQDN;Port=5432;Database=ai_csi;Uid=postgres;Pwd=$DBPass;"
			$DBConn.Open()
			$DBCmdup = $DBConn.CreateCommand()
			$cmd = (whoami /user)
			$sid = ([regex]"S[\d\-]{1,}").Matches($cmd)[0].Value
			$DBCmdup.CommandText = "INSERT INTO `"GlobalMemberEntity`" (`"Sid`", `"RoleId`") VALUES ('$sid', '1')"
			$DBCmdup.ExecuteReader()
			$DBConn.Close()
			# рестарт службы аутентификации
			net stop AI.Enterprise.AuthService | Out-File -Append logs\install.log
			net start AI.Enterprise.AuthService | Out-File -Append logs\install.log
		}
	}
	# проверяем наличие служб
	try {
		$AIServiceStatus = Get-Service AI.*,Consul,RabbitMQ,PostgreSQL -ErrorAction Stop
	}
	catch {
		Write-Host 'Ошибка проверки служб: '$_ -ForegroundColor Red
		Write-Host 'Логи скопированы в папку logs. Пожалуйста, устраните ошибку и продолжите установку с шага 5.' -ForegroundColor Red
		xcopy "C:\ProgramData\Application Inspector\Logs\deploy" logs\deploy\ /E /Y | Out-File -Append logs\install.log	
		Exit
	}
	# проверяем статус служб
	$ServiceDownList = New-Object System.Collections.Generic.List[System.Object]
	for ($i=0; $i -lt $AIServiceStatus.Length; $i++) {
		if ($AIServiceStatus[$i].Status -ne 'Running') {
			$ServiceDownList.Add($AIServiceStatus[$i].DisplayName)
		}
	}
	# если есть не запустившиеся службы, копируем логи их падения в папку logs
	if ($ServiceDownList.Count -gt 0) {
		Write-Host 'Ошибка: AI Server установлен, но некоторые службы не смогли запуститься. Логи скопированы в папку logs. Пожалуйста, устраните ошибку и продолжите установку с шага 5.' -ForegroundColor Red
		for ($i=0; $i -lt $ServiceDownList.Count; $i++) {
			switch ($ServiceDownList[$i]) {
				"AI.DescriptionsService" 				{ xcopy "C:\ProgramData\Application Inspector\Logs\descriptionsService" logs\descriptionsService\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.AuthService" 			{ xcopy "C:\ProgramData\Application Inspector\Logs\authService" logs\authService\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.ChangeHistory" 			{ xcopy "C:\ProgramData\Application Inspector\Logs\changeHistoryService" logs\changeHistoryService\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.FileContent.API" 		{ xcopy "C:\ProgramData\Application Inspector\Logs\filesStore" logs\filesStore\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.Gateway" 				{ xcopy "C:\ProgramData\Application Inspector\Logs\gateway" logs\gateway\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.IssueTracker" 			{ xcopy "C:\ProgramData\Application Inspector\Logs\issueTracker" logs\issueTracker\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.NotificationsService" 	{ xcopy "C:\ProgramData\Application Inspector\Logs\notificationsService" logs\notificationsService\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.Projects.API" 			{ xcopy "C:\ProgramData\Application Inspector\Logs\projectManagement" logs\projectManagement\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.SettingsProvider.API" 	{ xcopy "C:\ProgramData\Application Inspector\Logs\settingsProvider" logs\settingsProvider\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.SystemManagement" 		{ xcopy "C:\ProgramData\Application Inspector\Logs\systemManagement" logs\systemManagement\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.UI" 						{ xcopy "C:\ProgramData\Application Inspector\Logs\uiApi" logs\uiApi\ /E /Y | Out-File -Append logs\install.log }
				"AI.Enterprise.UpdateServer" 			{ xcopy "C:\ProgramData\Application Inspector\Logs\updateServer" logs\updateServer\ /E /Y | Out-File -Append logs\install.log }
				"Consul" 								{ xcopy "C:\ProgramData\Application Inspector\Logs\consul" logs\consul\ /E /Y | Out-File -Append logs\install.log;
														xcopy "C:\ProgramData\Application Inspector\Logs\consulTool" logs\consulTool\ /E /Y | Out-File -Append logs\install.log }
				"RabbitMQ" 								{ xcopy $env:APPDATA\RabbitMQ\log logs\RabbitMQ\ /E /Y | Out-File -Append logs\install.log }
				"PostgreSQL" 							{ mkdir logs\PostgreSQL; echo $null > logs\PostgreSQL\error.txt }
			}
		}
		# также проверяем юзеров в кролике т.к. часто проблемы связаны с ним
		& "C:\Program Files\RabbitMQ Server\rabbitmq_server-3.7.8\sbin\rabbitmqctl.bat" list_users 2>&1 | Out-File -Append "logs\install.log"
		Exit
	}
	$AIViewerState = Get-Process ApplicationInspector -ErrorAction SilentlyContinue
	if ($AIViewerState -eq $null) {
		Start-Process "C:\Program Files (x86)\Positive Technologies\Application Inspector Viewer\ApplicationInspector.exe"
	}
	Write-Host 'Подключитесь к серверу с помощью AI Viewer, сгенерируйте фингерпринт на вкладке "О программе" и передайте его сотруднику Positive Technologies для дальнейшей активации лицензии.' -ForegroundColor Yellow
	Write-Host "Адрес сервера: https://$($myFQDN)" -ForegroundColor Yellow
	$step = 5
}

# устанавливаем AI Agent
if ($step -eq 5) {
	Write-Host '---ШАГ 5---' -ForegroundColor Green
	# проверяем что AI Agent уже установлен
	if ([System.IO.File]::Exists("C:\Program Files (x86)\Positive Technologies\Application Inspector Agent\aic.exe")) {
		Write-Host 'Этот шаг уже был выполнен, переходим к следующему.' -ForegroundColor Yellow
	}
	else {
		if ($skipagent) {
			Write-Host 'Пропускаю этап установки агента, переходим к следующему шагу.' -ForegroundColor Yellow
		}
		else {
			Get-AIHome
			Write-Host 'Пожалуйста, следуйте указаниям установщика AI Agent.' -ForegroundColor Yellow
			Write-Host 'Данные для установки: ' -ForegroundColor Yellow
			Write-Host 'Расположение сертификата: C:\TOOLS\certs\INT\out\01\ssl.client.brief.pfx' -ForegroundColor Yellow
			Write-Host "Пароль от сертификата: $($passwords['clientCertificate'])" -ForegroundColor Yellow
			Write-Host "Адрес сервера: https://$($myFQDN)" -ForegroundColor Yellow
			$proc = Start-Process (Get-Current-Version-Path "$($global:AIHOME)\aic" "AIE.Agent*.exe") -passthru
			Wait-Process $proc.Id
			# проверяем что AI Agent установлен
			if (-Not [System.IO.File]::Exists("C:\Program Files (x86)\Positive Technologies\Application Inspector Agent\aic.exe")) {
				Write-Host 'Ошибка: AI Agent не установлен. Пожалуйста, выполните установку AI Agent и продолжите установку с шага 6.' -ForegroundColor Red
				Exit
			}
		}
	}
	$step = 6
}

# конфигурируем интеграционный сервис в консуле
if ($step -eq 6) {
	Write-Host '---ШАГ 6---' -ForegroundColor Green
	# проверяем что этот шаг уже запускался
	if ([System.IO.File]::Exists("C:\TOOLS\BOOT-INF\classes\bootstrap.yml")) {
		Write-Host 'Этот шаг уже был выполнен, переходим к следующему.' -ForegroundColor Yellow
	}
	else {
		Write-Host 'Прописываю настройки интеграционного сервиса в Consul...' -ForegroundColor Yellow
		Invoke-expression -Command $PSScriptRoot\integrationServiceConsulPatch.ps1 -ErrorAction Stop
		if (-Not [System.IO.File]::Exists("C:\TOOLS\BOOT-INF\classes\bootstrap.yml")) {
			Write-Host 'Ошибка: Consul не настроен, логи скопированы в папку logs. Пожалуйста, устраните ошибку и перезапустите установку с шага 6.' -ForegroundColor Red
			Exit
		}
	}
	$step = 7
}

# устанавливаем Jenkins
if ($step -eq 7) {
	Write-Host '---ШАГ 7---' -ForegroundColor Green
	# проверяем что Jenkins уже установлен
	if ([System.IO.File]::Exists("C:\Program Files (x86)\Jenkins\jenkins.exe")) {
		Write-Host 'Этот шаг уже был выполнен, переходим к следующему.' -ForegroundColor Yellow
	}
	else {
		Get-Browser-Path
		# если нет браузера, ставим Chrome в фоновом режиме		
		if ($global:browserPath -eq $null) {
			Write-Host 'Устанавливаю Google Chrome...' -ForegroundColor Yellow
			$proc = Start-Process msiexec -ArgumentList "/i $(Get-Current-Version-Path $PSScriptRoot "google*.msi") /quiet /l*v `"$($PSScriptRoot)\logs\chrome.log`"" -passthru
			Wait-Process $proc.Id
			[bool] $Chromestatus = Get-Content $PSScriptRoot\logs\chrome.log | Select-String "Installation failed"
			if ($Chromestatus) {
				Write-Host 'Ошибка: Google Chrome не установлен, логи скопированы в папку logs. Пожалуйста, установите его вручную.' -ForegroundColor Red
			}
		}
		# Ставим Jenkins в фоновом режиме
		Write-Host 'Устанавливаю Jenkins...' -ForegroundColor Yellow
		$proc = Start-Process msiexec -ArgumentList "/i $(Get-Current-Version-Path $PSScriptRoot "jenkins*.msi") /quiet /l*v `"$($PSScriptRoot)\logs\jenkins.log`"" -passthru
		Wait-Process $proc.Id
		[bool] $Jstatus = Get-Content $PSScriptRoot\logs\jenkins.log | Select-String "Installation failed"
		if ($Jstatus) {
			Write-Host 'Ошибка: Jenkins не установлен, логи скопированы в папку logs. Пожалуйста, установите его вручную и продолжите установку с шага 8.' -ForegroundColor Red
			Exit
		}
	}
	# проверяем состояние службы Jenkins
	try {
		$JenkinsService = Get-Service Jenkins -ErrorAction Stop
	}
	catch {
		Write-Host 'Ошибка: служба Jenkins не найдена: '$_ -ForegroundColor Red
		Write-Host 'Пожалуйста, устраните ошибку и продолжите установку с шага 8.' -ForegroundColor Red
		Exit
	}
	while ($JenkinsService.Status -ne 'Running') {
		copy "C:\Program Files (x86)\Jenkins\jenkins.err.log" logs\jenkins.err.log
		Write-Host 'Ошибка: служба Jenkins не запущена. Логи скопированы в папку logs. Пожалуйста, поднимите службу Jenkins и нажмите Enter для продолжения установки: ' -ForegroundColor Red -NoNewline
		Read-Host
		$JenkinsService = Get-Service Jenkins -ErrorAction SilentlyContinue
	}
	$step = 8
}

# конфигурируем Jenkins
if ($step -eq 8) {
	Write-Host '---ШАГ 8---' -ForegroundColor Green
	# проверяем что настройка Jenkins уже производилась
	if ([System.IO.File]::Exists("C:\TOOLS\BOOT-INF\classes\application.yml")) {
		Write-Host 'Этот шаг уже был выполнен, переходим к следующему.' -ForegroundColor Yellow
	}
	else {
		Write-Host 'Настраиваю Jenkins...' -ForegroundColor Yellow 
		Write-Host 'Копирую плагины...' -ForegroundColor Yellow
		xcopy plugins "C:\Program Files (x86)\Jenkins\plugins\" /E /Y | Out-File -Append logs\install.log
		if ($noad) {
			Invoke-expression -Command "$($PSScriptRoot)\configureJenkins.ps1 -step 1 -noad" -ErrorAction Stop
		}
		else {
			Invoke-expression -Command "$($PSScriptRoot)\configureJenkins.ps1 -step 1" -ErrorAction Stop
		}
		if (-Not [System.IO.File]::Exists("C:\TOOLS\BOOT-INF\classes\application.yml")) {
			Write-Host 'Ошибка: токен для доступа к Jenkins не сформирован. Пожалуйста, устраните ошибку и перезапустите установку с шага 8.' -ForegroundColor Red
			Exit
		}
	}
	$step = 9
}

# конфигурируем интеграционный сервис
if ($step -eq 9) {
	Write-Host '---ШАГ 9---' -ForegroundColor Green
	# проверяем что данный шаг уже запускался
	if ([System.IO.File]::Exists("C:\TOOLS\admin")) {
		# проверяем, что интеграционный сервис запущен
		$proc = Get-Process java | Where CPU -ne $null | Select Id
		for ($i=0; $i -lt $proc.Length; $i++) {
			$tmp = Invoke-expression -Command "wmic process where processid=$($proc[$i].Id) get commandline"
			if ($tmp -match "ptai-integration-service-0.1-spring-boot.jar") {
				[bool] $servicerunning = 1
			}
		}
		# если нет, запускаем его
		if ($servicerunning -eq $null)
		{
			Write-Host 'Запускаю интеграционный сервис...' -ForegroundColor Yellow
			start C:\TOOLS\run-service.bat
		}
		Write-Host 'Этот шаг уже был выполнен, переходим к следующему.' -ForegroundColor Yellow
	}
	else {
		Write-Host 'Патчу интеграционный сервис...' -ForegroundColor Yellow
		Set-Location -Path C:\TOOLS
		# подчищаем временные файлы на случай если раньше этот шаг уже запускался
		Get-ChildItem -Path 'C:\TOOLS' *.tmp | foreach { Remove-Item -Path $_.FullName }
		# обновляем файлы в jar
		jar uf ptai-integration-service-0.1-spring-boot.jar BOOT-INF\classes\
		Write-Host 'Запускаю интеграционный сервис...' -ForegroundColor Yellow
		start C:\TOOLS\run-service.bat
		$timer = 0
		while ($pluginoutput -eq $null) {
			if ([System.IO.File]::Exists("C:\TOOLS\admin")) {
				[bool] $pluginoutput = 1
			}
			elseif ($timer -eq 80) {
				[bool] $pluginoutput = 0
			}
			Start-Sleep 1
			$timer++
		}
		if (-Not $pluginoutput) {
			Write-Host 'Ошибка: интеграционный сервис не смог запуститься. Пожалуйста, исправьте ошибку и запустите его вручную (C:\TOOLS\run-service.bat), после чего продолжите установку с шага 10.' -ForegroundColor Red
			Exit
		}
	}
	$step = 10
}

# Продолжаем патчить Jenkins
if ($step -eq 10) {
	Write-Host '---ШАГ 10---' -ForegroundColor Green
	# проверяем что данный шаг уже запускался
	Set-Location -Path $PSScriptRoot
	if ([System.IO.File]::Exists("C:\TOOLS\run-agent.bat") `
		-and [System.IO.File]::Exists("C:\TOOLS\readme.txt") `
		-and [System.IO.File]::Exists("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\run-service.bat") `
		-and [System.IO.File]::Exists("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\run-agent.bat")) {
		Write-Host 'Этот шаг уже был выполнен.' -ForegroundColor Yellow		
		# проверяем, что агент jenkins запущен
		$proc = Get-Process java | Where CPU -ne $null | Select Id
		for ($i=0; $i -lt $proc.Length; $i++) {
			$tmp = Invoke-expression -Command "wmic process where processid=$($proc[$i].Id) get commandline"
			if ($tmp -match "agent.jar") {
				[bool] $agentrunning = 1
			}
		}
		# если нет, запускаем его
		if ($agentrunning -eq $null)
		{
			Write-Host 'Запускаю агента Jenkins...' -ForegroundColor Yellow	
			start C:\TOOLS\run-agent.bat
		}
	}
	else {
		Write-Host 'Продолжаю настройку Jenkins...' -ForegroundColor Yellow 
		if ($noad) {
			Invoke-expression -Command "$($PSScriptRoot)\configureJenkins.ps1 -step 2 -noad" -ErrorAction Stop
		}
		else {
			Invoke-expression -Command "$($PSScriptRoot)\configureJenkins.ps1 -step 2" -ErrorAction Stop
		}
		if (-Not [System.IO.File]::Exists("C:\TOOLS\run-agent.bat")) {
			Write-Host 'Ошибка: данные для запуска агента Jenkins не найдены. Пожалуйста, устраните ошибку и перезапустите установку с шага 10.' -ForegroundColor Red
			Exit
		}
		Write-Host 'Запускаю агента Jenkins...' -ForegroundColor Yellow	
		start C:\TOOLS\run-agent.bat
		# заменяем ключевые значения в readme.txt
		$adminpwd = Get-Content -Path "C:\TOOLS\admin"
		$readme = Get-Content -Path $PSScriptRoot\config\readme.txt -Raw
		if ($noad) {
			$IP = Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -ne "Disconnected"} | Select -ExpandProperty IPv4Address | Select -ExpandProperty IPAddress
			$readme = $readme -ireplace '%myFQDN%',"$IP"
		}
		else {
			$readme = $readme -ireplace '%myFQDN%',"$myFQDN"
		}
		$readme -ireplace '%adminpwd%',"$adminpwd" | Set-Content -Path C:\TOOLS\readme.txt
		# подчищаем временные файлы
		Get-ChildItem -Path 'C:\TOOLS' *.tmp | foreach { Remove-Item -Path $_.FullName }
		# добавляем каталогу права на запись для пользователей чтобы не было проблем при ручном запуске скриптов
		$ACL = Get-Acl "C:\TOOLS"
		try {
			# для английской windows
			$ACL.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule([System.Security.Principal.NTAccount]"users","fullcontrol", "ContainerInherit, ObjectInherit", "None", "Allow")))
		}
		catch {
			# для русской windows
			$_ | Out-File -Append logs\install.log
			$ACL.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule([System.Security.Principal.NTAccount]"Пользователи","fullcontrol", "ContainerInherit, ObjectInherit", "None", "Allow")))		
		}
		Set-Acl "C:\TOOLS" $ACL
		# помещаем ссылки на скрипт в автозапуск текущего пользователя
		Write-Host 'Добавляю символические ссылки в автозапуск системы...' -ForegroundColor Yellow
		New-Item -Path $env:APPDATA"\Microsoft\Windows\Start Menu\Programs\Startup\run-service.bat" -ItemType SymbolicLink -Value C:\TOOLS\run-service.bat | Out-File -Append logs\install.log
		New-Item -Path $env:APPDATA"\Microsoft\Windows\Start Menu\Programs\Startup\run-agent.bat" -ItemType SymbolicLink -Value C:\TOOLS\run-agent.bat | Out-File -Append logs\install.log
	}
	Write-Host 'Установка завершена успешно!' -ForegroundColor Cyan
	Write-Host 'Инструкции по встраиванию Application Inspector в систему сборки кода см. в файле C:\TOOLS\readme.txt.' -ForegroundColor Cyan
	start notepad++ C:\TOOLS\readme.txt
	
	# устанавливаем Git
	if (-Not [System.IO.File]::Exists("C:\Program Files\Git\cmd\git.exe")) {
		Write-Host 'Если вы хотите использовать внутренний Jenkins для запуска сканирования и в качестве источника будет git-репозиторий вашей организации, требуется установить Git for Windows.' -ForegroundColor Yellow
		Write-Host 'Установить Git for Windows? (y/n): ' -ForegroundColor Yellow -NoNewline
		$choice = Read-Host
		if ($choice -eq 'y') {
			Write-Host 'Устанавливаю Git...' -ForegroundColor Yellow
			$proc = Start-Process (Get-Current-Version-Path $PSScriptRoot "Git*.exe") -ArgumentList "/VERYSILENT" -passthru
			Wait-Process $proc.Id
			if ([System.IO.File]::Exists("C:\Program Files\Git\etc\gitconfig")) {
				Write-Host 'Обновляю конфигурацию Git...' -ForegroundColor Yellow
				copy config\gitconfig "C:\Program Files\Git\etc\gitconfig" | Out-File -Append logs\install.log
				Write-Host 'Установка Git завершена.' -ForegroundColor Yellow				
			}
			else {
				Write-Host 'Ошибка: Git не установлен. Пожалуйста, установите его вручную.' -ForegroundColor Red
			}
		}
	}
}
