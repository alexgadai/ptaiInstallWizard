# Инсталлятор AI Enterprise и его окружения
# Настройка Jenkins
# версия 0.1 от 13.04.2020

# установить заголовок для аутентификации в Jenkins
function Set-Auth-Header($username, $password) {
	# The header is the username and password concatenated together
	$pair = "$($username):$($password)"
	# The combined credentials are converted to Base 64
	$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
	# The base 64 credentials are then prefixed with "Basic"
	$basicAuthValue = "Basic $encodedCreds"
	# This is passed in the "Authorization" header
	$global:Headers = @{Authorization = $basicAuthValue}
}

# выключить IE Enhanced Security Configuration
function Disable-InternetExplorerESC {
    Write-Host "Временно отключаю IE Enhanced Security Configuration..." -ForegroundColor Yellow
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
    Stop-Process -Name Explorer
}

# включить IE Enhanced Security Configuration
function Enable-InternetExplorerESC {
    Write-Host "Включаю обратно IE Enhanced Security Configuration..." -ForegroundColor Yellow
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 1
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 1
    Stop-Process -Name Explorer
}

# запустить Jenkins и дождаться пока он поднимется
function Start-Jenkins($url, $header) {
	net start Jenkins | Out-File -Append logs\install.log
	# ждём пока сервис поднимется и (потенциально) упадёт
	Start-Sleep 10
	# проверяем состояние службы Jenkins
	$JenkinsServiceStatus = Get-Service Jenkins -ErrorAction Stop
	if ($JenkinsServiceStatus.Status -ne 'Running') {
		Write-Host 'Ошибка: Служба Jenkins не запущена. Логи скопированы в папку logs. Пожалуйста устраните ошибку и перезапустите установку с шага 7.' -ForegroundColor Red
		copy "C:\Program Files (x86)\Jenkins\jenkins.err.log" logs\jenkins.err.log | Out-File -Append logs\install.log	
		Exit
	}
	# проверяем что Jenkins реагирует на запросы
	$timer = 0
	do {
		try {
			[bool] $notready = 0
			Invoke-WebRequest -Uri $url -Headers $header 2>&1 | Out-File -Append logs\install.log
		}
		catch {
			[bool] $notready = 1
			Write-Host "Ожидание старта Jenkins..." -ForegroundColor Yellow
			$_ | Out-File -Append logs\install.log
			Start-Sleep 3
		}
		$timer++
		if ($timer -eq 5) {
			Write-Host "Ошибка: Jenkins отвечает ошибкой на запросы к $($url). Логи скопированы в папку logs." -ForegroundColor Red
			#Exit
		}
	}
	while ($notready)
}

$step = $args[0]
Set-Location -Path $PSScriptRoot
$myFQDN=((Get-WmiObject win32_computersystem).DNSHostName+"."+(Get-WmiObject win32_computersystem).Domain).ToLower()
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

