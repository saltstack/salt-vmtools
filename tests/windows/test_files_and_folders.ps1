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

Write-TestLabel "Testing Remove-FileOrFolder"

Write-Host "- Remove Directory: " -NoNewLine
$path = "C:\RemoveDir"
New-Item -Path $path -ItemType directory -Force | Out-Null
Remove-FileOrFolder -Path $path
if (!(Test-Path -Path $path)) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Remove File: " -NoNewLine
$path = "C:\RemoveFile.txt"
New-Item -Path $path -ItemType file -Force | Out-Null
Remove-FileOrFolder -Path $path
if (!(Test-Path -Path $path)) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Status $failed
Write-Label "="
Write-Host ""
exit $failed
