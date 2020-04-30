:search
ECHO "Waiting for Jenkins to start..."
tasklist|find "jenkins"
IF %ERRORLEVEL% == 0 GOTO found
TIMEOUT /T 3
GOTO search

:found
cd C:\TOOLS
