#Requires -RunAsAdministrator

# Инсталлятор AI Enterprise и его окружения
# версия 0.5 от 13.07.2020

Param (
[ValidateRange(1,10)]
[int]$step,
[switch]$genpass,
[switch]$noad,
[switch]$skipagent,
[switch]$skipcerts,
[switch]$add_admin,
[switch]$install
)

# проверяем, заполнен ли AIHOME
function Get-AIHome {
	if ($global:AIHOME -eq $null) {
		Write-Host 'Пожалуйста, укажите полный путь до каталога с дистрибутивами AI Enterprise (где находятся каталоги aiv, aie, aic) без \ в конце: ' -ForegroundColor Yellow -NoNewline
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
		Write-Host "Ошибка: файл $($mask) не найден в каталоге $($path). Возможно, вы указали относительный путь вместо полного пути." -ForegroundColor Red
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

# Обработка результата установки дистрибутива
function Handle-Install-Result($name, $proc, $step, [bool]$critical) {
	Wait-Process $proc.Id
	if ($proc.ExitCode -ne 0) {
		$errortext = "Ошибка: что-то пошло не так при установке $($name), код выхода $($proc.ExitCode). Логи скопированы в папку logs. "
		if ($critical) {
			$errortext += "Пожалуйста, устраните ошибку и продолжите установку с шага $($step)."
			$errortext | Tee-Object -Append logs\install.log | Write-Host -ForegroundColor Red
			Exit
		}
		else {
			$errortext += "Пожалуйста, установите его вручную."
			$errortext | Tee-Object -Append logs\install.log | Write-Host -ForegroundColor Red
		}
	}
}

# добавить текущего пользователя в качестве администратора AI через запрос в базу данных
function AI-Add-Admin {
	if ([System.IO.File]::Exists("C:\Program Files (x86)\Positive Technologies\Application Inspector Server\Services\gateway\AIE.Gateway.exe")) {
		if (-Not (Test-Path "C:\Program Files\psqlODBC")) {
			Write-Host 'Устанавливаю ODBC драйвер для Postgres...' -ForegroundColor Yellow
			$proc = Start-Process msiexec -ArgumentList "/i $(Get-Current-Version-Path $PSScriptRoot "psqlodbc*.msi") /quiet /l*v `"$($PSScriptRoot)\logs\psqlodbc.log`"" -passthru
			Handle-Install-Result "Postgres ODBC Driver" $proc $step+1 $false
			if ($proc.ExitCode -ne 0) {
				Write-Host "После этого выполните скрипт со следующими параметрами по очереди: " -ForegroundColor Red
				Write-Host ".\AI-Wizard.ps1 -add_admin" -ForegroundColor Red
				Write-Host ".\AI-Wizard.ps1 -step 4" -ForegroundColor Red
			}
		}
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
		net stop AI.Enterprise.AuthService 2>&1 | Out-File -Append logs\install.log
		net start AI.Enterprise.AuthService 2>&1 | Out-File -Append logs\install.log
		Write-Host 'Успех!' -ForegroundColor Cyan
	}
	else {
		Write-Host 'Ошибка: Компонент AI Server не установлен.' -ForegroundColor Red
	}
}

# информационное сообщение при запуске без параметров
if ($PsBoundParameters.count -eq 0) {
	Write-Host 'Данный скрипт поможет вам установить Application Inspector Enterprise Edition. Доступные параметры запуска:' -ForegroundColor Yellow
	Write-Host '-install: запустить установку с первого шага' -ForegroundColor Yellow
	Write-Host '-step [номер]: запустить установку с указанного шага' -ForegroundColor Yellow
	Write-Host '-genpass: сгенерировать сложные пароли' -ForegroundColor Yellow
	Write-Host '-noad: локальная установка без Active Directory' -ForegroundColor Yellow
	Write-Host '-skipagent: пропустить этап установки агента AI, если его планируется ставить на отдельном сервере' -ForegroundColor Yellow
	# TODO
	# Write-Host '-skipcerts: пропустить этап генерации самоподписанных сертификатов' -ForegroundColor Yellow
	Write-Host 'Пример запуска с параметрами:' -ForegroundColor Yellow
	Write-Host '.\AI-Wizard.ps1 -install -genpass' -ForegroundColor Yellow
	Write-Host '.\AI-Wizard.ps1 -step 3' -ForegroundColor Yellow
	Exit
}
# показываем с какими параметрами запуск чтобы предотвратить опечатки
elseif ($PsBoundParameters.count -eq 1 -and $install) {
	Write-Host "Запускаю инсталлятор без дополнительных параметров..." -ForegroundColor Yellow
}
elseif ($PsBoundParameters.count -gt 0) {
	Write-Host "Запускаю инсталлятор с параметрами " -ForegroundColor Yellow -NoNewline
	for ( $i = 0; $i -lt $PsBoundParameters.count; $i++ ) {
		Write-Host "-$($($PsBoundParameters.Keys)[$i]) " -ForegroundColor Yellow -NoNewline
	}
	Write-Host
}

# инициализация
Set-Location -Path $PSScriptRoot
if (-Not (Test-Path logs)) {mkdir logs >$null}
if (Test-Path logs\install.log) {
	copy logs\install.log "logs\install-$((New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date)).Ticks).log"
}
date | Out-File logs\install.log
if ($noad){
	$myFQDN = $env:ComputerName
} 
else {
	$myFQDN = ((Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain).ToLower()
}
$domain = ((Get-WmiObject win32_computersystem).Domain).ToLower()

# Обработка команды добавления текущего пользователя в админы
if ($add_admin) {
	AI-Add-Admin
	Exit
}

# импортируем пароли из файла
if ([System.IO.File]::Exists("C:\TOOLS\passwords.xml")) {
	$passwords = Import-Clixml -Path "C:\TOOLS\passwords.xml"
}
elseif ($step -gt 1) {
	Write-Host "Ошибка: первый запуск скрипта должен быть выполнен с первого шага." -ForegroundColor Red
	$step = 1
}

# проверяем что пререквизиты установки выполнены
if ($step -eq 1 -or $step -eq '') {
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
				# подготавливаем каталоги для утилит
				mkdir -p C:\TOOLS\BOOT-INF\classes\liquibase 2>&1 | Out-File -Append logs\install.log
				mkdir -p C:\TOOLS\certs\INT 2>&1 | Out-File -Append logs\install.log
				mkdir -p C:\TOOLS\certs\ROOT 2>&1 | Out-File -Append logs\install.log
				mkdir -p C:\TOOLS\certs\conf 2>&1 | Out-File -Append logs\install.log
				mkdir -p C:\TOOLS\certs\src 2>&1 | Out-File -Append logs\install.log
				# проверяем java и openssl
				if ($env:Path -match 'jdk|java') {
					Write-Host 'Предупреждение: в Path обнаружена Java.' -ForegroundColor Cyan
				}
				xcopy jdk1.8 C:\TOOLS\jdk1.8\ /E /Y 2>&1 | Out-File -Append logs\install.log
				if ($env:Path -match 'openssl') {
					Write-Host 'Предупреждение: в Path обнаружен Openssl.' -ForegroundColor Cyan
				}
				xcopy openssl C:\TOOLS\openssl\ /E /Y 2>&1 | Out-File -Append logs\install.log
				# обновляем глобальную переменную Path
				[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\TOOLS\openssl\bin;C:\TOOLS\jdk1.8\bin", "Machine")
				# обновляем знания текущей сессии Powershell о Path
				$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
				# копируем необходимые утилиты для установки
				copy config\root_ca.conf C:\TOOLS\certs\conf\root_ca.conf
				copy config\int_ca.conf C:\TOOLS\certs\conf\int_ca.conf
				copy config\ssl.server.conf C:\TOOLS\certs\conf\ssl.server.conf
				copy config\ssl.client.conf C:\TOOLS\certs\conf\ssl.client.conf
				copy generateCertificates.ps1 C:\TOOLS\certs\src\generateCertificates.ps1
				copy ptai-integration-service-0.1-spring-boot.jar C:\TOOLS\ptai-integration-service-0.1-spring-boot.jar
				copy ptai-cli-plugin-0.1-jar-with-dependencies.jar C:\TOOLS\ptai-cli-plugin.jar
				copy WinSW.NET461.exe C:\TOOLS\ptai-integration-service.exe
				copy config\ptai-integration-service.xml C:\TOOLS\ptai-integration-service.xml
				copy plugins\jenkins\ptai-jenkins-plugin.hpi C:\TOOLS\ptai-jenkins-plugin.hpi
				copy plugins\ptai-teamcity-plugin.zip C:\TOOLS\ptai-teamcity-plugin.zip
				copy agent.jar C:\TOOLS\agent.jar
				copy WinSW.NET461.exe C:\TOOLS\agent.exe
				# выключаем окно первого запуска IE чтобы работали запросы через функцию Invoke-WebRequest
				&{Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main" -Name "DisableFirstRunCustomize" -Value 2} 2>&1 | Tee-Object -Append logs\install.log | Write-Host -ForegroundColor Red
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
		Write-Host 'Устанавливаю AI Viewer...' -ForegroundColor Yellow
		$proc = Start-Process (Get-Current-Version-Path "$($global:AIHOME)\aiv" "AIE.Viewer*.exe") -ArgumentList "/eulaagree /verysilent /norestart" -passthru
		Handle-Install-Result "AI Viewer" $proc $step+1 $true
		$AIViewer = Get-Process ApplicationInspector -ErrorAction SilentlyContinue
		if ($AIViewer -ne $null) {Stop-Process $AIViewer}
		# проверяем что на машине есть нормальный блокнот
		if (-Not [System.IO.File]::Exists("C:\Program Files (x86)\Notepad++\notepad++.exe")) {
			# если нет, то ставим Notepad++ в фоновом режиме
			Write-Host 'Устанавливаю Notepad++...' -ForegroundColor Yellow
			$proc = Start-Process (Get-Current-Version-Path $PSScriptRoot "npp*.exe") -ArgumentList "/S" -passthru
			Handle-Install-Result "Notepad++" $proc $step+1 $false
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
		if ($skipcerts) {
			Write-Host 'Пропускаю этап генерации сертификатов, переходим к следующему шагу.' -ForegroundColor Yellow
		}
		else {
			if ($noad) {
				Invoke-expression -Command "C:\TOOLS\certs\src\generateCertificates.ps1 -noad 2>&1" -ErrorAction Stop | %{ "$_" } | Out-File -Append logs\install.log
			}
			else {
				Invoke-expression -Command "C:\TOOLS\certs\src\generateCertificates.ps1 2>&1" -ErrorAction Stop | %{ "$_" } | Out-File -Append logs\install.log
			}
			Set-Location -Path $PSScriptRoot
			# проверяем что сертификаты сгенерировались
			if ([System.IO.File]::Exists("C:\TOOLS\certs\server-private.jks")) {
				Write-Host 'Сертификаты были сгенерированы успешно и сохранены в C:\TOOLS\certs\INT\out.' -ForegroundColor Yellow
				# меняем пароль на java cacerts если запуск был с параметром genpass
				if ($passwords['javaCacerts'] -ne 'changeit') {
					Write-Host 'Меняю пароль на хранилище сертификатов Java...' -ForegroundColor Yellow
					# пояснение к способу логирования: вывод keytool и других утилит Powershell транслирует в stderr, что засоряет лог ошибками NativeCommandError. Поэтому весь вывод преобразуется в string, и только потом в конечный лог.
					keytool -storepasswd -new "$($passwords['javaCacerts'])" -storepass changeit -keystore "C:\TOOLS\jdk1.8\jre\lib\security\cacerts" 2>&1 | %{ "$_" } | Out-File -Append logs\install.log
				}
				# добавляем сертификаты в cacerts java
				Write-Host 'Добавляю сертификаты в хранилище сертификатов Java...' -ForegroundColor Yellow
				keytool -importkeystore -noprompt -srckeystore "C:/TOOLS/certs/server-private.jks" -srcstorepass "$($passwords['serverCertificate'])" -destkeystore "C:\TOOLS\jdk1.8\jre\lib\security\cacerts" -deststoretype JKS -deststorepass "$($passwords['javaCacerts'])" 2>&1 | %{ "$_" } | Out-File -Append logs\install.log
				keytool -importkeystore -noprompt -srckeystore "C:/TOOLS/certs/ssl.client.brief.pfx" -srcstorepass "$($passwords['clientCertificate'])" -srcstoretype pkcs12 -destkeystore "C:\TOOLS\jdk1.8\jre\lib\security\cacerts" -deststoretype JKS -deststorepass "$($passwords['javaCacerts'])" 2>&1 | %{ "$_" } | Out-File -Append logs\install.log
				Write-Host 'Импортирую сертификаты в хранилище Windows...' -ForegroundColor Yellow
				&{Import-Certificate -FilePath "C:\TOOLS\certs\ROOT\certs\RootCA.pem.crt" -CertStoreLocation Cert:\LocalMachine\Root} 2>&1 | Out-File -Append logs\install.log
				&{Import-Certificate -FilePath "C:\TOOLS\certs\INT\certs\IntermediateCA.pem.crt" -CertStoreLocation Cert:\LocalMachine\CA} 2>&1 | Out-File -Append logs\install.log
			}
			else {
				Write-Host 'Ошибка: сертификаты не созданы. Логи скопированы в папку logs. Пожалуйста, устраните ошибку и перезапустите установку с шага 3.' -ForegroundColor Red
				Exit
			}
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
		if ($noad) {
			[bool] $domainfound = 0
		}
		else {
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
		Write-Host 'Для копирования текста из окна Powershell выделите текст и нажмите правую кнопку мыши.' -ForegroundColor Cyan
		Write-Host 'Важно: при установке укажите любое имя пользователя сервиса очередей вместо значения по умолчанию "guest"' -ForegroundColor Yellow
		
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
		
		if (-Not $skipcerts) {
			Write-Host 'Расположение сертификата: C:\TOOLS\certs\INT\out\00\ssl.server.brief.pfx' -ForegroundColor Yellow
			Write-Host "Пароль от сертификата: $($passwords['serverCertificate'])" -ForegroundColor Yellow
		}
		
		# производим установку сервера
		if ($domainfound) {
			$proc = Start-Process (Get-Current-Version-Path "$($global:AIHOME)\aie" "AIE.Server*.exe") -passthru
		}
		# с флагом /noad если не смогли найти домен
		else {
			Write-Host "Предупреждение: домен не найден, провожу установку с флагом /noad. После установки вам будет предложено добавить пользователя в базу данных." -ForegroundColor Cyan
			$proc = Start-Process (Get-Current-Version-Path "$($global:AIHOME)\aie" "AIE.Server*.exe") -ArgumentList "/noad" -passthru
		}
		Handle-Install-Result "AI Server" $proc $step $true
		xcopy "C:\ProgramData\Application Inspector\Logs\deploy" logs\deploy\ /E /Y 2>&1 | Out-File -Append logs\install.log
		
		# если домен не обнаружен, добавляем текущего пользователя в качестве админа через базу данных
		if (-Not $domainfound) {
			AI-Add-Admin
		}
	}
	# проверяем наличие служб
	try {
		$AIServiceStatus = Get-Service AI.*,Consul,RabbitMQ,PostgreSQL -ErrorAction Stop
	}
	catch {
		Write-Host 'Ошибка проверки служб: '$_ -ForegroundColor Red
		Write-Host 'Логи скопированы в папку logs. Пожалуйста, устраните ошибку и продолжите установку с шага 5.' -ForegroundColor Red
		xcopy "C:\ProgramData\Application Inspector\Logs\deploy" logs\deploy\ /E /Y 2>&1 | Out-File -Append logs\install.log
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
				"AI.DescriptionsService" 				{ xcopy "C:\ProgramData\Application Inspector\Logs\descriptionsService" logs\descriptionsService\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.AuthService" 			{ xcopy "C:\ProgramData\Application Inspector\Logs\authService" logs\authService\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.ChangeHistory" 			{ xcopy "C:\ProgramData\Application Inspector\Logs\changeHistoryService" logs\changeHistoryService\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.FileContent.API" 		{ xcopy "C:\ProgramData\Application Inspector\Logs\filesStore" logs\filesStore\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.Gateway" 				{ xcopy "C:\ProgramData\Application Inspector\Logs\gateway" logs\gateway\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.IssueTracker" 			{ xcopy "C:\ProgramData\Application Inspector\Logs\issueTracker" logs\issueTracker\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.NotificationsService" 	{ xcopy "C:\ProgramData\Application Inspector\Logs\notificationsService" logs\notificationsService\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.Projects.API" 			{ xcopy "C:\ProgramData\Application Inspector\Logs\projectManagement" logs\projectManagement\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.SettingsProvider.API" 	{ xcopy "C:\ProgramData\Application Inspector\Logs\settingsProvider" logs\settingsProvider\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.SystemManagement" 		{ xcopy "C:\ProgramData\Application Inspector\Logs\systemManagement" logs\systemManagement\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.UI" 						{ xcopy "C:\ProgramData\Application Inspector\Logs\uiApi" logs\uiApi\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"AI.Enterprise.UpdateServer" 			{ xcopy "C:\ProgramData\Application Inspector\Logs\updateServer" logs\updateServer\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"Consul" 								{ xcopy "C:\ProgramData\Application Inspector\Logs\consul" logs\consul\ /E /Y 2>&1 | Out-File -Append logs\install.log;
														xcopy "C:\ProgramData\Application Inspector\Logs\consulTool" logs\consulTool\ /E /Y 2>&1 | Out-File -Append logs\install.log }
				"RabbitMQ" 								{ "ERROR: RabbitMQ is down" | Out-File -Append logs\install.log }
				"PostgreSQL" 							{ mkdir logs\PostgreSQL 2>&1 | Out-File -Append logs\install.log; echo $null > logs\PostgreSQL\error.txt }
			}
		}
		# также копируем те логи где чаще всего бывают проблемы
		& "C:\Program Files\RabbitMQ Server\rabbitmq_server-3.7.8\sbin\rabbitmqctl.bat" list_users 2>&1 | Out-File -Append "logs\install.log"
		xcopy $env:APPDATA\RabbitMQ\log logs\RabbitMQ\ /E /Y 2>&1 | Out-File -Append logs\install.log
		Exit
	}
	# запускаем AI Viewer если не запущен чтобы пользователь подготовил фингерпринт
	$AIViewer = Get-Process ApplicationInspector -ErrorAction SilentlyContinue
	if ($AIViewer -eq $null) {
		Start-Process "C:\Program Files (x86)\Positive Technologies\Application Inspector Viewer\ApplicationInspector.exe"
	}
	Write-Host 'Подключитесь к серверу с помощью AI Viewer, сгенерируйте фингерпринт на вкладке "О программе" и передайте его сотруднику Positive Technologies для дальнейшей активации лицензии.' -ForegroundColor Cyan
	Write-Host "Адрес сервера: https://$($myFQDN)" -ForegroundColor Cyan
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
			if (-Not $skipcerts) {
				Write-Host 'Расположение сертификата: C:\TOOLS\certs\INT\out\01\ssl.client.brief.pfx' -ForegroundColor Yellow
				Write-Host "Пароль от сертификата: $($passwords['clientCertificate'])" -ForegroundColor Yellow
			}
			Write-Host "Адрес сервера: https://$($myFQDN)" -ForegroundColor Yellow
			$proc = Start-Process (Get-Current-Version-Path "$($global:AIHOME)\aic" "AIE.Agent*.exe") -passthru
			Handle-Install-Result "AI Agent" $proc $step+1 $true
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
		Invoke-expression -Command "$($PSScriptRoot)\integrationServiceConsulPatch.ps1 2>&1" -ErrorAction Stop | Out-File -Append logs\install.log
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
			$proc = Start-Process msiexec -ArgumentList "/i $(Get-Current-Version-Path $PSScriptRoot "Google*.msi") /quiet /l*v `"$($PSScriptRoot)\logs\chrome.log`"" -passthru
			Handle-Install-Result "Google Chrome" $proc $step+1 $false
		}
		# Ставим Jenkins в фоновом режиме
		Write-Host 'Устанавливаю Jenkins...' -ForegroundColor Yellow
		$proc = Start-Process msiexec -ArgumentList "/i $(Get-Current-Version-Path $PSScriptRoot "jenkins*.msi") /quiet /l*v `"$($PSScriptRoot)\logs\jenkins.log`"" -passthru
		Handle-Install-Result "Jenkins" $proc $step+1 $true
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
		xcopy plugins\jenkins "C:\Program Files (x86)\Jenkins\plugins\" /E /Y 2>&1 | Out-File -Append logs\install.log
		if ($noad) {
			Invoke-expression -Command "$($PSScriptRoot)\configureJenkins.ps1 -step 1 -noad 2>&1" -ErrorAction Stop | Out-File -Append logs\install.log
		}
		else {
			Invoke-expression -Command "$($PSScriptRoot)\configureJenkins.ps1 -step 1 2>&1" -ErrorAction Stop | Out-File -Append logs\install.log
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
	$IntegrationService = Get-Service "AI.Enterprise.IntegrationService" -ErrorAction SilentlyContinue
	if ([System.IO.File]::Exists("C:\TOOLS\admin") -and $IntegrationService -ne $null) {
		# проверяем, что интеграционный сервис запущен
		if ($IntegrationService.Status -ne 'Running') {
			Write-Host 'Запускаю интеграционный сервис...' -ForegroundColor Yellow
			&{Start-Service -Name "AI.Enterprise.IntegrationService"} 2>&1 | Out-File -Append logs\install.log
		}
		else {
			Write-Host 'Этот шаг уже был выполнен, переходим к следующему.' -ForegroundColor Yellow
		}
	}
	else {
		Write-Host 'Патчу интеграционный сервис...' -ForegroundColor Yellow
		Set-Location -Path C:\TOOLS
		# подчищаем временные файлы на случай если раньше этот шаг уже запускался
		Get-ChildItem -Path 'C:\TOOLS' *.tmp | foreach { Remove-Item -Path $_.FullName }
		# обновляем файлы в jar
		jar uf ptai-integration-service-0.1-spring-boot.jar BOOT-INF\classes\
		Set-Location -Path $PSScriptRoot
		# ставим интеграционный сервис как службу Windows и проверяем его работу
		Write-Host 'Устанавливаю интеграционный сервис в качестве службы Windows "AI.Enterprise.IntegrationService"...' -ForegroundColor Yellow
		$proc = Start-Process C:\TOOLS\ptai-integration-service.exe -ArgumentList "install" -passthru
		Handle-Install-Result "интеграционного сервиса PT AI" $proc $step+1 $true
		Write-Host 'Запускаю интеграционный сервис...' -ForegroundColor Yellow
		&{Start-Service -Name "AI.Enterprise.IntegrationService"} 2>&1 | Out-File -Append logs\install.log
		$timer = 0
		while ($serviceoutput -eq $null) {
			Start-Sleep 1
			$timer++
			$IntegrationService = Get-Service "AI.Enterprise.IntegrationService" -ErrorAction SilentlyContinue
			if ([System.IO.File]::Exists("C:\TOOLS\admin")) {
				[bool] $serviceoutput = 1
			}
			elseif ($IntegrationService.Status -ne 'Running') {
				[bool] $serviceoutput = 0
			}
			elseif ($timer -eq 90) {
				[bool] $serviceoutput = 0
			}
		}
		if (-Not $serviceoutput) {
			Write-Host 'Ошибка: интеграционный сервис не смог запуститься. Логи скопированы в папку logs. Пожалуйста, исправьте ошибку и продолжите установку с шага 10.' -ForegroundColor Red
			copy C:\TOOLS\ptai-integration-service.out logs\ptai-integration-service.out
			Exit
		}
	}
	$step = 10
}

# Продолжаем патчить Jenkins
if ($step -eq 10) {
	Write-Host '---ШАГ 10---' -ForegroundColor Green
	# проверяем что данный шаг уже запускался
	$JenkinsService = Get-Service "Jenkins.Agent" -ErrorAction SilentlyContinue
	if ([System.IO.File]::Exists("C:\TOOLS\agent.xml") `
		-and [System.IO.File]::Exists("C:\TOOLS\instructions.txt") `
		-and $JenkinsService -ne $null) {
		Write-Host 'Этот шаг уже был выполнен.' -ForegroundColor Yellow		
		# проверяем, что агент jenkins запущен
		if ($JenkinsService.Status -ne 'Running') {
			Write-Host 'Запускаю агента Jenkins...' -ForegroundColor Yellow
			&{Start-Service -Name "Jenkins.Agent"} 2>&1 | Out-File -Append logs\install.log
		}
	}
	else {
		Write-Host 'Продолжаю настройку Jenkins...' -ForegroundColor Yellow 
		if ($noad) {
			Invoke-expression -Command "$($PSScriptRoot)\configureJenkins.ps1 -step 2 -noad 2>&1" -ErrorAction Stop | Out-File -Append logs\install.log
		}
		else {
			Invoke-expression -Command "$($PSScriptRoot)\configureJenkins.ps1 -step 2 2>&1" -ErrorAction Stop | Out-File -Append logs\install.log
		}
		if (-Not [System.IO.File]::Exists("C:\TOOLS\agent.xml")) {
			Write-Host 'Ошибка: данные для запуска агента Jenkins не найдены. Пожалуйста, устраните ошибку и перезапустите установку с шага 10.' -ForegroundColor Red
			Exit
		}
		# ставим агента Jenkins как службу Windows и проверяем его работу
		Write-Host 'Устанавливаю агента Jenkins в качестве службы Windows "Jenkins.Agent"...' -ForegroundColor Yellow
		$proc = Start-Process C:\TOOLS\agent.exe -ArgumentList "install" -passthru
		Handle-Install-Result "агента Jenkins" $proc $step $true
		Write-Host 'Запускаю агента Jenkins...' -ForegroundColor Yellow
		&{Start-Service -Name "Jenkins.Agent"} 2>&1 | Out-File -Append logs\install.log
		Start-Sleep 3
		
		# заменяем ключевые значения в instructions.txt
		$adminpwd = Get-Content -Path "C:\TOOLS\admin"
		$instructions = Get-Content -Path $PSScriptRoot\config\instructions.txt -Raw
		if ($noad) {
			$IP = Get-NetIPConfiguration | Where-Object {$_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -ne "Disconnected"} | Select -ExpandProperty IPv4Address | Select -ExpandProperty IPAddress
			$instructions = $instructions -ireplace '%myFQDN%',"$IP"
		}
		else {
			$instructions = $instructions -ireplace '%myFQDN%',"$myFQDN"
		}
		$instructions -ireplace '%adminpwd%',"$adminpwd" | Set-Content -Path C:\TOOLS\instructions.txt
		
		# подчищаем временные файлы
		Get-ChildItem -Path 'C:\TOOLS' *.tmp | foreach { Remove-Item -Path $_.FullName }
		# добавляем каталогу права на запись для пользователей чтобы не было проблем при ручном запуске
		$ACL = Get-Acl "C:\TOOLS"
		try {
			# для английской windows
			&{$ACL.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule([System.Security.Principal.NTAccount]"users","fullcontrol", "ContainerInherit, ObjectInherit", "None", "Allow")))} 2>&1 | Out-File -Append logs\install.log
		}
		catch {
			# для русской windows
			$_ | Out-File -Append logs\install.log
			&{$ACL.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule([System.Security.Principal.NTAccount]"Пользователи","fullcontrol", "ContainerInherit, ObjectInherit", "None", "Allow")))} 2>&1 | Out-File -Append logs\install.log
		}
		try {
			&{Set-Acl "C:\TOOLS" $ACL} 2>&1 | Out-File -Append logs\install.log
		}
		catch {
			Write-Host 'Ошибка: Не удалось изменить права для каталога C:\TOOLS.' -ForegroundColor Red
		}
	}
	$JenkinsService = Get-Service "Jenkins.Agent" -ErrorAction SilentlyContinue
	$IntegrationService = Get-Service "AI.Enterprise.IntegrationService" -ErrorAction SilentlyContinue
	if ($JenkinsService.Status -ne 'Running') {
		Write-Host 'Ошибка: служба агента Jenkins не запущена. Пожалуйста, устраните ошибку для работы системы.' -ForegroundColor Red
		copy C:\TOOLS\agent.out logs\agent.out
	}
	if ($IntegrationService.Status -ne 'Running') {
		Write-Host 'Ошибка: служба интеграционного сервиса не запущена. Пожалуйста, устраните ошибку для работы системы.' -ForegroundColor Red
		copy C:\TOOLS\ptai-integration-service.out logs\ptai-integration-service.out
	}
	
	# собираем статистику по ошибкам
	$logstatus = Get-Content logs\install.log | Select-String -Pattern "error|ошибка|Exception"
	$errorlist = New-Object System.Collections.Generic.List[System.Object]
	for ($i=0; $i -lt $logstatus.Length; $i++) {
		$errorlist.Add($logstatus[$i])
	}
	
	Write-Host 'Установка завершена!' -ForegroundColor Cyan
	Write-Host 'Инструкции по встраиванию Application Inspector в систему сборки кода см. в файле C:\TOOLS\instructions.txt.' -ForegroundColor Cyan
	start notepad++ C:\TOOLS\instructions.txt
	
	if ($errorlist.Count -gt 0) {
		Write-Host 'Внимание: в процессе установки в логе было зафиксировано $($errorlist.Count) ошибок. Убедитесь, что это не повлияет на работу системы.' -ForegroundColor Red
	}
	Write-Host
	
	# устанавливаем Git
	if (-Not [System.IO.File]::Exists("C:\Program Files\Git\cmd\git.exe")) {
		Write-Host 'Если вы хотите использовать внутренний Jenkins для запуска сканирования и в качестве источника будет git-репозиторий вашей организации, требуется установить Git for Windows.' -ForegroundColor Yellow
		Write-Host 'Установить Git for Windows? (y/n): ' -ForegroundColor Yellow -NoNewline
		$choice = Read-Host
		if ($choice -eq 'y') {
			Write-Host 'Устанавливаю Git...' -ForegroundColor Yellow
			$proc = Start-Process (Get-Current-Version-Path $PSScriptRoot "Git*.exe") -ArgumentList "/VERYSILENT" -passthru
			Handle-Install-Result "Git for Windows" $proc $step $false
			if ([System.IO.File]::Exists("C:\Program Files\Git\etc\gitconfig")) {
				Write-Host 'Обновляю конфигурацию Git...' -ForegroundColor Yellow
				copy config\gitconfig "C:\Program Files\Git\etc\gitconfig" 2>&1 | Out-File -Append logs\install.log
				Write-Host 'Перезапускаю Jenkins...' -ForegroundColor Yellow
				net stop Jenkins.Agent | Out-File -Append logs\install.log
				net stop Jenkins | Out-File -Append logs\install.log
				net start Jenkins | Out-File -Append logs\install.log
				Start-Sleep 5
				net start Jenkins.Agent | Out-File -Append logs\install.log
				Write-Host 'Установка Git завершена.' -ForegroundColor Yellow
			}
		}
	}
}
