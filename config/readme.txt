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
2. Скопируйте плагин C:\TOOLS\ptai-cli-plugin-0.1.jar на хост агента сборки и запомните полный путь к нему
3. Откройте настройки сборки вашего проекта и добавьте шаг "вызов командной строки"
4. Подготовьте строку запуска AI:

java -jar /путь/к/плагину/ptai-cli-plugin-0.1.jar --folder "WorkspaceПроекта" --project "ИмяПроектаИзAIViewer" --node PTAI --username admin --token %adminpwd% --url https://%myFQDN%:8443

Примечание:
	Для TeamCity указать параметр folder следующим образом: --folder "%system.teamcity.build.workingDir%"
	Для Gitlab: --folder "$CI_BUILDS_DIR"
	Для Jenkins: --folder ""

5. Вставьте строку запуска в шаг сборки
6. Сохраните и запустите сборку

---ПАРОЛИ---

Пароли, заданные в процессе установки, сохранены в файле C:\TOOLS\passwords.xml
Внимание: некоторые спецсимволы пароля заменяются по стандарту экранирования html:
http://htmlbook.ru/samhtml/tekst/spetssimvoly

---ПЕРЕЗАГРУЗКА---

В случае перезагрузки системы, пожалуйста, войдите под учётной записью текущего пользователя для автозапуска скриптов, либо запустите их самостоятельно:
	C:\TOOLS\run-agent.bat
	C:\TOOLS\run-service.bat
	
---БЕЗОПАСНОСТЬ---

Для обеспечения безопасности сервера закройте на межсетевом экране все порты, кроме 443 и 8443.
При наличии антивируса рекомендуется добавить каталог "C:\Program Files (x86)\Positive Technologies\Application Inspector Agent" в исключения, т.к. некоторые антивирусы могут блокировать подозрительную активность, когда AI взаимодействует с файламами во время сканирования.

---ДОПОЛНИТЕЛЬНО---

Полный список доступных параметров плагина можно получить, если обратиться к нему без параметров: 
	java -jar C:\TOOLS\ptai-cli-plugin-0.1.jar
	
	usage: java -jar ptai-cli-plugin-0.1.jar [--excludes <files>] 
	--folder <folder> 
	[--includes <files>] 
	--node <name or tag> 
	[--output <folder>] 
	--project <project name> 
	--token <token> 
	[--truststore <file>] 
	--url <url> 
	--username <name> 
	[--verbose]
	
    --excludes <files>         Comma-separated list of files to exclude from scan
    --folder <folder>          Source folder to scan
    --includes <files>         Comma-separated list of files to include to scan
    --node <name or tag>       Node name or tag for SAST to be executed on
    --output <folder>          Folder where AST reports are to be stored
    --project <project name>   Project name how it is setup and seen in the PT AI viewer
    --token <token>            PT AI integration service API token
    --truststore <file>        Path to file that stores trusted CA certificates
    --url <url>                PTAI integration service URL, i.e. https://ptai.domain.org:8443
    --username <name>          PT AI integration service account name
    --verbose                  Provide verbose console log output