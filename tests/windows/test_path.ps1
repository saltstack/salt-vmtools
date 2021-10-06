$vmtools_base_reg = "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools"
$vmtools_base_path = "C:\temp_test"
New-Item -Path $vmtools_base_reg -Force | Out-Null
New-ItemProperty -Path $vmtools_base_reg -Name InstallPath -Value "$vmtools_base_path" -Force | Out-Null
New-Item -Path "$vmtools_base_path" -ItemType directory -Force | Out-Null
New-Item -Path "$vmtools_base_path\vmtoolsd.exe" -ItemType file -Force | Out-Null
New-Item -Path "$vmtools_base_path\salt-call.bat" -ItemType file -Force | Out-Null
New-Item -Path "$vmtools_base_path\salt-call.bat" -ItemType file -Force | Out-Null
function Write-Success { Write-Host "Success" -ForegroundColor Green }
function Write-Failed { Write-Host "Failed" -ForegroundColor Red }

$failed = 0

$Action = "test"
Import-Module .\windows\svtminion.ps1
Import-Module .\tests\windows\helper.ps1

Write-TestLabel "Testing Add-SystemPathValue"

Write-Host "- Adding to system path: " -NoNewline
Add-SystemPathValue -Path "C:\spongebob"
$path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
$path = Get-ItemProperty -Path $path_reg_key -Name Path
if ($path.Path -like "*C:\spongebob*") { Write-Success } else { Write-Failed; $failed = 1 }


Write-TestLabel "Testing Add-SystemPathValue"

Write-Host "- Removing from system path: " -NoNewline
Remove-SystemPathValue -Path "C:\spongebob"
$path = Get-ItemProperty -Path $path_reg_key -Name Path
if ($path.Path -notlike "*C:\spongebob*") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Status $failed
Write-Label $MyInvocation.MyCommand.Name
exit $failed
