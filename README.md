# ptaiInstallWizard
Install Wizard для анализатора кода Positive Technologies Application Inspector Enterprise

Для запуска:
1. Скачать дистрибутивы AI Enterprise
2. Скачать ресурсы: (ссылка выдаётся по запросу)
3. Скачать файлы данного репозитория и положить их в папку с ресурсами
4. Открыть Powershell с правами администратора 
5. Выполнить команды:
```powershell
cd %путь до директории скрипта установки%
dir AI-Wizard.ps1 | Unblock-File
Set-ExecutionPolicy RemoteSigned -Scope Process
.\AI-Wizard.ps1 -install -genpass
```

TODO:
- установка со своими сертификатами
- установка утилит в произвольную директорию