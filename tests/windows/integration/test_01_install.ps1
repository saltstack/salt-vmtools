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

Write-TestLabel "Testing Install"

function Get-GuestVars { "master=gv_master id=gv_minion" }
Install

Write-Host "- Status set to installed: " -NoNewline
try {
    $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
} catch {
    $current_status = 2
}
if ($current_status -eq 0) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Salt binary installed: " -NoNewline
if (Test-Path $salt_bin) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- SSM binary installed: " -NoNewline
if (Test-Path $ssm_bin) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Salt-call.bat installed: " -NoNewline
if (Test-Path "$salt_dir\salt-call.bat") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Salt-minion.bat installed: " -NoNewline
if (Test-Path "$salt_dir\salt-minion.bat") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Salt-minion service registered: " -NoNewline
$service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
if ($service) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Salt-minion service running: " -NoNewline
if ((Get-Service -Name salt-minion).Status -eq "Running") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Minion config present: " -NoNewline
if (Test-Path $salt_config_file) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Added to system path: " -NoNewline
$path = "$env:ProgramFiles\Salt Project\salt"
$path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
$current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
if ($current_path -like "*$path*") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Status $failed
Write-Label "="
Write-Host ""
exit $failed
