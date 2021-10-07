$vmtools_base_reg = "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools"
$vmtools_base_path = "C:\temp_test"
New-Item -Path $vmtools_base_reg -Force | Out-Null
New-ItemProperty -Path $vmtools_base_reg -Name InstallPath -Value "$vmtools_base_path" -Force | Out-Null
New-Item -Path "$vmtools_base_path" -ItemType directory -Force | Out-Null
New-Item -Path "$vmtools_base_path\vmtoolsd.exe" -ItemType file -Force | Out-Null
function Write-Success { Write-Host "Success" -ForegroundColor Green }
function Write-Failed { Write-Host "Failed" -ForegroundColor Red }

$failed = 0

$Action = "test"
Import-Module .\windows\svtminion.ps1
Import-Module .\tests\windows\helpers.ps1

# Suppress error messages
$log_level_value = 0

Write-Label $MyInvocation.MyCommand.Name

Write-TestLabel "Testing Find-StandardSaltInstallation"

Write-Host "- No existing salt installation: " -NoNewline
$result = Find-StandardSaltInstallation
if ($result -eq $false) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Existing old location: " -NoNewline
New-Item -Path "C:\salt\bin\python.exe" -ItemType file -Force | Out-Null
$result = Find-StandardSaltInstallation
Remove-Item -Path "C:\salt\bin\python.exe" -Force | Out-Null
if ($result -eq $true) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Existing new location: " -NoNewline
New-Item -Path "$salt_dir\bin\python.exe" -ItemType file -Force | Out-Null
$result = Find-StandardSaltInstallation
Remove-Item -Path "$salt_dir\bin\python.exe" -Force | Out-Null
if ($result -eq $true) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Status $failed
Write-Label "="
Write-Host ""
exit $failed
