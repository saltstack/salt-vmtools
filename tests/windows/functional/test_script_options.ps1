# Tests for the script options set using key=value (source, minionversion,
# loglevel) in guestVars, tools.conf and the CLI. The same scenarios are tested
# for the Linux script in tests/linux/test_script_opts.sh, keep them in step.
#
# Get-GuestVars and Read-IniContent are mocked, and the CLI options and the
# action are set locally in each test.

function setUpScript {
    # Get-ConfigToolsConf needs the tools.conf file to exist, the content is
    # mocked in each test by Read-IniContent
    $Script:so_tc_dir = Join-Path $env:TEMP "svtminion_script_options"
    New-Item -Path $Script:so_tc_dir -ItemType Directory -Force | Out-Null
    $Script:so_tc_file = Join-Path $Script:so_tc_dir "tools.conf"
    New-Item -Path $Script:so_tc_file -ItemType File -Force | Out-Null
}

function tearDownScript {
    Remove-Item -Path $Script:so_tc_dir -Recurse -Force
}

function Test-Result {
    # Compare the hash table returned by Get-ScriptOptions to an expected hash
    # table, values are case sensitive. Returns 0 if they match, otherwise 1
    param($Actual, $Expected)
    if ($null -eq $Actual) { return 1 }
    if ($Actual.Count -ne $Expected.Count) { return 1 }
    foreach ($key in $Expected.Keys) {
        if (!$Actual.ContainsKey($key)) { return 1 }
        if ($Actual[$key] -cne $Expected[$key]) { return 1 }
    }
    return 0
}

function test_gv_only {
    # 1. All options are picked up from guestVars
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = $null
    function Get-GuestVars { "master=m source=https://gv.example.com/onedir minionversion=3006.8 loglevel=debug" }
    function Read-IniContent { @{} }
    $result = Get-ScriptOptions
    return Test-Result $result @{
        Source = "https://gv.example.com/onedir"
        MinionVersion = "3006.8"
        LogLevel = "debug"
    }
}

function test_tools_conf_over_gv {
    # 2a. tools.conf beats guestVars, only for the options it sets
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = $null
    function Get-GuestVars { "source=https://gv.example.com/onedir loglevel=info" }
    function Read-IniContent { @{ salt_minion = @{ source = "https://tc.example.com/onedir" } } }
    $result = Get-ScriptOptions
    return Test-Result $result @{
        Source = "https://tc.example.com/onedir"
        LogLevel = "info"
    }
}

function test_cli_over_tools_conf {
    # 2b. CLI key=value beats tools.conf
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = @("source=https://cli.example.com/onedir")
    function Get-GuestVars { "source=https://gv.example.com/onedir" }
    function Read-IniContent { @{ salt_minion = @{ source = "https://tc.example.com/onedir" } } }
    $result = Get-ScriptOptions
    return Test-Result $result @{ Source = "https://cli.example.com/onedir" }
}

function test_parameters_over_key_value {
    # 2c and 10. Explicit parameters, including from a VMware Tools that
    # passes them on the CLI, are not overridden by key=value
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = @("source=https://cli.example.com/onedir", "minionversion=3007", "loglevel=debug")
    function Get-GuestVars { "source=https://gv.example.com/onedir" }
    function Read-IniContent { @{} }
    $result = Get-ScriptOptions -BoundParameters @("Source", "MinionVersion", "LogLevel")
    return Test-Result $result @{}
}

function test_not_in_minion_config {
    # 3. Script options never reach the minion config
    $vmtools_conf_file = $Script:so_tc_file
    $ConfigOptions = @("log_level=trace", "Source=https://cli.example.com/onedir")
    function Get-GuestVars { "master=m source=https://gv.example.com/onedir loglevel=debug" }
    function Read-IniContent { @{ salt_minion = @{ id = "tcid"; MinionVersion = "3006" } } }
    $config = Get-MinionConfig
    if ($config.Count -ne 3) { return 1 }
    if ($config["master"] -cne "m") { return 1 }
    if ($config["id"] -cne "tcid") { return 1 }
    if ($config["log_level"] -cne "trace") { return 1 }
    return 0
}

