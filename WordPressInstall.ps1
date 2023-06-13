# Шаг 1: Замена TLS на версию 1.2 для загрузки файлов из интернета
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Шаг 2: Загрузка и установка MySQL Server версии 8.0.28
$mysqlUrl = "https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.28-winx64.zip"
$mysqlZipPath = "$env:TEMP\mysql.zip"
$mysqlExtractPath = "$env:TEMP\mysql"
$mysqlInstallPath = "C:\mysql"

# Загрузка MySQL Server
Invoke-WebRequest -Uri $mysqlUrl -OutFile $mysqlZipPath

# Распаковка архива MySQL Server
Expand-Archive -Path $mysqlZipPath -DestinationPath $mysqlExtractPath

# Перемещение файлов MySQL в установочную папку
Move-Item -Path "$mysqlExtractPath\mysql-8.0.28-winx64\*" -Destination $mysqlInstallPath -Force

# Установка Visual C++ Redistributable for Visual Studio 2015
$vcRedistUrl = "https://aka.ms/vs/16/release/vc_redist.x64.exe"
$vcRedistPath = "$env:TEMP\vc_redist.x64.exe"

# Загрузка Visual C++ Redistributable
Invoke-WebRequest -Uri $vcRedistUrl -OutFile $vcRedistPath

# Установка Visual C++ Redistributable
Start-Process -FilePath $vcRedistPath -ArgumentList "/quiet", "/install" -Wait

# Инициализация MySQL Data Directory и запуск MySQL Service
Start-Process -FilePath "$mysqlInstallPath\mysqld.exe" -ArgumentList "--initialize-insecure", "--console" -Wait
Start-Process -FilePath "$mysqlInstallPath\mysqld.exe" -ArgumentList "--install" -Wait
Start-Service -Name "mysql"

# Подключение к MySQL Server
$mysqlExePath = "$mysqlInstallPath\mysql.exe"
$mysqlCommand = "ALTER USER 'root'@'localhost' IDENTIFIED BY '123qweASD';"
$securePassword = ConvertTo-SecureString -String '123qweASD' -AsPlainText -Force
$credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'root', $securePassword
Start-Process -FilePath $mysqlExePath -ArgumentList @("-u", $credentials.UserName, "-p" + $credentials.GetNetworkCredential().Password, "-e", $mysqlCommand) -Wait

Write-Host "MySQL Server успешно установлен."

# Шаг 3: Настройка MySQL для WordPress

$mysqlCommand = @"
CREATE DATABASE IF NOT EXISTS wordpress;
SELECT IF(EXISTS(SELECT 1 FROM mysql.user WHERE user = 'wpuser' AND host = 'localhost'), 'UserExists', 'UserNotExists') AS UserCheck;
"@

# Проверка наличия пользователя
$userExists = & $mysqlExePath -u root -e $mysqlCommand | Out-String

if ($userExists -like "*UserNotExists*") {
    $mysqlCommand = @"
CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'P@ssword';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';
FLUSH PRIVILEGES;
"@
    & $mysqlExePath -u root -e $mysqlCommand
    Write-Output "Пользователь wpuser создан успешно."
}
else {
    Write-Output "Пользователь wpuser уже существует."
}

# Шаг 4: Установка PHP версии 8.2 и добавление пути к переменной среды C:\php

# URL для загрузки архива PHP
$phpUrl = "https://windows.php.net/downloads/releases/archives/php-8.2.0-nts-Win32-vs16-x64.zip"
# Пути к архиву и каталогу для распаковки PHP
$phpZipPath = "$env:TEMP\php.zip"
$phpExtractPath = "$env:TEMP\php"

# Загрузка архива PHP
Invoke-WebRequest -Uri $phpUrl -OutFile $phpZipPath

# Распаковка архива
Expand-Archive -Path $phpZipPath -DestinationPath $phpExtractPath

# Перемещение содержимого распакованного каталога в C:\php
Move-Item -Path "$phpExtractPath\*" -Destination "C:\php" -Force

