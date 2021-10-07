function setUpScript {
    # We need to create a tools.conf file with some settings
    $content = @("[salt_minion]"; "master=tc_master"; "id=tc_minion")
    $tc_content = $content -join "`n"
    New-Item -Path $vmtools_conf_file -Value $tc_content -Force | Out-Null
}

function tearDownScript {
    Remove-Item -Path $vmtools_conf_file -Force | Out-Null
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
    function Get-GuestVars { "" }
    $failed = 0
    $config = Get-MinionConfig
    if ($config["master"] -ne "tc_master") { $failed = 1 }
    if ($config["id"] -ne "tc_minion") { $failed = 1 }
    return $failed
}

function test_Get-MinionConfig_guestVars {
    $failed = 0
    # modify guestvars function
    function Get-GuestVars { "master=gv_master" }
    # Clear CLI
    $ConfigOptions = $null
    $config = Get-MinionConfig
    if ($config["master"] -ne "gv_master") {$failed = 1}
    if ($config["id"] -ne "tc_minion") { $failed = 1 }
    return $failed
}

function test_Get-MinionConfig_CLI {
    $failed = 0
    # modify guestvars function
    function Get-GuestVars { "master=gv_master" }
    $ConfigOptions = @("master=cli_master"; "id=cli_minion")
    $config = Get-MinionConfig
    if ($config["master"] -ne "cli_master") { $failed = 1 }
    if ($config["id"] -ne "cli_minion") { $failed = 1 }
    return $failed
}

function test_Add-MinionConfig {
    $failed = 0
    # We have to try to mock getting guestVars
    function Get-GuestVars { "id=gv_minion" }
    # Set CLI Options
    $ConfigOptions = @("root_dir=cli_root_dir")
    Add-MinionConfig
    $content = Get-Content $salt_config_file
    if (!($content -like "*id: gv_minion*")) { $failed = 1 }
    if (!($content -like "*file_roots: C:\ProgramData\Salt Project\salt*")) { $failed = 1 }
    if (!($content -like "*master: tc_master*")) { $failed = 1 }
    if (!($content -like "*root_dir: cli_root_dir*")) { $failed = 1 }
    return $failed
}