function test_cli_one_argument {
    # 4a. CLI tokens as one argument
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = "master=m source=https://cli.example.com/onedir"
    function Get-GuestVars { "" }
    function Read-IniContent { @{} }
    $result = Get-ScriptOptions
    return Test-Result $result @{ Source = "https://cli.example.com/onedir" }
}

function test_cli_several_arguments {
    # 4b. CLI tokens as several arguments
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = @("master=m", "source=https://cli.example.com/onedir", "minionversion=3007.1")
    function Get-GuestVars { "" }
    function Read-IniContent { @{} }
    $result = Get-ScriptOptions
    return Test-Result $result @{
        Source = "https://cli.example.com/onedir"
        MinionVersion = "3007.1"
    }
}

function test_cli_after_switch {
    # 4c. Tokens after the next switch are not read
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = @("master=m", "-LogLevel", "debug", "source=https://evil.example.com/onedir")
    function Get-GuestVars { "" }
    function Read-IniContent { @{} }
    $result = Get-ScriptOptions
    return Test-Result $result @{}
}

function test_invalid_values {
    # 5. Invalid values return $null, the script exits with 126
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = $null
    function Read-IniContent { @{} }
    $failed = 0
    foreach ($args_value in @(
            "source=ftp:/bad",
            "source=http://x/a;id",
            "minionversion=abc",
            "loglevel=loud")) {
        $Script:so_args = $args_value
        function Get-GuestVars { $Script:so_args }
        $result = Get-ScriptOptions
        if ($null -ne $result) {
            Write-Host "Not rejected: $args_value" -ForegroundColor Red
            $failed = 1
        }
    }
    return $failed
}

function test_equals_in_value {
    # 6. A value containing = is preserved
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = $null
    function Get-GuestVars { "master=a=b source=https://h.example.com/onedir?a=b" }
    function Read-IniContent { @{} }
    $result = Get-ScriptOptions
    if ((Test-Result $result @{ Source = "https://h.example.com/onedir?a=b" }) -ne 0) { return 1 }
    $config = Get-MinionConfig
    if ($config["master"] -cne "a=b") { return 1 }
    return 0
}

function test_ignored_tokens {
    # 7. Control characters, empty values and tokens without = are ignored,
    # nothing is globbed
    $null_byte = [char]0x01
    $result = _parse_config -KeyValues "master=* id=x empty= bad=a${null_byte}b noequals =novalue"
    if ($result.Count -ne 2) { return 1 }
    if ($result["master"] -cne "*") { return 1 }
    if ($result["id"] -cne "x") { return 1 }
    return 0
}

function test_case_insensitive {
    # 8. Keys and loglevel are not case sensitive
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = $null
    function Get-GuestVars { "Source=https://gv.example.com/onedir MINIONVERSION=3006 LOGLEVEL=DEBUG" }
    function Read-IniContent { @{} }
    $result = Get-ScriptOptions
    return Test-Result $result @{
        Source = "https://gv.example.com/onedir"
        MinionVersion = "3006"
        LogLevel = "debug"
    }
}

function test_not_installing {
    # 9. A non install action ignores source and minionversion, and honors
    # loglevel. Also 12b, a desired state of absent is the remove action
    $vmtools_conf_file = $Script:so_tc_file
    $ConfigOptions = $null
    function Get-GuestVars { "source=https://gv.example.com/onedir minionversion=3006 loglevel=debug" }
    function Read-IniContent { @{} }
    $failed = 0
    foreach ($action_name in @("status", "remove", "reconfig")) {
        $Action = $action_name
        $result = Get-ScriptOptions
        if ((Test-Result $result @{ LogLevel = "debug" }) -ne 0) {
            Write-Host "Failed for action: $action_name" -ForegroundColor Red
            $failed = 1
        }
    }
    return $failed
}

function test_legacy_switch_in_guestvars {
    # 11. A legacy --source in guestVars is ignored
    $vmtools_conf_file = $Script:so_tc_file
    $Action = "install"
    $ConfigOptions = $null
    function Get-GuestVars { "--source https://legacy.example.com/onedir master=m" }
    function Read-IniContent { @{} }
    $result = Get-ScriptOptions
    if ((Test-Result $result @{}) -ne 0) { return 1 }
    $config = Get-MinionConfig
    if ($config.Count -ne 1) { return 1 }
    if ($config["master"] -cne "m") { return 1 }
    return 0
}