# Добавление пути C:\php к переменной среды PATH
$existingPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
$newPath = "C:\php;" + $existingPath
[Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")

Write-Host "PHP успешно установлен и добавлен в переменную среды PATH."

# Шаг 5: Конфигурация php.ini

$phpIniPath = "C:\php\php.ini"
# Создание нового файла php.ini
New-Item -Path $phpIniPath -ItemType File -Force
# Задание значений для необходимых настроек
@"
cgi.force_redirect = 0
cgi.fix_pathinfo = 1
fastcgi.impersonate = 1
fastcgi.logging = 0
extension=mysqli
extension=pdo_mysql

; Настройки PHP
post_max_size = 64M
upload_max_filesize = 64M
max_execution_time = 300
date.timezone = "Europe/Moscow"
"@ | Set-Content $phpIniPath
Write-Host "Файл php.ini успешно создан и настроен для работы с WordPress и PHP."

# Шаг 6: Установка ролей и компонентов IIS
Install-WindowsFeature -Name Web-Server, Web-Asp-Net45, Web-Mgmt-Console, Web-CGI, Web-Custom-Logging, Web-Log-Libraries

# Шаг 7: Настройка IIS - handler mappings - php-cgi.exe, default document - index.php, add application pool - wordpress and start.
Add-WindowsFeature Web-Scripting-Tools
Import-Module WebAdministration
# Установка обработчика для файлов PHP
$php = 'C:\php\php-cgi.exe'
$configPath = get-webconfiguration 'system.webServer/fastcgi/application' | where-object { $_.fullPath -eq $php }
if (!$configPath) {
    add-webconfiguration 'system.webserver/fastcgi' -value @{'fullPath' = $php }
}
# Create IIS handler mapping for handling PHP requests
$handlerName = "PHP"
$handler = get-webconfiguration 'system.webserver/handlers/add' | where-object { $_.Name -eq $handlerName }
if (!$handler) {
    add-webconfiguration 'system.webServer/handlers' -Value @{
        Name = $handlerName;
        Path = "*.php";
        Verb = "*";
        Modules = "FastCgiModule";
        scriptProcessor=$php;
        resourceType='Either' 
    }
}

# Configure the FastCGI Setting
# Set the max request environment variable for PHP
$configPath = "system.webServer/fastCgi/application[@fullPath='$php']/environmentVariables/environmentVariable"
$config = Get-WebConfiguration $configPath
if (!$config) {
    $configPath = "system.webServer/fastCgi/application[@fullPath='$php']/environmentVariables"
    Add-WebConfiguration $configPath -Value @{ 'Name' = 'PHP_FCGI_MAX_REQUESTS'; Value = 10050 }
}

$configPath = "system.webServer/fastCgi/application[@fullPath='$php']"
Set-WebConfigurationProperty $configPath -Name instanceMaxRequests -Value 10000
Set-WebConfigurationProperty $configPath -Name monitorChangesTo -Value 'C:\php\php.ini'

# Restart IIS to load new configs.
invoke-command -scriptblock {iisreset /restart }

Add-WebConfigurationProperty -Filter "/system.webServer/defaultDocument/files" -PSPath "IIS:\" -Name "Collection" -Value @{
    value = "index.php"
}

# Создание пула приложений 'wordpress' и запуск его
New-WebAppPool -Name "wordpress" 
Start-WebAppPool -Name "wordpress"
$poolUser = "Administrator"
$poolPassword = "WinServ2016"
# Задание настроек Application Pool Defaults
Set-ItemProperty "IIS:\AppPools\DefaultAppPool" -Name "managedPipelineMode" -Value 0
Set-ItemProperty "IIS:\AppPools\DefaultAppPool" -Name "processModel.identityType" -Value 3
Set-ItemProperty "IIS:\AppPools\DefaultAppPool" -Name "processModel.userName" -Value $poolUser
Set-ItemProperty "IIS:\AppPools\DefaultAppPool" -Name "processModel.password" -Value $poolPassword

Write-Host "IIS успешно настроен."

# Шаг 8: Загрузка и установка WordPress
$wordpressUrl = "https://wordpress.org/latest.zip"
$wordpressPath = "$env:TEMP\wordpress.zip"
Invoke-WebRequest -Uri $wordpressUrl -OutFile $wordpressPath
Expand-Archive -Path $wordpressPath -DestinationPath "C:\inetpub\wwwroot"

# Шаг 9: Конфигурация wp-config.php
Start-Sleep -Seconds 5

# Пути к файлам wp-config-sample.php и wp-config.php
$wpConfigSamplePath = "C:\inetpub\wwwroot\wordpress\wp-config-sample.php"
$wpConfigPath = "C:\inetpub\wwwroot\wordpress\wp-config.php"

# Проверка доступности файла wp-config-sample.php
while (-not (Test-Path -Path $wpConfigSamplePath -PathType Leaf)) {
    Write-Host "Ожидание доступности файла wp-config-sample.php..."
    Start-Sleep -Seconds 1
}

# Копирование файла wp-config-sample.php в wp-config.php
Copy-Item -Path $wpConfigSamplePath -Destination $wpConfigPath -Force

# Задержка перед выполнением замены значений
Start-Sleep -Seconds 5

# Замена значений в файле wp-config.php
(Get-Content $wpConfigPath) | ForEach-Object {
    $_ -replace "database_name_here", "wordpress" `
       -replace "username_here", "wpuser" `
       -replace "password_here", "P@ssword"
} | Set-Content $wpConfigPath -Encoding UTF8

# Вывод сообщения об успешном завершении
Write-Host "Конфигурация wp-config.php успешно обновлена."
Write-Host "Установка WordPress завершена."
# Очистка временных файлов
Remove-Item -Path $mysqlZipPath -Force
Remove-Item -Path $mysqlExtractPath -Force -Recurse
Remove-Item -Path $vcRedistPath -Force
Remove-Item -Path $wpConfigPath -Force
Remove-Item -Path $wordpressPath -Force
Remove-Item -Path $phpZipPath -Force
Remove-Item -Path $phpExtractPath -Force -Recurse
Start-Process "http://localhost/wordpress/wp-admin/install.php"