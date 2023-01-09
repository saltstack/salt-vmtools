# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function setUpScript {
    # We need to create a tools.conf file with some settings
    Write-Host "Creating tools.conf: " -NoNewline
    $content = @("[salt_minion]"; "master=tc_master"; "id=tc_minion")
    $tc_content = $content -join "`n"
    New-Item -Path $vmtools_conf_file -Value $tc_content -Force | Out-Null
    Write-Done
}

function tearDownScript {
    Write-Host "Removing tools.conf: " -NoNewline
    Remove-Item -Path $vmtools_conf_file -Force | Out-Null
    Write-Done

    Write-Host "Removing base config directory: " -NoNewline
    Remove-Item -Path $base_salt_config_location -Recurse -Force
    Write-Done
}

function test_Get-ConfigToolsConf {
    $failed = 0
    $config = Get-ConfigToolsConf
    if ($config["master"] -ne "tc_master") { $failed = 1 }
    if ($config["id"] -ne "tc_minion") { $failed = 1 }
    return $failed
}

function test_Get-ConfigGuestVars {
    $failed = 0
    # We have to try to mock getting guestVars
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    $config = Get-ConfigGuestVars
    if ($config["master"] -ne "gv_master") { $failed = 1 }
    if ($config["id"] -ne "gv_minion") { $failed = 1 }
    return $failed
}

function test-Get-ConfigCLI {
    $failed = 0
    $ConfigOptions = @("master=cli_master"; "id=cli_minion")
    $config = Get-ConfigCLI
    if ($config["master"] -ne "cli_master") { $failed = 1 }
    if ($config["id"] -ne "cli_minion") { $failed = 1 }
    return $failed
}

function test_Get-MinionConfig_tools.conf {
    # tools.conf should superced guestVars
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    function Read-IniContent { @{ salt_minion = @{ master = "tc_master" } } }

    $failed = 0
    $config = Get-MinionConfig
    if ($config["master"] -ne "tc_master") { $failed = 1 }
    if ($config["id"] -ne "gv_minion") { $failed = 1 }
    return $failed
}

function test_Get-MinionConfig_guestVars {
    # Least precedence
    $failed = 0
    # modify guestvars function
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    # modify ini content so that we get all the guestVars
    function Read-IniContent { @{} }
    # Clear CLI
    $ConfigOptions = $null
    $config = Get-MinionConfig

    if ($config["master"] -ne "gv_master") {$failed = 1}
    if ($config["id"] -ne "gv_minion") { $failed = 1 }
    return $failed
}

function test_Get-MinionConfig_CLI {
    $failed = 0
    # We have to try to mock getting guestVars
    function Get-GuestVars { "master=gv_master" }
    # We have to try to mock getting tools.conf
    function Read-IniContent { @{ salt_minion = @{ master = "tc_master" } } }
    # Set the CLI Options by defining ConfigOptions
    $ConfigOptions = @("master=cli_master"; "id=cli_minion")
    $config = Get-MinionConfig
    if ($config["master"] -ne "cli_master") { $failed = 1 }
    if ($config["id"] -ne "cli_minion") { $failed = 1 }
    return $failed
}

function test_Add-MinionConfig {
    # We have to try to mock getting guestVars
    function Get-GuestVars { "master=gv_master id=gv_minion" }
    # We have to try to mock getting ini values
    function Read-IniContent { @{ salt_minion = @{ master = "tc_master"; master_port="1234" } } }
    # Set CLI Options
    $ConfigOptions = @("root_dir=cli_root_dir")
    Add-MinionConfig
    $content = Get-Content $salt_config_file
    if (!($content -like "*created by vmtools salt script*")) { return 1 }
    if (!($content -like "*id: gv_minion*")) { return 1 }
    if (!($content -like "*root_dir: $salt_root_dir*")) { return 1 }
    if (!($content -like "*log_file: $salt_log_dir\minion*")) { return 1 }
    if (!($content -like "*master: tc_master*")) { return 1 }
    if (!($content -like "*master_port: 1234*")) { return 1 }
    return 0
}
