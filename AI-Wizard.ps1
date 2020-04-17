#Requires -RunAsAdministrator

# Инсталлятор AI Enterprise и его окружения
# версия 0.2 от 17.04.2020

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
	if ([System.IO.File]::Exists($filename)) {
		return $filename
	}
	else {
		Write-Host "Ошибка: Файл $($mask) не найден в каталоге $($path)." -ForegroundColor Red
		Exit
	}
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
	if ($passed) {
		return $passed
	}
	else {
		Write-Host 'Ошибка: Пожалуйста, обновите версию Net Framework до 4.7.2 или выше, а затем перезапустите скрипт.' -ForegroundColor Red
		Write-Host 'Запускаю установщик обновления Net Framework...' -ForegroundColor Yellow
		start ndp48-x86-x64-allos-enu.exe
		Exit
	}
}


date | Out-File -Append logs\install.log
$myFQDN = ((Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain).ToLower()
$domain = ((Get-WmiObject win32_computersystem).Domain).ToLower()
$step = $args[0]

# проверяем что пререквизиты установки выполнены
if ($step -eq $null) {
	Write-Host 'Данный скрипт поможет вам установить Application Inspector Enterprise Edition. Если в процессе установки у вас возникнут ошибки, либо придётся перезагрузить компьютер, вы можете продолжить установку с последнего шага, указав номер этого шага в качестве параметра скрипта, например:' -ForegroundColor Yellow
	Write-Host '.\AI-Wizard.ps1 5' -ForegroundColor Yellow
	Write-Host 'Таким образом установка продолжится с шага 5.' -ForegroundColor Yellow
	Write-Host
	Write-Host '---ШАГ 1---' -ForegroundColor Green
	Write-Host 'Проверяю пререквизиты установки...' -ForegroundColor Yellow
	# проверяем что машина в домене
	if ((Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain) {
		# проверяем что пользователь доменный
		if ($env:ComputerName -ne $env:UserDomain) {
			# проверяем переменную %HOMEDRIVE%
			if ($env:HOMEDRIVE -eq "C:") {
				# проверяем версию powershell
				$psver = Get-Host | Select-Object Version
				$psver.version | Out-File -Append logs\install.log
				if ($psver.version.Major -ge 5) {
					# проверяем версию NetFramework
					if (Check-NetFramework-Version) {
						Write-Host 'Проверки пройдены успешно.' -ForegroundColor Yellow
						Get-AIHome
						# копируем утилиты для установки
						if (-Not (Test-Path C:\TOOLS)) {
							Write-Host 'Создаю каталог C:\TOOLS и копирую туда необходимые компоненты для установки...' -ForegroundColor Yellow
							mkdir -p C:\TOOLS\BOOT-INF\classes | Out-File -Append logs\install.log
							xcopy jdk1.8 C:\TOOLS\jdk1.8\ /E /Y | Out-File -Append logs\install.log
							xcopy openssl C:\TOOLS\openssl\ /E /Y | Out-File -Append logs\install.log
							# обновляем Path
							[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\TOOLS\openssl\bin;C:\TOOLS\jdk1.8\bin", "Machine")		
							# обновляем знания текущей сессии Powershell о Path
							$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
							xcopy certs C:\TOOLS\certs\ /E /Y | Out-File -Append logs\install.log
							copy ptai-integration-service-0.1-spring-boot.jar C:\TOOLS\ptai-integration-service-0.1-spring-boot.jar
							copy ptai-cli-plugin-0.1-jar-with-dependencies.jar C:\TOOLS\ptai-cli-plugin-0.1.jar
							copy config\application.yml C:\TOOLS\BOOT-INF\classes\application.yml
							copy config\bootstrap.yml C:\TOOLS\BOOT-INF\classes\bootstrap.yml
							copy agent.jar C:\TOOLS\agent.jar
							copy plugins\ptai-jenkins-plugin.hpi C:\TOOLS\ptai-jenkins-plugin.hpi
							copy config\readme.txt C:\TOOLS\readme.txt
							copy config\run-service.bat C:\TOOLS\run-service.bat
							# выключаем окно первого запуска IE чтобы работал Invoke-WebRequest
							Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main" -Name "DisableFirstRunCustomize" -Value 2
						}
						$step = 2
					}
				}
				else {
					Write-Host 'Ошибка: Пожалуйста, обновите версию Powershell до 5-ой или выше, а затем перезапустите скрипт.' -ForegroundColor Red
					Write-Host 'Запускаю установщик обновления Powershell...' -ForegroundColor Yellow
					start powershell_5-1_Win8.1AndW2K12R2-KB3191564-x64.msu
					Check-NetFramework-Version
					Exit
				}
			}
			else {
				Write-Host 'Ошибка: Пожалуйста, измените значение глобальной переменной %HOMEDRIVE% на диск C:.' -ForegroundColor Red
				Exit
			}			
		}
		else {
			Write-Host 'Ошибка: Пожалуйста, войдите под доменной учётной записью с правами локального администратора.' -ForegroundColor Red
			Exit
		}
	}
	else {
		Write-Host 'Ошибка: Пожалуйста, введите компьютер в домен.' -ForegroundColor Red
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
	if ([System.IO.File]::Exists("C:\TOOLS\certs\INT\out\01\private.jks")) {
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
		Write-Host 'Конфигурирую утилиту для выпуска сертификатов...' -ForegroundColor Yellow
		((Get-Content -path C:\TOOLS\certs\conf\root\ca.conf -Raw) -replace 'test.com',$domain) | Set-Content -Path C:\TOOLS\certs\conf\root\ca.conf
		((Get-Content -path C:\TOOLS\certs\conf\int\ssl.server.conf -Raw) -replace 'test.com',$domain) | Set-Content -Path C:\TOOLS\certs\conf\int\ssl.server.conf
		((Get-Content -path C:\TOOLS\certs\conf\int\ca.conf -Raw) -replace 'test.com',$domain) | Set-Content -Path C:\TOOLS\certs\conf\int\ca.conf
		((Get-Content -path C:\TOOLS\certs\conf\int\ssl.client.conf -Raw) -replace 'test.com',$domain) | Set-Content -Path C:\TOOLS\certs\conf\int\ssl.client.conf
		Write-Host 'Запускаю процедуру генерации самоподписанных сертификатов...' -ForegroundColor Yellow
		Set-Location -Path C:\TOOLS\certs\src
		Invoke-expression -Command C:\TOOLS\certs\src\ROOT.ps1 2>&1 | Out-File -Append "C:\TOOLS\certs\install.log"
		Set-Location -Path $PSScriptRoot
		# проверяем что сертификаты сгенерировались
		if ([System.IO.File]::Exists("C:\TOOLS\certs\INT\out\01\private.jks")) {
			# добавляем серты в cacerts java
			keytool -importkeystore -noprompt -srckeystore C:\TOOLS\certs\INT\out\01\private.jks -srcstorepass P@ssw0rd -destkeystore C:\TOOLS\jdk1.8\jre\lib\security\cacerts -deststorepass changeit 2>&1 | Out-File -Append "C:\TOOLS\certs\install.log"
			copy C:\TOOLS\certs\INT\out\01\ca.chain.pem.crt C:\TOOLS\server-cert.txt
			Write-Host 'Сертификаты были сгенерированы успешно и сохранены в C:\TOOLS\certs\INT\out. Пароль: P@ssw0rd' -ForegroundColor Yellow
			Write-Host 'Импортирую сертификаты в хранилище Windows...' -ForegroundColor Yellow
			Import-Certificate -FilePath "C:\TOOLS\certs\ROOT\certs\RootCA.pem.crt" -CertStoreLocation Cert:\LocalMachine\Root | Out-File -Append logs\install.log
			Import-Certificate -FilePath "C:\TOOLS\certs\INT\certs\IntermediateCA.pem.crt" -CertStoreLocation Cert:\LocalMachine\CA | Out-File -Append logs\install.log
		}
		else {
			Write-Host 'Ошибка: Сертификаты не созданы. Логи записаны в C:\TOOLS\certs\install.log. Пожалуйста, устраните ошибку и перезапустите установку с шага 3.' -ForegroundColor Red
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
		# проверяем наличие пользователя в домене
		do {
			Write-Host "Проверяю связь с домен контроллером..." -ForegroundColor Yellow
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
		
		Write-Host 'Пожалуйста, следуйте указаниям установщика AI Server.' -ForegroundColor Yellow
		Write-Host 'Данные для установки: ' -ForegroundColor Yellow
		if ($domainfound -and $domain -ne ((Get-WmiObject win32_computersystem).Domain).ToLower()) {
			Write-Host "Важно: при установке укажите, пожалуйста, домен в таком виде: $($domain)" -ForegroundColor Cyan
		}
		else {
			Write-Host "Домен: "((Get-WmiObject win32_computersystem).Domain).ToLower() -ForegroundColor Yellow
		}
		Write-Host 'Расположение сертификата: C:\TOOLS\certs\INT\out\00\ssl.server.brief.pfx' -ForegroundColor Yellow
		Write-Host 'Пароль от сертификата: P@ssw0rd' -ForegroundColor Yellow
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
			$DBCmdup.CommandText = "UPDATE `"GlobalMemberEntity`" SET `"Sid`" = '$sid' WHERE `"Id`" = 1"
			$DBCmdup.ExecuteReader()
			$DBConn.Close()
		}
	}
	# проверяем наличие служб
	try {
		$AIServiceStatus = Get-Service AI.*,Consul,RabbitMQ,PostgreSQL -ErrorAction Stop
	}
	catch {
		Write-Host 'Ошибка проверки служб:'$_ -ForegroundColor Red
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
		Get-AIHome
		Write-Host 'Пожалуйста, следуйте указаниям установщика AI Agent.' -ForegroundColor Yellow
		Write-Host 'Данные для установки: ' -ForegroundColor Yellow
		Write-Host 'Расположение сертификата: C:\TOOLS\certs\INT\out\01\ssl.client.brief.pfx' -ForegroundColor Yellow
		Write-Host 'Пароль от сертификата: P@ssw0rd' -ForegroundColor Yellow
		Write-Host "Адрес сервера: https://$($myFQDN)" -ForegroundColor Yellow
		$proc = Start-Process (Get-Current-Version-Path "$($global:AIHOME)\aic" "AIE.Agent*.exe") -passthru
		Wait-Process $proc.Id
		# проверяем что AI Agent установлен
		if (-Not [System.IO.File]::Exists("C:\Program Files (x86)\Positive Technologies\Application Inspector Agent\aic.exe")) {
			Write-Host 'Ошибка: AI Agent не установлен. Пожалуйста, выполните установку AI Agent и продолжите установку с шага 6.' -ForegroundColor Red
			Exit
		}
	}
	$step = 6
}

# конфигурируем интеграционный сервис в консуле
if ($step -eq 6) {
	Write-Host '---ШАГ 6---' -ForegroundColor Green
	# проверяем что этот шаг уже запускался
	if ([System.IO.File]::Exists("C:\TOOLS\consultoken.txt")) {
		Write-Host 'Этот шаг уже был выполнен, переходим к следующему.' -ForegroundColor Yellow
	}
	else {
		Write-Host 'Прописываю настройки интеграционного сервиса в Consul...' -ForegroundColor Yellow
		Invoke-expression -Command $PSScriptRoot\integrationServiceConsulPatch.ps1 -ErrorAction Stop
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
			[bool] $Chromestatus = Get-Content "$($PSScriptRoot)\logs\chrome.log" | Select-String "Installation failed"
			if ($Chromestatus) {
				Write-Host 'Ошибка: Google Chrome не установлен, логи скопированы в папку logs. Пожалуйста, установите его вручную.' -ForegroundColor Red
			}
		}
		# Ставим Jenkins в фоновом режиме
		Write-Host 'Устанавливаю Jenkins...' -ForegroundColor Yellow
		$proc = Start-Process msiexec -ArgumentList "/i $(Get-Current-Version-Path $PSScriptRoot "jenkins*.msi") /quiet /l*v `"$($PSScriptRoot)\logs\jenkins.log`"" -passthru
		Wait-Process $proc.Id
		[bool] $Jstatus = Get-Content "$($PSScriptRoot)\logs\jenkins.log" | Select-String "Installation failed"
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
		Write-Host 'Ошибка проверки службы Jenkins:'$_ -ForegroundColor Red
		Write-Host 'Пожалуйста, устраните ошибку и продолжите установку с шага 8.' -ForegroundColor Red
		Exit
	}
	if ($JenkinsService.Status -ne 'Running') {
		do {
			xcopy "C:\Program Files (x86)\Jenkins\jenkins.err.log" logs\jenkins.err.log /Y | Out-File -Append logs\install.log		
			Write-Host 'Ошибка: Служба Jenkins не запущена. Логи скопированы в папку logs. Пожалуйста, поднимите службу Jenkins и нажмите Enter для продолжения установки: ' -ForegroundColor Red -NoNewline
			Read-Host
			$JenkinsService = Get-Service Jenkins -ErrorAction SilentlyContinue
		}
		while ($JenkinsService.Status -ne 'Running')
	}
	$step = 8
}

# конфигурируем Jenkins
if ($step -eq 8) {
	Write-Host '---ШАГ 8---' -ForegroundColor Green
	# проверяем что плагины Jenkins уже установлены
	if ([System.IO.File]::Exists("C:\TOOLS\jenkinstoken.txt")) {
		Write-Host 'Этот шаг уже был выполнен, переходим к следующему.' -ForegroundColor Yellow
	}
	else {
		Write-Host 'Настраиваю Jenkins...' -ForegroundColor Yellow 
		Write-Host 'Копирую плагины...' -ForegroundColor Yellow
		xcopy plugins "C:\Program Files (x86)\Jenkins\plugins\" /E /Y | Out-File -Append logs\install.log
		Invoke-expression -Command $PSScriptRoot\configureJenkins.ps1 -ErrorAction Stop
		if (-Not [System.IO.File]::Exists("C:\TOOLS\jenkinstoken.txt")) {
			Write-Host 'Ошибка: токен для доступа к Jenkins не сформирован. Пожалуйста, устраните ошибку и перезапустите установку с шага 8.' -ForegroundColor Red
			Exit
		}
	}
	$step = 9
}

# конфигурируем интеграционный сервис
if ($step -eq 9) {
	Write-Host '---ШАГ 9---' -ForegroundColor Green
	Write-Host 'Патчу интеграционный сервис...' -ForegroundColor Yellow
	Set-Location -Path C:\TOOLS
	# подчищаем временные файлы на случай если раньше этот шаг уже запускался
	Get-ChildItem -Path 'C:\TOOLS' *.tmp | foreach { Remove-Item -Path $_.FullName }
	jar uf ptai-integration-service-0.1-spring-boot.jar BOOT-INF\classes\
	Write-Host 'Запускаю интеграционный сервис...' -ForegroundColor Yellow
	start C:\TOOLS\run-service.bat
	$timer = 0
	do {
		Start-Sleep 1
		$timer++
		if ([System.IO.File]::Exists("C:\TOOLS\admin")) {
			[bool] $pluginoutput = 1
		}
		elseif ($timer -eq 80) {
			[bool] $pluginoutput = 0
		}
	}
	while ($pluginoutput -eq $null)
	if (-Not $pluginoutput) {
		Write-Host 'Интеграционный сервис не смог запуститься. Пожалуйста, исправьте ошибку и запустите его вручную (C:\TOOLS\run-service.bat), после чего продолжите установку с шага 10.' -ForegroundColor Red
		Exit
	}
	$step = 10
}

# Продолжаем патчить Jenkins
if ($step -eq 10) {
	Write-Host '---ШАГ 10---' -ForegroundColor Green
	Write-Host 'Продолжаю настройку Jenkins...' -ForegroundColor Yellow 
	Invoke-expression -Command "$($PSScriptRoot)\configureJenkins.ps1 2" -ErrorAction Stop
	if (-Not [System.IO.File]::Exists("C:\TOOLS\run-agent.bat")) {
		Write-Host 'Ошибка: данные для запуска агента Jenkins не найдены.' -ForegroundColor Red
		Exit
	}
	Write-Host 'Запускаю агента Jenkins...' -ForegroundColor Yellow	
	start C:\TOOLS\run-agent.bat
	# заменяем ключевые значения в readme.txt
	$adminpwd = Get-Content -Path "C:\TOOLS\admin"
	$readme = Get-Content -Path C:\TOOLS\readme.txt | Out-String
	$readme = $readme -ireplace '%myFQDN%',"$myFQDN"
	$readme -ireplace '%adminpwd%',"$adminpwd" | Set-Content -Path C:\TOOLS\readme.txt
	# подчищаем временные файлы
	Get-ChildItem -Path 'C:\TOOLS' *.tmp | foreach { Remove-Item -Path $_.FullName }
	# добавляем каталогу права на запись для пользователей чтобы не было проблем при ручном запуске скриптов
	$ACL = Get-Acl "C:\TOOLS"
	$ACL.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule([System.Security.Principal.NTAccount]"users","fullcontrol", "ContainerInherit, ObjectInherit", "None", "Allow")))
	Set-Acl "C:\TOOLS" $ACL
	# помещаем ссылки на скрипт в автозапуск текущего пользователя
	Write-Host 'Добавляю символические ссылки в автозапуск системы...' -ForegroundColor Yellow
	New-Item -Path $env:APPDATA"\Microsoft\Windows\Start Menu\Programs\Startup\run-service.bat" -ItemType SymbolicLink -Value C:\TOOLS\run-service.bat | Out-File -Append logs\install.log
	New-Item -Path $env:APPDATA"\Microsoft\Windows\Start Menu\Programs\Startup\run-agent.bat" -ItemType SymbolicLink -Value C:\TOOLS\run-agent.bat | Out-File -Append logs\install.log
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
