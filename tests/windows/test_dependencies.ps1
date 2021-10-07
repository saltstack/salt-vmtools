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

Write-TestLabel "Testing Confirm-Dependencies"

Write-Host "- All dependencies present: " -NoNewline
$result = Confirm-Dependencies
if ($result -eq $true) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Missing registry key: " -NoNewline
Remove-Item -Path $vmtools_base_reg
$result = Confirm-Dependencies
if ($result -eq $false) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Missing registry value: " -NoNewline
New-Item -Path $vmtools_base_reg -Force | Out-Null
$result = Confirm-Dependencies
if ($result -eq $false) { Write-Success } else { Write-Failed; $failed = 1 }

# Adding back the registry so we can check the files
New-ItemProperty -Path $vmtools_base_reg -Name InstallPath -Value "$vmtools_base_path" -Force | Out-Null

Write-Host "- Missing vmtoolsd.exe: " -NoNewline
Move-Item "$vmtools_base_dir\vmtoolsd.exe" "$vmtools_base_path\vmtoolsd.exe.bak"
$result = Confirm-Dependencies
Move-Item "$vmtools_base_dir\vmtoolsd.exe.bak" "$vmtools_base_path\vmtoolsd.exe"
if ($result -eq $false) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Missing salt-call.bat: " -NoNewline
Move-Item ".\windows\salt-call.bat" ".\windows\salt-call.bak"
$result = Confirm-Dependencies
Move-Item ".\windows\salt-call.bak" ".\windows\salt-call.bat"
if ($result -eq $false) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Missing salt-minion.bat: " -NoNewline
Move-Item ".\windows\salt-minion.bat" ".\windows\salt-minion.bak"
$result = Confirm-Dependencies
Move-Item ".\windows\salt-minion.bak" ".\windows\salt-minion.bat"
if ($result -eq $false) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Status $failed
Write-Label "="
Write-Host ""
exit $failed
