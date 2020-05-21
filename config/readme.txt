---ВСТРАИВАНИЕ В JENKINS---
1. Установите плагин C:\TOOLS\ptai-jenkins-plugin.hpi
2. Перейдите в меню Настройки системы
3. Найдите раздел Анализ уязвимостей PT AI
4. Добавьте Упрощенную конфигурацию PT AI
5. Укажите следующие данные:
	Имя: PTAIconfig
	URL: https://%myFQDN%:8443
	Учётные данные: Упрощенная аутентификация PT AI
	Имя пользователя: admin
	Пароль: %adminpwd%
	Сертификат сервера: скопируйте из C:\TOOLS\certs\server-cert.txt
6. Нажмите Добавить
7. Нажмите Проверить соединение
8. Нажмите Сохранить
9. Откройте настройки сборки вашего проекта и добавьте шаг "Анализ уязвимостей PT AI"
10. Укажите Имя проекта, созданного в программе AI Viewer
11. Сохраните и запустите сборку

---ВСТРАИВАНИЕ В ДРУГИЕ СИСТЕМЫ CI/CD---
1. Установите Java JDK 1.8 на агента сборки
2. Скопируйте плагин C:\TOOLS\ptai-cli-plugin.jar на хост агента сборки и запомните полный путь к нему
3. Скопируйте сертификаты сервера на хост агента сборки: 
	C:\TOOLS\certs\RootCA.pem.crt 
	C:\TOOLS\certs\IntermediateCA.pem.crt
4. Импортируйте сертификаты сервера в хранилище сертификатов Java агента сборки, выполнив на нём следующие команды (пример):
	keytool -importcert -keystore jdk1.8\jre\lib\security\cacerts -storepass "changeit" -alias AIRootCA -file RootCA.pem.crt -noprompt
	keytool -importcert -keystore jdk1.8\jre\lib\security\cacerts -storepass "changeit" -alias AIIntermediateCA -file IntermediateCA.pem.crt -noprompt
	, где -keystore - путь к хранилищу сертификатов
		  -storepass - пароль от хранилища сертификатов
		  -file - путь к файлу сертификата для импорта
5. Откройте настройки сборки вашего проекта в CI-системе и добавьте шаг "вызов командной строки"
6. Подготовьте строку запуска AI по примеру:
	java -jar /путь/к/плагину/ptai-cli-plugin.jar slim-ui-ast --input="WorkspaceПроекта" --project="ИмяПроектаИзAIViewer" --node=PTAI --user=admin --token=%adminpwd% --url=https://%myFQDN%:8443
	Примечание для параметра input:
		Для TeamCity: --input "%system.teamcity.build.workingDir%"
		Для Gitlab:   --input "$CI_PROJECT_DIR"
		Для Jenkins:  --input ""
7. Вставьте строку запуска в шаг сборки
8. Сохраните и запустите сборку

---ПАРОЛИ---
Пароли, заданные в процессе установки, сохранены в файле C:\TOOLS\passwords.txt

---ПЕРЕЗАГРУЗКА---
В случае перезагрузки системы, пожалуйста, войдите под учётной записью текущего пользователя для автозапуска служб, либо запустите их самостоятельно:
	C:\TOOLS\run-agent.bat
	C:\TOOLS\run-service.bat

---БЕЗОПАСНОСТЬ---
Для обеспечения безопасности сервера закройте на межсетевом экране все порты, кроме 443 и 8443.
При наличии антивируса рекомендуется добавить каталог "C:\Program Files (x86)\Positive Technologies\Application Inspector Agent" в исключения, т.к. некоторые антивирусы могут блокировать подозрительную активность, когда AI взаимодействует с файламами во время сканирования.

---ДОПОЛНИТЕЛЬНО---
Полный список доступных параметров плагина можно получить, если обратиться к нему без параметров: 
	> java -jar ptai-cli-plugin.jar slim-ui-ast
	Usage: java -jar ptai-cli-plugin.jar slim-ui-ast [-v] --url=<url> -u=<name>
		-t=<token> --input=<path> [--output=<path>] -p=<name> [-i=<pattern>]
		[-e=<pattern>] -n=<name> [--truststore=<path>]
		[--truststore-pass=<password>] [--truststore-type=<type>]
	Calls PT AI EE for AST using integration server. Project settings are defined
	in the PT AI viewer UI
		--url=<url>            	   PT AI integration service URL, i.e. https://ptai.domain.org:8443
		-u, --user=<name>          PT AI integration service account name
		-t, --token=<token>        PT AI integration service API token
			--input=<path>         Source file or folder to scan
			--output=<path>        Folder where AST reports are to be stored. By default .ptai folder is used
		-p, --project=<name>       Project name how it is setup and seen in the PT AI Viewer
		-i, --includes=<pattern>   Comma-separated list of files to include to scan.
									The string is a comma separated list of includes
									for an Ant fileset eg. '**/*.jar'(see http://ant.apache.org/manual/dirtasks.html#patterns ). 
									The base directory for this fileset is the sources folder
		-e, --excludes=<pattern>   Comma-separated list of files to exclude from
									scan. The syntax is the same as for includes
		-n, --node=<name>          Node name or tag for SAST to be executed on
			--truststore=<path>    Path to file that stores trusted CA certificates
			--truststore-pass=<password>
									Truststore password
			--truststore-type=<type>
									Truststore file type, i.e. JKS, PKCS12 etc. By
									default JKS is used
		-v, --verbose              Provide verbose console log output
	Exit Codes:
		0      AST complete, policy (if set up) assessment success
		1      AST complete, policy (if set up) assessment failed
		2      AST complete, policy (if set up) assessment success, minor warnings
				were reported
		3      AST failed
		1000   Invalid input