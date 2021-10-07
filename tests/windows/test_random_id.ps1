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

Write-Label $MyInvocation.MyCommand.Name

Write-TestLabel "Testing Get-RandomizedMinionId"

Write-Host "- Random Id: " -NoNewline
$random_id = Get-RandomizedMinionId
if ($random_id -match "^minion_[\w\d]{5}$") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Second Id: " -NoNewline
$random_id_2 = Get-RandomizedMinionId
if ($random_id -ne $random_id_2) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Custom prefix: " -NoNewline
$random_id = Get-RandomizedMinionId -Prefix spongebob
if ($random_id -match "^spongebob_[\w\d]{5}$") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Custom length: " -NoNewline
$random_id = Get-RandomizedMinionId -Length 7
if ($random_id -match "^minion_[\w\d]{7}$") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Custom length and prefix: " -NoNewline
$random_id = Get-RandomizedMinionId -Prefix spongebob -Length 7
if ($random_id -match "^spongebob_[\w\d]{7}$") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Status $failed
Write-Label "="
Write-Host ""
exit $failed
