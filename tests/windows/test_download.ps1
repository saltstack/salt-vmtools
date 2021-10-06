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

Write-TestLabel "Testing Get-SaltFromWeb"

Get-SaltFromWeb
Write-Host "- Zip File Downloaded: " -NoNewline
$web_file = "$base_salt_install_location\$salt_web_file_name"
if (Test-Path -Path $web_file) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Hash File Downloaded: " -NoNewline
$hash_file = "$base_salt_install_location\$salt_hash_name"
if (Test-Path -Path $hash_file) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Hash Matches: " -NoNewline
$exp_hash = Get-HashFromFile $hash_file $salt_web_file_name
$file_hash = (Get-FileHash -Path $web_file -Algorithm SHA512).Hash
if ($file_hash -like $exp_hash) { Write-Success } else { Write-Failed; $failed = 1 }

Write-TestLabel "Testing Expand-ZipFile (slow test)"

Expand-ZipFile -ZipFile $web_file -Destination $base_salt_install_location
Write-Host "- Checking for salt.exe: " -NoNewline
if (Test-Path -Path $salt_bin) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Checking for ssm.exe: " -NoNewline
if (Test-Path -Path $ssm_bin) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Status $failed
Write-Label $MyInvocation.MyCommand.Name
exit $failed