function test_desired_state_present_is_install {
    # 12a. When there is no action on the CLI the desired state in guestVars
    # sets it. Main maps present to install, the action source and
    # minionversion apply to
    $vmtools_conf_file = $Script:so_tc_file
    $ConfigOptions = $null
    function Get-GuestVars {
        param($GuestVarsPath)
        if ($GuestVarsPath -like "*.desiredstate") { return "present" }
        return "source=https://gv.example.com/onedir"
    }
    function Read-IniContent { @{} }
    # What Main does with the desired state
    $Action = Get-GuestVars -GuestVarsPath $guestvars_salt_desired_state
    switch ($Action.ToLower()) {
        "present" { $Action = "install" }
        "absent" { $Action = "remove" }
    }
    $result = Get-ScriptOptions
    return Test-Result $result @{ Source = "https://gv.example.com/onedir" }
}

function test_Test-ScriptOptionKey {
    foreach ($key in @("source", "Source", "MINIONVERSION", "loglevel")) {
        if (!(Test-ScriptOptionKey -Key $key)) { return 1 }
    }
    foreach ($key in @("log_level", "master", "sources", "")) {
        if (Test-ScriptOptionKey -Key $key) { return 1 }
    }
    return 0
}

function test_Get-SourceUrls {
    $artifactory = "https://mirror.example.com/artifactory/saltproject-generic/onedir"
    $urls = Get-SourceUrls -SourceLocation $artifactory
    if ($urls["base_url"] -cne $artifactory) { return 1 }
    $api = "https://mirror.example.com/artifactory/api/storage/saltproject-generic/onedir"
    if ($urls["api_url"] -cne $api) { return 1 }

    # Not artifactory, there is no api
    foreach ($location in @(
            "https://mirror.example.com/vmtools/salt",
            "\\server\share\salt",
            "C:\salt\repo")) {
        $urls = Get-SourceUrls -SourceLocation $location
        if ($urls["base_url"] -cne $location) { return 1 }
        if ($urls["api_url"] -cne "") { return 1 }
    }
    return 0
}

function test_Get-ConfigToolsConf_ignores_bad_options {
    # Control characters and empty values are ignored, the rest is returned
    $vmtools_conf_file = $Script:so_tc_file
    function Read-IniContent {
        @{
            salt_minion = @{
                master = "m"
                bad = "a$([char]0x01)b"
                empty = ""
                source = "https://tc.example.com/onedir"
            }
            other = @{ id = "other_section" }
        }
    }
    $config = Get-ConfigToolsConf
    if ($config.Count -ne 2) { return 1 }
    if ($config["master"] -cne "m") { return 1 }
    if ($config["source"] -cne "https://tc.example.com/onedir") { return 1 }
    return 0
}

function test_Get-ConfigCLI_stops_at_switch {
    # Options end at the next switch, a token starting with -
    $ConfigOptions = @("master=m", "-Foo", "id=x")
    $config = Get-ConfigCLI
    if ($config.Count -ne 1) { return 1 }
    if ($config["master"] -cne "m") { return 1 }
    return 0
}

function test_Get-ConfigCLI_switch_first {
    $ConfigOptions = @("-Foo", "master=m")
    $config = Get-ConfigCLI
    if ($config) { return 1 }
    return 0
}

function test_Get-ConfigCLI_one_argument {
    $ConfigOptions = "master=m  id=x"
    $config = Get-ConfigCLI
    if ($config.Count -ne 2) { return 1 }
    if ($config["master"] -cne "m") { return 1 }
    if ($config["id"] -cne "x") { return 1 }
    return 0
}

function Set-MainMocks {
    # Mocks so Main gets as far as applying the script options and then
    # returns without doing anything to the system. Dot source this so the
    # functions are defined in the caller's scope
    function Confirm-Dependencies { return $true }
    function Find-StandardSaltInstallation { return $false }
    function Get-Status { return $STATUS_CODES["installed"] }
    function Read-IniContent { @{} }
}