if ($step -eq $null) {
	# Установка Jenkins
	# Выключаем IE ESC чтобы он не блокировал наши запросы к Jenkins
	Disable-InternetExplorerESC
	Start-Sleep 3
	Write-Host 'Перевожу Jenkins на https...' -ForegroundColor Yellow
	# проверяем что Jenkins сформировал пароль администратора
	$timer = 0
	while (-Not [System.IO.File]::Exists("C:\Program Files (x86)\Jenkins\secrets\initialAdminPassword")) {
		# разбудить Jenkins
		try {
			Invoke-WebRequest -Uri "http://localhost:8080/login?from=%2F" 2>&1 | Out-File -Append logs\install.log
		}
		catch {
			Write-Host "Ожидание старта Jenkins..." -ForegroundColor Yellow
			$_ | Out-File -Append logs\install.log			
			Start-Sleep 3
		}
		$timer++
		if ($timer -eq 5) {
			Write-Host "Ошибка: Jenkins не сформировал пароль администратора: файл C:\Program Files (x86)\Jenkins\secrets\initialAdminPassword не найден. Логи скопированы в папку logs." -ForegroundColor Red
			Exit
		}
	}
	
	# останавливаем сервис и обновляем конфигурацию
	net stop Jenkins | Out-File -Append logs\install.log
	copy config\jenkins.xml "C:\Program Files (x86)\Jenkins\jenkins.xml"
	copy config\unsecure-config.xml "C:\Program Files (x86)\Jenkins\config.xml"
	xcopy nodes "C:\Program Files (x86)\Jenkins\nodes\" /E /Y | Out-File -Append logs\install.log
	copy C:\TOOLS\certs\INT\out\01\private.jks "C:\Program Files (x86)\Jenkins\secrets\private.jks"
	copy config\jenkins.model.JenkinsLocationConfiguration.xml "C:\Program Files (x86)\Jenkins\jenkins.model.JenkinsLocationConfiguration.xml"
	copy config\com.ptsecurity.appsec.ai.ee.utils.ci.integration.plugin.jenkins.Plugin.xml "C:\Program Files (x86)\Jenkins\com.ptsecurity.appsec.ai.ee.utils.ci.integration.plugin.jenkins.Plugin.xml"
	# jenkins location patch
	$c_jenkins_location = Get-Content -path 'C:\Program Files (x86)\Jenkins\jenkins.model.JenkinsLocationConfiguration.xml' | Out-String
	$c_jenkins_location -ireplace '(<jenkinsUrl>)(.*)',"`$1https://$myFQDN`:8080/</jenkinsUrl>" | Set-Content -Path 'C:\Program Files (x86)\Jenkins\jenkins.model.JenkinsLocationConfiguration.xml'
	Start-Jenkins "https://$($myFQDN):8080/"
	
	# меняем пароль администратора
	Write-Host 'Обновляю пароль администратора...' -ForegroundColor Yellow
	# берём пароль задаваемый при первичной установке
	$defaultpass = Get-Content -Path "C:\Program Files (x86)\Jenkins\secrets\initialAdminPassword" | Out-String
	Set-Auth-Header "admin" $defaultpass.Trim()
	# меняем на P@ssw0rd для admin
	Invoke-WebRequest -Uri "https://$($myFQDN):8080/user/admin/configSubmit" `
	-Method "POST" `
	-Headers $global:Headers `
	-ContentType "application/x-www-form-urlencoded" `
	-Body "_.fullName=admin&_.description=&_.primaryViewName=&user.password=P%40ssw0rd&user.password2=P%40ssw0rd&_.authorizedKeys=&insensitiveSearch=on&core%3Aapply=&json=%7B%22fullName%22%3A+%22admin%22%2C+%22description%22%3A+%22%22%2C+%22userProperty2%22%3A+%7B%22primaryViewName%22%3A+%22%22%7D%2C+%22userProperty4%22%3A+%7B%22password%22%3A+%22P%40ssw0rd%22%2C+%22%24redact%22%3A+%5B%22password%22%2C+%22password2%22%5D%2C+%22password2%22%3A+%22P%40ssw0rd%22%7D%2C+%22userProperty5%22%3A+%7B%22authorizedKeys%22%3A+%22%22%7D%2C+%22userProperty7%22%3A+%7B%22insensitiveSearch%22%3A+true%7D%2C+%22core%3Aapply%22%3A+%22%22%7D&Submit=%D0%A1%D0%BE%D1%85%D1%80%D0%B0%D0%BD%D0%B8%D1%82%D1%8C" | Out-File -Append logs\install.log
	Write-Host 'Готово! Логин: admin, пароль: P@ssw0rd' -ForegroundColor Yellow
	
	# создаём пользователя svc_ptai с паролем P@ssw0rd
	Write-Host 'Завожу технического пользователя для AI...' -ForegroundColor Yellow
	Invoke-WebRequest -Uri "https://$($myFQDN):8080/securityRealm/createAccountByAdmin" `
	-Method "POST" `
	-ContentType "application/x-www-form-urlencoded" `
	-Body "username=svc_ptai&password1=P%40ssw0rd&password2=P%40ssw0rd&fullname=svc_ptai&email=svc_ptai%40mail.ru&json=%7B%22username%22%3A+%22svc_ptai%22%2C+%22password1%22%3A+%22P%40ssw0rd%22%2C+%22%24redact%22%3A+%5B%22password1%22%2C+%22password2%22%5D%2C+%22password2%22%3A+%22P%40ssw0rd%22%2C+%22fullname%22%3A+%22svc_ptai%22%2C+%22email%22%3A+%22svc_ptai%40mail.ru%22%7D&Submit=%D0%A1%D0%BE%D0%B7%D0%B4%D0%B0%D1%82%D1%8C+%D0%BF%D0%BE%D0%BB%D1%8C%D0%B7%D0%BE%D0%B2%D0%B0%D1%82%D0%B5%D0%BB%D1%8F" | Out-File -Append logs\install.log
	
	# создаём токен для пользователя svc_ptai
	Set-Auth-Header "svc_ptai" "P@ssw0rd"
	try {
		$crtoken = Invoke-WebRequest -Uri "https://$($myFQDN):8080/user/svc_ptai/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken" `
		-Headers $global:Headers `
		-Method "POST" `
		-ContentType "application/x-www-form-urlencoded" `
		-Body "newTokenName=ptai"
	}
	catch {
		Write-Host 'Ошибка: Операция по созданию технического пользователя завершилась неудачей. Логи скопированы в папку logs. Пожалуйста, устраните ошибку, удалите Jenkins и перезапустите установку с шага 7.' -ForegroundColor Red
		$_ | Out-File -Append logs\install.log
		Exit
	}
	$tmp = $crtoken.Content | ConvertFrom-Json
	$token = $tmp.data.tokenValue
	if ($token -ne $null) {
		Write-Host 'Готово! Логин: svc_ptai, пароль: P@ssw0rd' -ForegroundColor Yellow
		# патчим application.yml
		Write-Host 'Обновляю конфигурацию application.yml...' -ForegroundColor Yellow
		$patchAPP = Get-Content -Path "C:\TOOLS\BOOT-INF\classes\application.yml" | Out-String
		$patchAPP = $patchAPP -replace '(ci-api-token\:)(.*)',"`$1 $token"
		$patchAPP = $patchAPP -ireplace '(ci-url: https:\/\/)(.*)(:8080)',"`$1$myFQDN`$3"
		$patchAPP = $patchAPP -ireplace '(ptai-url: https:\/\/)(.*)(:443)',"`$1$myFQDN`$3" | Set-Content -Path "C:\TOOLS\BOOT-INF\classes\application.yml"
		echo $token > C:\TOOLS\jenkinstoken.txt
	}
	else {
		Write-Host 'Ошибка: Операция по созданию технического пользователя завершилась неудачей. Логи скопированы в папку logs. Пожалуйста, устраните ошибку, удалите Jenkins и перезапустите установку с шага 7.' -ForegroundColor Red
		Exit
	}
}

