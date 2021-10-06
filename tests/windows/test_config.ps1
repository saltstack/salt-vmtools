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

Write-TestLabel "Testing Get-ConfigToolsConf"

# We need to create a tools.conf file with some settings
$content = @("[salt_minion]"; "master=tc_master"; "id=tc_minion")
$tc_content = $content -join "`n"
New-Item -Path $vmtools_conf_file -Value $tc_content -Force | Out-Null

$config = Get-ConfigToolsConf

Write-Host "- Verifying master: " -NoNewline
if ($config["master"] -eq "tc_master") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Verifying id: " -NoNewline
if ($config["id"] -eq "tc_minion") { Write-Success } else { Write-Failed; $failed = 1 }


Write-TestLabel "Testing Get-ConfigGuestVars"

# We have to try to mock getting guestVars
function Get-GuestVars { "master=gv_master id=gv_minion" }
$config = Get-ConfigGuestVars

Write-Host "- Verifying master: " -NoNewline
if ($config["master"] -eq "gv_master") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Verifying id: " -NoNewline
if ($config["id"] -eq "gv_minion") { Write-Success } else { Write-Failed; $failed = 1 }


Write-TestLabel "Testing Get-ConfigCLI"

$ConfigOptions = @("master=cli_master"; "id=cli_minion")
$config = Get-ConfigCLI

Write-Host "- Verifying master: " -NoNewline
if ($config["master"] -eq "cli_master") { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- Verifying id: " -NoNewline
if ($config["id"] -eq "cli_minion") { Write-Success } else { Write-Failed; $failed = 1 }


Write-TestLabel "Testing Get-MinionConfig"

Write-Host "- guestVars overwrite tools.conf: " -NoNewline

# We need to create some tools.conf content
$content = @("[salt_minion]"; "ma=tc_m"; "id=tc_i")
$tc_content = $content -join "`n"
New-Item -Path $vmtools_conf_file -Value $tc_content -Force | Out-Null

# modify guestvars function
function Get-GuestVars { "ma=gv_m" }

# Clear CLI
$ConfigOptions = $null
$config = Get-MinionConfig
if (($config["ma"] -eq "gv_m") -and ($config["id"] -eq "tc_i")) { Write-Success } else { Write-Failed; $failed = 1 }

Write-Host "- CLI options overwrite everything: " -NoNewline
$ConfigOptions = @("ma=cli_m"; "id=cli_i")
$config = Get-MinionConfig
if (($config["ma"] -eq "cli_m") -and ($config["id"] -eq "cli_i")) { Write-Success } else { Write-Failed; $failed = 1 }


#Write-TestLabel "Testing Add-MinionConfig"
#
## We need to create some content
#$content = @("[salt_minion]"; "master=tc_master")
#$tc_content = $content -join "`n"
#New-Item -Path $vmtools_conf_file -Value $tc_content -Force | Out-Null
#
## We have to try to mock getting guestVars
#function Get-GuestVars { "id=gv_minion" }
#
## Set CLI Options
#$ConfigOptions = @("root_dir=cli_root_dir")
#Add-MinionConfig
##TODO: Finish this

Write-Status $failed
Write-Label $MyInvocation.MyCommand.Name
exit $failed