function test_Main_applies_script_options {
    # Main applies the options to the script scoped variables used later
    $state = Save-ScriptState
    try {
        $vmtools_conf_file = $Script:so_tc_file
        $ConfigOptions = $null
        $Action = "install"
        $Script:cli_parameters = @()
        $Script:Source = "https://orig.example.com/onedir"
        $Script:MinionVersion = "latest"
        $Script:LogLevel = "warning"
        $Script:log_level_value = 0
        $Script:base_url = "orig"
        $Script:api_url = "orig"
        . Set-MainMocks
        function Get-GuestVars {
            "source=https://mirror.example.com/artifactory/saltproject-generic/onedir minionversion=3007.1 loglevel=error"
        }
        $expected_url = "https://mirror.example.com/artifactory/saltproject-generic/onedir"
        $expected_api = "https://mirror.example.com/artifactory/api/storage/saltproject-generic/onedir"
        $result = Main
        if ($result -ne $STATUS_CODES["scriptSuccess"]) { return 1 }
        if ($Script:Source -cne $expected_url) { return 1 }
        if ($Script:base_url -cne $expected_url) { return 1 }
        if ($Script:api_url -cne $expected_api) { return 1 }
        if ($Script:MinionVersion -cne "3007.1") { return 1 }
        if ($Script:LogLevel -cne "error") { return 1 }
        if ($Script:log_level_value -ne 1) { return 1 }
        return 0
    } finally {
        Restore-ScriptState $state
    }
}

function test_Main_desired_state_present_applies_script_options {
    # No action on the CLI, the action is the desired state in guestVars
    $state = Save-ScriptState
    try {
        $vmtools_conf_file = $Script:so_tc_file
        $ConfigOptions = $null
        $Action = $null
        $Script:cli_parameters = @()
        $Script:Source = "https://orig.example.com/onedir"
        $Script:log_level_value = 0
        . Set-MainMocks
        function Get-GuestVars {
            param($GuestVarsPath)
            if ($GuestVarsPath -like "*.desiredstate") { return "present" }
            return "source=https://gv.example.com/onedir"
        }
        $result = Main
        if ($result -ne $STATUS_CODES["scriptSuccess"]) { return 1 }
        if ($Script:Source -cne "https://gv.example.com/onedir") { return 1 }
        return 0
    } finally {
        Restore-ScriptState $state
    }
}

function test_Main_not_installing_ignores_source {
    # Other actions ignore source and minionversion, but honor loglevel
    $state = Save-ScriptState
    try {
        $vmtools_conf_file = $Script:so_tc_file
        $ConfigOptions = $null
        $Action = "status"
        $Script:cli_parameters = @()
        $Script:Source = "https://orig.example.com/onedir"
        $Script:MinionVersion = "latest"
        $Script:LogLevel = "warning"
        $Script:log_level_value = 0
        . Set-MainMocks
        function Get-GuestVars {
            "source=https://gv.example.com/onedir minionversion=3006 loglevel=error"
        }
        $result = Main
        if ($result -ne $STATUS_CODES["installed"]) { return 1 }
        if ($Script:Source -cne "https://orig.example.com/onedir") { return 1 }
        if ($Script:MinionVersion -cne "latest") { return 1 }
        if ($Script:LogLevel -cne "error") { return 1 }
        return 0
    } finally {
        Restore-ScriptState $state
    }
}

function test_Main_parameters_beat_script_options {
    # An explicit parameter, here -Source, is not overridden
    $state = Save-ScriptState
    try {
        $vmtools_conf_file = $Script:so_tc_file
        $ConfigOptions = $null
        $Action = "install"
        $Script:cli_parameters = @("Source")
        $Script:Source = "https://switch.example.com/onedir"
        $Script:MinionVersion = "latest"
        $Script:log_level_value = 0
        . Set-MainMocks
        function Get-GuestVars {
            "source=https://gv.example.com/onedir minionversion=3007.1"
        }
        $result = Main
        if ($result -ne $STATUS_CODES["scriptSuccess"]) { return 1 }
        if ($Script:Source -cne "https://switch.example.com/onedir") { return 1 }
        if ($Script:MinionVersion -cne "3007.1") { return 1 }
        return 0
    } finally {
        Restore-ScriptState $state
    }
}

