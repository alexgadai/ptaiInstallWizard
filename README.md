# PT AI Install Wizard
Автоматический установщик для анализатора кода Positive Technologies Application Inspector Enterprise

Для запуска:
1.	Установить Win64 OpenSSL v1.1.1h Light https://slproweb.com/products/Win32OpenSSL.html
-	Также для установки самого OpenSSL потребуются редисты: https://aka.ms/vs/16/release/vc_redist.x64.exe
2.	Прописать путь к openssl/bin в переменную окружения PATH. После этого проверить, что команда openssl выполняется из командной строки Windows.
3.	Выполнить вход в Windows под учётной записью с правами администратора.
4.	Распаковать архивы Дистрибутива и Инсталлятора
5.	Запустить Powershell с правами администратора
6.	Перейти (cd) в каталог с распакованным Инсталлятором
7.	Запустить скрипт инсталляции, пример запуска:
```powershell
.\install.ps1 -aiepath C:\Users\Administrator\Downloads\AIE -toolspath C:\TOOLS
# aiepath 	- путь до каталога с дистрибутивом AI (там где папки aic/aiv/aie)
# toolspath	– каталог, куда будут перемещены артефакты установки (сертификаты, пароли)
```
8.	Если скрипт не запускается из-за ограничений доменной политики, выполните следующую команду и попробуйте снова:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process 
```
9.	Если установка производится на Windows Server 2012 R2, также потребуется установить пакеты:
-	http://www.catalog.update.microsoft.com/Search.aspx?q=3191564 
-	https://dotnet.microsoft.com/download/dotnet-framework/thank-you/net48-offline-installer 


TODO:
- скрипт деинсталляции
- обновить инструкции в readme.txt