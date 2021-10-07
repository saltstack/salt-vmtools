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

Write-TestLabel "Testing Remove"

Remove

Write-Host "- Status set to notInstalled: " -NoNewline
try {
    $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
} catch {
    # You'll only get here if the path isn't present
    $current_status = 2
}
if ($current_status -eq 2) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Config directory removed: " -NoNewline
if (!(Test-Path "$env:ProgramData\Salt Project")) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Install directory removed: " -NoNewline
if (!(Test-Path "$env:ProgramFiles\Salt Project")) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- salt-minion service not registered: " -NoNewline
$service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
if (!($service)) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Removed from system path: " -NoNewline
$path = "$env:ProgramFiles\Salt Project\salt"
$path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
$current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
if ($current_path -notlike "*$path*") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Status $failed
Write-Label "="
Write-Host ""
exit $failed