function test_Main_invalid_script_option_fails {
    # An invalid value returns scriptFailed and nothing is installed
    $state = Save-ScriptState
    try {
        $vmtools_conf_file = $Script:so_tc_file
        $ConfigOptions = $null
        $Action = "install"
        $Script:cli_parameters = @()
        $Script:Source = "https://orig.example.com/onedir"
        $Script:log_level_value = 0
        . Set-MainMocks
        function Install { throw "Install should not be called" }
        $failed = 0
        foreach ($args_value in @(
                "source=ftp:/bad",
                "minionversion=abc",
                "loglevel=loud")) {
            $Script:so_args = $args_value
            function Get-GuestVars { $Script:so_args }
            $result = Main
            if ($result -ne $STATUS_CODES["scriptFailed"]) {
                Write-Host "Not rejected: $args_value" -ForegroundColor Red
                $failed = 1
            }
            if ($Script:Source -cne "https://orig.example.com/onedir") { $failed = 1 }
        }
        return $failed
    } finally {
        Restore-ScriptState $state
    }
}

function Set-ToolsConfContent {
    # Write a real tools.conf, Read-IniContent is not mocked by these tests
    param([String] $Content)
    [System.IO.File]::WriteAllText($Script:so_tc_file, $Content)
}

function test_tools_conf_white_space {
    # Same as test 23 for Linux: white space around the line, the key and the
    # value is ignored, and CRLF line endings are fine
    $vmtools_conf_file = $Script:so_tc_file
    Set-ToolsConfContent ("[salt_minion]`r`nsource = https://tc.example.com/onedir`r`n" +
                          "  loglevel =  error  `r`n`tmaster`t=`tm`r`n")
    $Action = "install"
    $ConfigOptions = $null
    function Get-GuestVars { "" }
    $result = Get-ScriptOptions
    if ((Test-Result $result @{ Source = "https://tc.example.com/onedir"; LogLevel = "error" }) -ne 0) { return 1 }
    $config = Get-MinionConfig
    if ($config.Count -ne 1) { return 1 }
    if ($config["master"] -cne "m") { return 1 }
    return 0
}

function test_tools_conf_comments_and_sections {
    # Same as tests 24 and 25 for Linux: comment lines are ignored, and only
    # the salt_minion section is read
    $vmtools_conf_file = $Script:so_tc_file
    Set-ToolsConfContent ("# source=https://comment.example.com/onedir`r`n" +
                          "[other]`r`nsource=https://wrong.example.com/onedir`r`n" +
                          "[salt_minion]`r`n; minionversion=3007`r`n, loglevel=debug`r`nid=x`r`n" +
                          "[after]`r`nsource=https://wrong.example.com/onedir`r`n")
    $Action = "install"
    $ConfigOptions = $null
    function Get-GuestVars { "" }
    $result = Get-ScriptOptions
    if ((Test-Result $result @{}) -ne 0) { return 1 }
    $config = Get-MinionConfig
    if ($config.Count -ne 1) { return 1 }
    if ($config["id"] -cne "x") { return 1 }
    return 0
}

function test_tools_conf_value_with_equals {
    # Same as test 26 for Linux
    $vmtools_conf_file = $Script:so_tc_file
    Set-ToolsConfContent "[salt_minion]`r`nmaster = a=b`r`n"
    function Get-GuestVars { "" }
    $ConfigOptions = $null
    $config = Get-MinionConfig
    if ($config["master"] -cne "a=b") { return 1 }
    return 0
}

function test_silent_log_level_does_not_allow_invalid_values {
    # Same as test 21 for Linux
    $vmtools_conf_file = $Script:so_tc_file
    Set-ToolsConfContent "[salt_minion]`r`n"
    $Action = "install"
    $ConfigOptions = $null
    $failed = 0
    foreach ($args_value in @(
            "loglevel=silent source=http://x/a;id",
            "loglevel=silent source=ftp:/bad",
            "loglevel=silent minionversion=abc")) {
        $Script:so_args = $args_value
        function Get-GuestVars { $Script:so_args }
        if ($null -ne (Get-ScriptOptions)) {
            Write-Host "Not rejected: $args_value" -ForegroundColor Red
            $failed = 1
        }
    }
    $Script:so_args = "loglevel=silent source=https://ok.example.com/onedir"
    $result = Get-ScriptOptions
    if ((Test-Result $result @{ LogLevel = "silent"; Source = "https://ok.example.com/onedir" }) -ne 0) {
        $failed = 1
    }
    return $failed
}
