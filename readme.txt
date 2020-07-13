Быстрый старт:
1. Открыть Powershell с правами администратора
2. Выполнить команды:
cd %путь до директории скрипта установки%
dir AI-Wizard.ps1 | Unblock-File
Set-ExecutionPolicy RemoteSigned -Scope Process
.\AI-Wizard.ps1 -install -genpass
