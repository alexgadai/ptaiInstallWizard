:search
ECHO "Waiting for Consul to start..."
tasklist|find "consul"
IF %ERRORLEVEL% == 0 GOTO found
TIMEOUT /T 10
GOTO search

:found
cd C:\TOOLS
java -Xmx2g -Xms32m -XX:+UseConcMarkSweepGC -Dspring.main.lazy-initialization=true -Dspring.profiles.active=prod -jar ptai-integration-service-0.1-spring-boot.jar 10
