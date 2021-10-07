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

# Current status
$service_status = (Get-Service -Name $ServiceName).Status


Write-TestLabel "Testing Start-MinionService"

# Make sure the service is stopped before beginning
Stop-Service -Name Spooler

Write-Host "- Starting service: " -NoNewline
Start-MinionService -ServiceName Spooler
if ((Get-Service -Name $ServiceName).Status -eq "Running") { Write-Success } else { Write-Failed; $failed = 1 }


Write-TestLabel "Testing Stop-MinionService"

Write-Host "- Stopping service: " -NoNewline
Stop-MinionService -ServiceName Spooler
if ((Get-Service -Name $ServiceName).Status -eq "Stopped") { Write-Success } else { Write-Failed; $failed = 1 }

# Set it back to Running status if it was running to begin with
if ($service_status -eq "Running") { Start-Service -Name Spooler }

Write-Status $failed
Write-Label "="
Write-Host ""
exit $failed
