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

Write-Label $MyInvocation.MyCommand.Name

Write-TestLabel "Testing Get-Status"

Write-Host "- notInstalled: " -NoNewline
Remove-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -ErrorAction SilentlyContinue
$result = Get-Status
if ($result -eq 2) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- installed: " -NoNewline
New-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 0 | Out-Null
$result = Get-Status
if ($result -eq 0) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- installing: " -NoNewline
Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 1
Start-Process powershell -ArgumentList "-file .\svtminion.ps1 -d"
$result = Get-Status
if ($result -eq 1) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- installFailed: " -NoNewline
Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 3
$result = Get-Status
if ($result -eq 3) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- removing: " -NoNewline
Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 4
Start-Process powershell -ArgumentList "-file .\svtminion.ps1 -d"
$result = Get-Status
if ($result -eq 4) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- removeFailed: " -NoNewline
Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 5
$result = Get-Status
if ($result -eq 5) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Unknown Status: " -NoNewline
Set-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus -Value 7
$result = Get-Status
if ($result -eq 7) { Write-Success } else { Write-Failed; $failed = 1 }

Write-TestLabel "Testing Set-Status"

Write-Host "- installed: " -NoNewline
Set-Status -NewStatus installed
$result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
if ($result.SaltMinionStatus -eq 0) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- installing: " -NoNewline
Set-Status -NewStatus installing
$result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
if ($result.SaltMinionStatus -eq 1) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- notInstalled: " -NoNewline
Set-Status -NewStatus notInstalled
$result = Get-Status
if ($result -eq 2) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- installFailed: " -NoNewline
Set-Status -NewStatus installFailed
$result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
if ($result.SaltMinionStatus -eq 3) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- removing: " -NoNewline
Set-Status -NewStatus removing
$result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
if ($result.SaltMinionStatus -eq 4) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- removeFailed: " -NoNewline
Set-Status -NewStatus removeFailed
$result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
if ($result.SaltMinionStatus -eq 5) { Write-Success } else { Write-Failed; $failed = 1 }

Write-TestLabel "Testing Set-FailedStatus"

Write-Host "- installFailed: " -NoNewline
$Action = "add"
Set-FailedStatus
$result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
if ($result.SaltMinionStatus -eq 3) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- removeFailed: " -NoNewline
$Action = "remove"
Set-FailedStatus
$result = Get-ItemProperty -Path $vmtools_base_reg -Name SaltMinionStatus
if ($result.SaltMinionStatus -eq 5) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Status $failed
Write-Label $MyInvocation.MyCommand.Name
exit $failed
