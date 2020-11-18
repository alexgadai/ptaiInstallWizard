# PT AI Install Wizard
Автоматический установщик для анализатора кода Positive Technologies Application Inspector Enterprise

Для запуска:
1.	Выполнить вход в Windows под учётной записью с правами администратора
2.	Установить Win64 OpenSSL v1.1.1h Light https://slproweb.com/products/Win32OpenSSL.html
-	Также для установки самого OpenSSL потребуются редисты: https://aka.ms/vs/16/release/vc_redist.x64.exe
3.	Запустить Powershell с правами администратора
4.	Запустить скрипт инсталляции, пример запуска:
```powershell
.\AI-one-click-install.ps1 -aiepath C:\Users\Administrator\Downloads\AIE
# aiepath - путь до каталога с дистрибутивом AI (там где папки aic/aiv/aie)
```
5.	Если скрипт не запускается из-за ограничений доменной политики, выполните следующую команду и попробуйте снова:
```powershell
Set-ExecutionPolicy Unrestricted Process
```
6.	Если установка производится на Windows Server 2012 R2, также потребуется установить пакеты:
-	http://www.catalog.update.microsoft.com/Search.aspx?q=3191564 
-	https://dotnet.microsoft.com/download/dotnet-framework/thank-you/net48-offline-installer 


TODO:
- скрипт деинсталляции