# продолжение установки
if ($step -eq 2) {
	$adminpwd = Get-Content -Path "C:\TOOLS\admin"
	# создаём папку PTAI
	Write-Host 'Конфигурирую pipeline...' -ForegroundColor Yellow
	Invoke-WebRequest -Uri "https://$($myFQDN):8080/view/all/createItem" `
	-Method "POST" `
	-ContentType "application/x-www-form-urlencoded" `
	-Body "name=PTAI&mode=com.cloudbees.hudson.plugins.folder.Folder&json=%7B%22name%22%3A+%22PTAI%22%2C+%22mode%22%3A+%22com.cloudbees.hudson.plugins.folder.Folder%22%7D" | Out-File -Append logs\install.log
	
	# создаём пайплайн SAST
	Invoke-WebRequest -Uri "https://$($myFQDN):8080/job/PTAI/createItem" `
	-Method "POST" `
	-ContentType "application/x-www-form-urlencoded" `
	-Body "name=SAST&mode=org.jenkinsci.plugins.workflow.job.WorkflowJob&from=&json=%7B%22name%22%3A+%22SAST%22%2C+%22mode%22%3A+%22org.jenkinsci.plugins.workflow.job.WorkflowJob%22%2C+%22from%22%3A+%22%22%7D" | Out-File -Append logs\install.log
	
	# редактируем настройки пайплайна
	Invoke-WebRequest -Uri "https://$($myFQDN):8080/job/PTAI/job/SAST/configSubmit" `
	-Method "POST" `
	-ContentType "application/x-www-form-urlencoded" `
	-Body "description=&stapler-class-bag=true&specified=on&hint=MAX_SURVIVABILITY&_.buildCount=1&_.count=1&_.durationName=hour&_.daysToKeepStr=&_.numToKeepStr=&_.artifactDaysToKeepStr=&_.artifactNumToKeepStr=&stapler-class=hudson.tasks.LogRotator&%24class=hudson.tasks.LogRotator&specified=on&parameter.name=PTAI_PROJECT_NAME&parameter.defaultValue=&parameter.description=&stapler-class=hudson.model.StringParameterDefinition&%24class=hudson.model.StringParameterDefinition&parameter.name=PTAI_NODE_NAME&parameter.defaultValue=PTAI&parameter.description=&stapler-class=hudson.model.StringParameterDefinition&%24class=hudson.model.StringParameterDefinition&parameter.name=PTAI_SETTINGS_JSON&parameter.defaultValue=&parameter.description=&stapler-class=hudson.model.StringParameterDefinition&%24class=hudson.model.StringParameterDefinition&parameter.name=PTAI_POLICY_JSON&parameter.defaultValue=&parameter.description=&stapler-class=hudson.model.StringParameterDefinition&%24class=hudson.model.StringParameterDefinition&stapler-class-bag=true&_.upstreamProjects=&ReverseBuildTrigger.threshold=SUCCESS&_.spec=&_.scmpoll_spec=&quiet_period=5&authToken=&_.displayNameOrNull=&_.script=def+aicPath+%3D+%27C%3A%5C%5CProgram+Files+%28x86%29%5C%5CPositive+Technologies%5C%5CApplication+Inspector+Agent%5C%5Caic.exe%27%0D%0Anode%28%22%24%7BPTAI_NODE_NAME%7D%22%29+%7B%0D%0A++++def+retStatus+%3D+0%3B%0D%0A%0D%0A++++stage%28%27SAST%27%29+%7B%0D%0A++++++++if+%28isUnix%28%29%29+%7B%0D%0A++++++++++++currentBuild.result+%3D+%22UNSTABLE%22%3B%0D%0A++++++++++++println+%27PT+AI+must+be+deployed+on+a+Windows+host%27%3B%0D%0A++++++++++++return%3B%0D%0A++++++++%7D%0D%0A++++++++cleanWs%28%29%3B%0D%0A%0D%0A++++++++batchScript+%3D+%22%5C%22%24%7BaicPath%7D%5C%22+%22%3B%0D%0A++++++++batchScript+%2B%3D+%22--project-name+%5C%22%24%7BPTAI_PROJECT_NAME%7D%5C%22+%22%3B%0D%0A++++++++batchScript+%2B%3D+%22--scan-target+%5C%22%24%7BWORKSPACE%7D%5C%5CSCAN%5C%22+%22%0D%0A++++++++batchScript+%2B%3D+%22--reports+%5C%22HTML%7CJSON%5C%22+%22%0D%0A++++++++batchScript+%2B%3D+%22--reports-folder+%5C%22%24%7BWORKSPACE%7D%5C%5CREPORTS%5C%22+%22%0D%0A++++++++batchScript+%2B%3D+%22--restore-sources+%22%0D%0A++++++++batchScript+%2B%3D+%22--sync+%22%0D%0A++++++++if+%28%22%24%7BPTAI_SETTINGS_JSON%7D%22%3F.trim%28%29%29+%7B%0D%0A++++++++++++writeFile+file%3A+%22%24%7BWORKSPACE%7D%5C%5CSETTINGS%5C%5Csettings.aiproj%22%2C+text%3A+%22%24%7BPTAI_SETTINGS_JSON%7D%22%0D%0A++++++++++++batchScript+%2B%3D+%22--project-settings-file+%5C%22%24%7BWORKSPACE%7D%5C%5CSETTINGS%5C%5Csettings.aiproj%5C%22+%22%0D%0A++++++++%7D%0D%0A%0D%0A++++++++if+%28%22%24%7BPTAI_POLICY_JSON%7D%22%3F.trim%28%29%29+%7B%0D%0A++++++++++++writeFile+file%3A+%22%24%7BWORKSPACE%7D%5C%5CSETTINGS%5C%5Cpolicy.json%22%2C+text%3A+%22%24%7BPTAI_POLICY_JSON%7D%22%0D%0A++++++++++++batchScript+%2B%3D+%22--policies-path+%5C%22%24%7BWORKSPACE%7D%5C%5CSETTINGS%5C%5Cpolicy.json%5C%22+%22%0D%0A++++++++%7D%0D%0A%0D%0A++++++++retStatus+%3D+bat%28script%3A+batchScript%2C+returnStatus%3A+true%29%3B%0D%0A%09%09writeFile+file%3A+%22%24%7BWORKSPACE%7D%5C%5CREPORTS%5C%5Cstatus.code%22%2C+text%3A+%22%24%7BretStatus%7D%22%0D%0A++++++++println+%22AI+return+status+%24%7BretStatus%7D%22%3B%0D%0A++++++++archiveArtifacts+%27REPORTS%2F*%27%3B%0D%0A%0D%0A++++++++if+%280+%3D%3D+retStatus%29+%7B%0D%0A++++++++++++currentBuild.result+%3D+%22SUCCESS%22%3B%0D%0A++++++++++++println+%27SAST+policy+assessment+OK%27%3B%0D%0A++++++++%7D+else+if+%2810+%3D%3D+retStatus%29+%7B%0D%0A++++++++++++currentBuild.result+%3D+%22FAILURE%22%3B%0D%0A++++++++++++println+%27SAST+policy+assessment+failed%27%3B%0D%0A++++++++%7D+else+if+%28-1+%3D%3D+retStatus%29+%7B%0D%0A++++++++++++currentBuild.result+%3D+%22UNSTABLE%22%3B%0D%0A++++++++++++println+%27Another+AI+instance+started+already%27%3B%0D%0A++++++++%7D+else+if+%282+%3D%3D+retStatus%29+%7B%0D%0A++++++++++++currentBuild.result+%3D+%22UNSTABLE%22%3B%0D%0A++++++++++++println+%27Scan+folder+not+found%27%3B%0D%0A++++++++%7D+else+if+%283+%3D%3D+retStatus%29+%7B%0D%0A++++++++++++currentBuild.result+%3D+%22UNSTABLE%22%3B%0D%0A++++++++++++println+%27AI+license+problem%27%3B%0D%0A++++++++%7D+else+if+%284+%3D%3D+retStatus%29+%7B%0D%0A++++++++++++currentBuild.result+%3D+%22UNSTABLE%22%3B%0D%0A++++++++++++println+%27Project+not+found%27%3B%0D%0A++++++++%7D+else+if+%285+%3D%3D+retStatus%29+%7B%0D%0A++++++++++++currentBuild.result+%3D+%22UNSTABLE%22%3B%0D%0A++++++++++++println+%27Project+settings+error%27%3B%0D%0A++++++++%7D+else+if+%286+%3D%3D+retStatus%29+%7B%0D%0A++++++++++++currentBuild.result+%3D+%22UNSTABLE%22%3B%0D%0A++++++++++++println+%27Minor+errors+during+scan%27%3B%0D%0A++++++++%7D+else+%7B%0D%0A++++++++++++currentBuild.result+%3D+%22FAILURE%22%3B%0D%0A++++++++++++println+%27Unknown+problem%27%3B%0D%0A++++++++%7D%0D%0A++++++++cleanWs%28%29%3B%0D%0A++++%7D%0D%0A%7D&stapler-class=org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition&%24class=org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition&stapler-class=org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition&%24class=org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition&core%3Aapply=&json=%7B%22description%22%3A+%22%22%2C+%22properties%22%3A+%7B%22stapler-class-bag%22%3A+%22true%22%2C+%22org-jenkinsci-plugins-workflow-job-properties-DisableConcurrentBuildsJobProperty%22%3A+%7B%22specified%22%3A+true%7D%2C+%22org-jenkinsci-plugins-workflow-job-properties-DisableResumeJobProperty%22%3A+%7B%22specified%22%3A+false%7D%2C+%22org-jenkinsci-plugins-workflow-job-properties-DurabilityHintJobProperty%22%3A+%7B%22specified%22%3A+false%2C+%22hint%22%3A+%22MAX_SURVIVABILITY%22%7D%2C+%22org-jenkinsci-plugins-pipeline-modeldefinition-properties-PreserveStashesJobProperty%22%3A+%7B%22specified%22%3A+false%2C+%22buildCount%22%3A+%221%22%7D%2C+%22jenkins-branch-RateLimitBranchProperty%24JobPropertyImpl%22%3A+%7B%7D%2C+%22jenkins-model-BuildDiscarderProperty%22%3A+%7B%22specified%22%3A+false%2C+%22%22%3A+%220%22%2C+%22strategy%22%3A+%7B%22daysToKeepStr%22%3A+%22%22%2C+%22numToKeepStr%22%3A+%22%22%2C+%22artifactDaysToKeepStr%22%3A+%22%22%2C+%22artifactNumToKeepStr%22%3A+%22%22%2C+%22stapler-class%22%3A+%22hudson.tasks.LogRotator%22%2C+%22%24class%22%3A+%22hudson.tasks.LogRotator%22%7D%7D%2C+%22hudson-model-ParametersDefinitionProperty%22%3A+%7B%22specified%22%3A+true%2C+%22parameterDefinitions%22%3A+%5B%7B%22name%22%3A+%22PTAI_PROJECT_NAME%22%2C+%22defaultValue%22%3A+%22%22%2C+%22description%22%3A+%22%22%2C+%22trim%22%3A+false%2C+%22stapler-class%22%3A+%22hudson.model.StringParameterDefinition%22%2C+%22%24class%22%3A+%22hudson.model.StringParameterDefinition%22%7D%2C+%7B%22name%22%3A+%22PTAI_NODE_NAME%22%2C+%22defaultValue%22%3A+%22PTAI%22%2C+%22description%22%3A+%22%22%2C+%22trim%22%3A+false%2C+%22stapler-class%22%3A+%22hudson.model.StringParameterDefinition%22%2C+%22%24class%22%3A+%22hudson.model.StringParameterDefinition%22%7D%2C+%7B%22name%22%3A+%22PTAI_SETTINGS_JSON%22%2C+%22defaultValue%22%3A+%22%22%2C+%22description%22%3A+%22%22%2C+%22trim%22%3A+false%2C+%22stapler-class%22%3A+%22hudson.model.StringParameterDefinition%22%2C+%22%24class%22%3A+%22hudson.model.StringParameterDefinition%22%7D%2C+%7B%22name%22%3A+%22PTAI_POLICY_JSON%22%2C+%22defaultValue%22%3A+%22%22%2C+%22description%22%3A+%22%22%2C+%22trim%22%3A+false%2C+%22stapler-class%22%3A+%22hudson.model.StringParameterDefinition%22%2C+%22%24class%22%3A+%22hudson.model.StringParameterDefinition%22%7D%5D%7D%2C+%22org-jenkinsci-plugins-workflow-job-properties-PipelineTriggersJobProperty%22%3A+%7B%22triggers%22%3A+%7B%22stapler-class-bag%22%3A+%22true%22%7D%7D%7D%2C+%22disable%22%3A+false%2C+%22hasCustomQuietPeriod%22%3A+false%2C+%22quiet_period%22%3A+%225%22%2C+%22displayNameOrNull%22%3A+%22%22%2C+%22%22%3A+%220%22%2C+%22definition%22%3A+%7B%22script%22%3A+%22def+aicPath+%3D+%27C%3A%5C%5C%5C%5CProgram+Files+%28x86%29%5C%5C%5C%5CPositive+Technologies%5C%5C%5C%5CApplication+Inspector+Agent%5C%5C%5C%5Caic.exe%27%5Cnnode%28%5C%22%24%7BPTAI_NODE_NAME%7D%5C%22%29+%7B%5Cn++++def+retStatus+%3D+0%3B%5Cn%5Cn++++stage%28%27SAST%27%29+%7B%5Cn++++++++if+%28isUnix%28%29%29+%7B%5Cn++++++++++++currentBuild.result+%3D+%5C%22UNSTABLE%5C%22%3B%5Cn++++++++++++println+%27PT+AI+must+be+deployed+on+a+Windows+host%27%3B%5Cn++++++++++++return%3B%5Cn++++++++%7D%5Cn++++++++cleanWs%28%29%3B%5Cn%5Cn++++++++batchScript+%3D+%5C%22%5C%5C%5C%22%24%7BaicPath%7D%5C%5C%5C%22+%5C%22%3B%5Cn++++++++batchScript+%2B%3D+%5C%22--project-name+%5C%5C%5C%22%24%7BPTAI_PROJECT_NAME%7D%5C%5C%5C%22+%5C%22%3B%5Cn++++++++batchScript+%2B%3D+%5C%22--scan-target+%5C%5C%5C%22%24%7BWORKSPACE%7D%5C%5C%5C%5CSCAN%5C%5C%5C%22+%5C%22%5Cn++++++++batchScript+%2B%3D+%5C%22--reports+%5C%5C%5C%22HTML%7CJSON%5C%5C%5C%22+%5C%22%5Cn++++++++batchScript+%2B%3D+%5C%22--reports-folder+%5C%5C%5C%22%24%7BWORKSPACE%7D%5C%5C%5C%5CREPORTS%5C%5C%5C%22+%5C%22%5Cn++++++++batchScript+%2B%3D+%5C%22--restore-sources+%5C%22%5Cn++++++++batchScript+%2B%3D+%5C%22--sync+%5C%22%5Cn++++++++if+%28%5C%22%24%7BPTAI_SETTINGS_JSON%7D%5C%22%3F.trim%28%29%29+%7B%5Cn++++++++++++writeFile+file%3A+%5C%22%24%7BWORKSPACE%7D%5C%5C%5C%5CSETTINGS%5C%5C%5C%5Csettings.aiproj%5C%22%2C+text%3A+%5C%22%24%7BPTAI_SETTINGS_JSON%7D%5C%22%5Cn++++++++++++batchScript+%2B%3D+%5C%22--project-settings-file+%5C%5C%5C%22%24%7BWORKSPACE%7D%5C%5C%5C%5CSETTINGS%5C%5C%5C%5Csettings.aiproj%5C%5C%5C%22+%5C%22%5Cn++++++++%7D%5Cn%5Cn++++++++if+%28%5C%22%24%7BPTAI_POLICY_JSON%7D%5C%22%3F.trim%28%29%29+%7B%5Cn++++++++++++writeFile+file%3A+%5C%22%24%7BWORKSPACE%7D%5C%5C%5C%5CSETTINGS%5C%5C%5C%5Cpolicy.json%5C%22%2C+text%3A+%5C%22%24%7BPTAI_POLICY_JSON%7D%5C%22%5Cn++++++++++++batchScript+%2B%3D+%5C%22--policies-path+%5C%5C%5C%22%24%7BWORKSPACE%7D%5C%5C%5C%5CSETTINGS%5C%5C%5C%5Cpolicy.json%5C%5C%5C%22+%5C%22%5Cn++++++++%7D%5Cn%5Cn++++++++retStatus+%3D+bat%28script%3A+batchScript%2C+returnStatus%3A+true%29%3B%5Cn%5Ct%5CtwriteFile+file%3A+%5C%22%24%7BWORKSPACE%7D%5C%5C%5C%5CREPORTS%5C%5C%5C%5Cstatus.code%5C%22%2C+text%3A+%5C%22%24%7BretStatus%7D%5C%22%5Cn++++++++println+%5C%22AI+return+status+%24%7BretStatus%7D%5C%22%3B%5Cn++++++++archiveArtifacts+%27REPORTS%2F*%27%3B%5Cn%5Cn++++++++if+%280+%3D%3D+retStatus%29+%7B%5Cn++++++++++++currentBuild.result+%3D+%5C%22SUCCESS%5C%22%3B%5Cn++++++++++++println+%27SAST+policy+assessment+OK%27%3B%5Cn++++++++%7D+else+if+%2810+%3D%3D+retStatus%29+%7B%5Cn++++++++++++currentBuild.result+%3D+%5C%22FAILURE%5C%22%3B%5Cn++++++++++++println+%27SAST+policy+assessment+failed%27%3B%5Cn++++++++%7D+else+if+%28-1+%3D%3D+retStatus%29+%7B%5Cn++++++++++++currentBuild.result+%3D+%5C%22UNSTABLE%5C%22%3B%5Cn++++++++++++println+%27Another+AI+instance+started+already%27%3B%5Cn++++++++%7D+else+if+%282+%3D%3D+retStatus%29+%7B%5Cn++++++++++++currentBuild.result+%3D+%5C%22UNSTABLE%5C%22%3B%5Cn++++++++++++println+%27Scan+folder+not+found%27%3B%5Cn++++++++%7D+else+if+%283+%3D%3D+retStatus%29+%7B%5Cn++++++++++++currentBuild.result+%3D+%5C%22UNSTABLE%5C%22%3B%5Cn++++++++++++println+%27AI+license+problem%27%3B%5Cn++++++++%7D+else+if+%284+%3D%3D+retStatus%29+%7B%5Cn++++++++++++currentBuild.result+%3D+%5C%22UNSTABLE%5C%22%3B%5Cn++++++++++++println+%27Project+not+found%27%3B%5Cn++++++++%7D+else+if+%285+%3D%3D+retStatus%29+%7B%5Cn++++++++++++currentBuild.result+%3D+%5C%22UNSTABLE%5C%22%3B%5Cn++++++++++++println+%27Project+settings+error%27%3B%5Cn++++++++%7D+else+if+%286+%3D%3D+retStatus%29+%7B%5Cn++++++++++++currentBuild.result+%3D+%5C%22UNSTABLE%5C%22%3B%5Cn++++++++++++println+%27Minor+errors+during+scan%27%3B%5Cn++++++++%7D+else+%7B%5Cn++++++++++++currentBuild.result+%3D+%5C%22FAILURE%5C%22%3B%5Cn++++++++++++println+%27Unknown+problem%27%3B%5Cn++++++++%7D%5Cn++++++++cleanWs%28%29%3B%5Cn++++%7D%5Cn%7D%22%2C+%22%22%3A+%5B%22try+sample+Pipeline...%22%2C+%22%5Cu0001%5Cu0001%22%5D%2C+%22sandbox%22%3A+false%2C+%22stapler-class%22%3A+%22org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition%22%2C+%22%24class%22%3A+%22org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition%22%7D%2C+%22core%3Aapply%22%3A+%22%22%7D&Submit=%D0%A1%D0%BE%D1%85%D1%80%D0%B0%D0%BD%D0%B8%D1%82%D1%8C" | Out-File -Append logs\install.log
	
	# добавляем креды для авторизации в сервисе
	Write-Host 'Настраиваю плагин...' -ForegroundColor Yellow
	Invoke-WebRequest -Uri "https://$($myFQDN):8080/descriptor/com.cloudbees.plugins.credentials.CredentialsSelectHelper/resolver/com.cloudbees.plugins.credentials.CredentialsSelectHelper`$SystemContextResolver/provider/com.cloudbees.plugins.credentials.SystemCredentialsProvider`$ProviderImpl/context/jenkins/addCredentials" `
	-Method "POST" `
	-ContentType "application/x-www-form-urlencoded" `
	-Body "_.domain=_&_.scope=GLOBAL&_.username=&_.password=&_.id=&_.description=&stapler-class=com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl&%24class=com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl&stapler-class=org.jenkinsci.plugins.docker.commons.credentials.DockerServerCredentials&%24class=org.jenkinsci.plugins.docker.commons.credentials.DockerServerCredentials&stapler-class=com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey&%24class=com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey&stapler-class=org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl&%24class=org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl&stapler-class=org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl&%24class=org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl&_.userName=admon&_.password=$($adminpwd)&_.serverCaCertificates=-----BEGIN+CERTIFICATE-----%0D%0AMIIFVDCCAzygAwIBAgIIYaQyGbkTSjEwDQYJKoZIhvcNAQELBQAwMjETMBEGA1UE%0D%0ACgwKRG9tYWluLk9SRzEbMBkGA1UEAwwSRG9tYWluLk9SRyBSb290IENBMB4XDTE5%0D%0AMDMwNzA4MjAzNFoXDTM5MDMwNzA4MjAzNFowOjETMBEGA1UECgwKRG9tYWluLk9S%0D%0ARzEjMCEGA1UEAwwaRG9tYWluLk9SRyBJbnRlcm1lZGlhdGUgQ0EwggIiMA0GCSqG%0D%0ASIb3DQEBAQUAA4ICDwAwggIKAoICAQCxEpZw1eGb%2Bfvp0iISDnIp6kP1mqfAPF1H%0D%0AquN6TVgGxpBvavYuOgQIFWjobniH09a4c5ma5qKd%2FCrC7iL2SpuRyJHZLD9PD8yO%0D%0AQpyEnELLNuMvhx%2BqEGI%2BOClJJWxj1P%2B0cvYRtS%2F9vq64ZnL46HItXmqnPUIIwwVH%0D%0AJ6aZloRbfHHVguQepT6izMzWr6zfvr4MjoTzAb4s5R0NsNB0KaUV%2Ffp3V7yVRmUq%0D%0Ao9EHfLFP%2BJy3QwAIfCB4PmkYbX9FDE6hicUFKu9x0w64Jb9on8J0mCfrl3cDYmyp%0D%0AxeAbkypjWHYkNgYav3IpKDJBE2o%2BbID8DJJr%2B53%2F62cKiHT9FqyR%2BDCuoMwc%2BH3P%0D%0A0HAhi4EgbrIgi8h1nibm0AgSTb9DX7GhOEUio48mfE%2FWhI%2F26tVDQ%2B%2Bud8K%2BHeXL%0D%0AWvpfU1UoaQ9ClG26gRDGGcqJMC%2Ft2y1zCMsjfw2lyZVvoquYVhOACqUgK4Wq9PVl%0D%0ApGCovywqhoW1I7e5nuCmH2vQJOQQacdrkkEOpQyS%2BR3nQK2UQofMJHsLHnY7p%2F1m%0D%0Az7M%2BvtsPIl1A0pQrGBPFa4P3ze0UXvsv4YmhplJrPdv%2FfqSySlvCp7dz0SAJ55ts%0D%0Awk%2FvoZL3Wu5MM4oFC%2B%2BJZYM0Za7oUTHz4G5iCJz6N9bkpHQpg7VXTiJm6JyZe2YG%0D%0AH1VTiwyjRQIDAQABo2YwZDAOBgNVHQ8BAf8EBAMCAQYwEgYDVR0TAQH%2FBAgwBgEB%0D%0A%2FwIBADAdBgNVHQ4EFgQUEbOON7jUO47uGxr0muy2xOh3vhQwHwYDVR0jBBgwFoAU%0D%0AygE1DVJ%2FLOL%2B2tlTF8fw8cSJcNwwDQYJKoZIhvcNAQELBQADggIBAKBYe1jGYwPo%0D%0A1Av%2FA7DkLQGbXOAvkLmkgYNoCC5%2BJ6AfCeaCu%2Fpzhzi4zlj9f081wz9wYr%2Fr4Ake%0D%0AVlnNOtzejKXLlbvocow842xEGb0z9YGh5pIgyvwvRe1y9rEy7CmmrCQwLGzlGAqK%0D%0A48bD6Y%2FxvT3WWdkxvCQoc%2F3S1WGpBdN6ZiS9VlprpEOl0j1r4ns9Hwm7CQjm95sE%0D%0A9sD%2FvPOSRdp%2Blzfx36gWOWX4r7FAkGSk3yHaRXIP1HKy4PhzZUmjMeIMvN7o86sj%0D%0Azt2MvfeUlU5FvmElBsuMraJ3MDiSaNAOg%2F13bRQBNUjsrLuKBDzWnvS41LdfMXEY%0D%0AedmnNyVflw4100lj7Oul1ovuJ6R1s6X3TFn%2FsRjwAAbVJDTUBop9quu9qHpnBpim%0D%0AqNch6fFTrgZSecRsXqbxPc4mNOv%2B4oz5mGkg%2FQTmq64nQHwPlULjqeEWqPcvrMPx%0D%0ASrJSxHqFxHgECr8uM51Gf2%2BONxvcEdZegRelyU1PMzc%2BctSt5J%2F%2F77h%2BrVYAoVq%2B%0D%0A7qX27UrXTALGQHI1v2tJuVMYIVJuxbzD6lstG8IFqOJPh6lAL%2FmW0WeaC%2F3ShV5D%0D%0AFFhyCIc59CbX9NOHQfItkAi2O8NrjYkoPrhwgKzJCFbB90jVixaMatOVUjdnl0gS%0D%0Aw3oG7pLjhMOWzB6mUoSVpk8QxJCH4pCA%0D%0A-----END+CERTIFICATE-----&_.id=&_.description=&stapler-class=com.ptsecurity.appsec.ai.ee.utils.ci.integration.plugin.jenkins.credentials.SlimCredentialsImpl&%24class=com.ptsecurity.appsec.ai.ee.utils.ci.integration.plugin.jenkins.credentials.SlimCredentialsImpl&stapler-class=com.ptsecurity.appsec.ai.ee.utils.ci.integration.plugin.jenkins.credentials.LegacyCredentialsImpl&%24class=com.ptsecurity.appsec.ai.ee.utils.ci.integration.plugin.jenkins.credentials.LegacyCredentialsImpl&stapler-class=com.cloudbees.plugins.credentials.impl.CertificateCredentialsImpl&%24class=com.cloudbees.plugins.credentials.impl.CertificateCredentialsImpl&json=%7B%22domain%22%3A+%22_%22%2C+%22%22%3A+%225%22%2C+%22credentials%22%3A+%7B%22userName%22%3A+%22admin%22%2C+%22password%22%3A+%22$($adminpwd)%22%2C+%22%24redact%22%3A+%22password%22%2C+%22serverCaCertificates%22%3A+%22-----BEGIN+CERTIFICATE-----%5CnMIIFVDCCAzygAwIBAgIIYaQyGbkTSjEwDQYJKoZIhvcNAQELBQAwMjETMBEGA1UE%5CnCgwKRG9tYWluLk9SRzEbMBkGA1UEAwwSRG9tYWluLk9SRyBSb290IENBMB4XDTE5%5CnMDMwNzA4MjAzNFoXDTM5MDMwNzA4MjAzNFowOjETMBEGA1UECgwKRG9tYWluLk9S%5CnRzEjMCEGA1UEAwwaRG9tYWluLk9SRyBJbnRlcm1lZGlhdGUgQ0EwggIiMA0GCSqG%5CnSIb3DQEBAQUAA4ICDwAwggIKAoICAQCxEpZw1eGb%2Bfvp0iISDnIp6kP1mqfAPF1H%5CnquN6TVgGxpBvavYuOgQIFWjobniH09a4c5ma5qKd%2FCrC7iL2SpuRyJHZLD9PD8yO%5CnQpyEnELLNuMvhx%2BqEGI%2BOClJJWxj1P%2B0cvYRtS%2F9vq64ZnL46HItXmqnPUIIwwVH%5CnJ6aZloRbfHHVguQepT6izMzWr6zfvr4MjoTzAb4s5R0NsNB0KaUV%2Ffp3V7yVRmUq%5Cno9EHfLFP%2BJy3QwAIfCB4PmkYbX9FDE6hicUFKu9x0w64Jb9on8J0mCfrl3cDYmyp%5CnxeAbkypjWHYkNgYav3IpKDJBE2o%2BbID8DJJr%2B53%2F62cKiHT9FqyR%2BDCuoMwc%2BH3P%5Cn0HAhi4EgbrIgi8h1nibm0AgSTb9DX7GhOEUio48mfE%2FWhI%2F26tVDQ%2B%2Bud8K%2BHeXL%5CnWvpfU1UoaQ9ClG26gRDGGcqJMC%2Ft2y1zCMsjfw2lyZVvoquYVhOACqUgK4Wq9PVl%5CnpGCovywqhoW1I7e5nuCmH2vQJOQQacdrkkEOpQyS%2BR3nQK2UQofMJHsLHnY7p%2F1m%5Cnz7M%2BvtsPIl1A0pQrGBPFa4P3ze0UXvsv4YmhplJrPdv%2FfqSySlvCp7dz0SAJ55ts%5Cnwk%2FvoZL3Wu5MM4oFC%2B%2BJZYM0Za7oUTHz4G5iCJz6N9bkpHQpg7VXTiJm6JyZe2YG%5CnH1VTiwyjRQIDAQABo2YwZDAOBgNVHQ8BAf8EBAMCAQYwEgYDVR0TAQH%2FBAgwBgEB%5Cn%2FwIBADAdBgNVHQ4EFgQUEbOON7jUO47uGxr0muy2xOh3vhQwHwYDVR0jBBgwFoAU%5CnygE1DVJ%2FLOL%2B2tlTF8fw8cSJcNwwDQYJKoZIhvcNAQELBQADggIBAKBYe1jGYwPo%5Cn1Av%2FA7DkLQGbXOAvkLmkgYNoCC5%2BJ6AfCeaCu%2Fpzhzi4zlj9f081wz9wYr%2Fr4Ake%5CnVlnNOtzejKXLlbvocow842xEGb0z9YGh5pIgyvwvRe1y9rEy7CmmrCQwLGzlGAqK%5Cn48bD6Y%2FxvT3WWdkxvCQoc%2F3S1WGpBdN6ZiS9VlprpEOl0j1r4ns9Hwm7CQjm95sE%5Cn9sD%2FvPOSRdp%2Blzfx36gWOWX4r7FAkGSk3yHaRXIP1HKy4PhzZUmjMeIMvN7o86sj%5Cnzt2MvfeUlU5FvmElBsuMraJ3MDiSaNAOg%2F13bRQBNUjsrLuKBDzWnvS41LdfMXEY%5CnedmnNyVflw4100lj7Oul1ovuJ6R1s6X3TFn%2FsRjwAAbVJDTUBop9quu9qHpnBpim%5CnqNch6fFTrgZSecRsXqbxPc4mNOv%2B4oz5mGkg%2FQTmq64nQHwPlULjqeEWqPcvrMPx%5CnSrJSxHqFxHgECr8uM51Gf2%2BONxvcEdZegRelyU1PMzc%2BctSt5J%2F%2F77h%2BrVYAoVq%2B%5Cn7qX27UrXTALGQHI1v2tJuVMYIVJuxbzD6lstG8IFqOJPh6lAL%2FmW0WeaC%2F3ShV5D%5CnFFhyCIc59CbX9NOHQfItkAi2O8NrjYkoPrhwgKzJCFbB90jVixaMatOVUjdnl0gS%5Cnw3oG7pLjhMOWzB6mUoSVpk8QxJCH4pCA%5Cn-----END+CERTIFICATE-----%22%2C+%22id%22%3A+%22%22%2C+%22description%22%3A+%22%22%2C+%22stapler-class%22%3A+%22com.ptsecurity.appsec.ai.ee.utils.ci.integration.plugin.jenkins.credentials.SlimCredentialsImpl%22%2C+%22%24class%22%3A+%22com.ptsecurity.appsec.ai.ee.utils.ci.integration.plugin.jenkins.credentials.SlimCredentialsImpl%22%7D%7D" | Out-File -Append logs\install.log
	
	# извлекаем ID добавленных кредов
	$c_aiee_creds = Get-Content -path 'C:\Program Files (x86)\Jenkins\credentials.xml' | Out-String
	$tmp = $c_aiee_creds -match '(<id>)(.*)(</id>)'
	if ($tmp) {
		$credid = $matches[0].Split("<")[1].Substring(3)
	}
	else {
		Write-Host 'Ошибка: не удалось найти ID добавленных учётных данных. Логи скопированы в папку logs.'  -ForegroundColor Red
		$c_aiee_creds | Out-File -Append logs\install.log
		Exit
	}

	# патчим конфиг плагина новым УРЛом
	$c_aiee_plugin = Get-Content -path 'C:\Program Files (x86)\Jenkins\com.ptsecurity.appsec.ai.ee.utils.ci.integration.plugin.jenkins.Plugin.xml' | Out-String
	$c_aiee_plugin = $c_aiee_plugin -ireplace '(<slimServerSettings>\s*<serverSlimUrl>)(.*)',"`$1https://$myFQDN`:8443</serverSlimUrl>" 
	
	# патчим конфиг плагина ID кредов
	$c_aiee_plugin -replace '(<serverSlimCredentialsId>)(.*)',"<serverSlimCredentialsId>$credid</serverSlimCredentialsId>" | Set-Content -Path 'C:\Program Files (x86)\Jenkins\com.ptsecurity.appsec.ai.ee.utils.ci.integration.plugin.jenkins.Plugin.xml'
	
	# патчим креды новым сертификатом
	$server_cert = Get-Content -path 'C:\TOOLS\certs\INT\out\01\ca.chain.pem.crt' | Out-String
	$c_aiee_creds -ireplace '(<serverCaCertificates>)([\d\w\W]{1,})(<\/serverCaCertificates>)',"`$1$server_cert`$3" | Set-Content -Path 'C:\Program Files (x86)\Jenkins\credentials.xml'

	# возвращаем защищённую авторизацию в Jenkins
	Write-Host 'Активирую усиленную авторизацию в Jenkins...' -ForegroundColor Yellow
	net stop Jenkins | Out-File -Append logs\install.log	
	copy config\secure-config.xml "C:\Program Files (x86)\Jenkins\config.xml"
	Set-Auth-Header "admin" "P@ssw0rd"
	Start-Jenkins "https://$($myFQDN):8080/computer/LOCAL/" $global:Headers
	
	# извлекаем строку запуска jenkins агента и записываем её в run-agent.bat
	Write-Host 'Настраиваю агента Jenkins...' -ForegroundColor Yellow
	$node = Invoke-WebRequest -Uri "https://$($myFQDN):8080/computer/LOCAL/" -Headers $global:Headers
	$tmp = $node.ParsedHtml.body.innerText | Out-String
	$found = $tmp -match '(java)(.*)(jenkins")'
	if ($found) {
		copy config\run-agent.bat C:\TOOLS\run-agent.bat
		$matches[0] | Out-File -Encoding "UTF8" -Append C:\TOOLS\run-agent.bat
		# Включаем IE ESC обратно
		Enable-InternetExplorerESC
		Start-Sleep 3
	}
	else {
		Write-Host 'Ошибка: строка запуска агента Jenkins не обнаружена. Логи скопированы в папку logs.'  -ForegroundColor Red
		$tmp | Out-File -Append logs\install.log
		Exit
	}	
}