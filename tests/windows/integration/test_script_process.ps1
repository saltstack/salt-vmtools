# Run svtminion.ps1 the way VMware Tools does, as its own PowerShell process,
# and check the exit code, which is what VMware Tools gets. The guestVars are
# set through a stand-in vmtoolsd.exe (see New-FakeVmtoolsd in helpers.ps1), so
# this goes through the script's real code for running vmtoolsd.exe and reading
# guestVars, not a mock of it. The same is tested for Linux in
# tests/linux/test-linux.sh.
#
# The packages in tests\testarea are placeholders (only used to find versions),
# so the real installs here use the Broadcom repository, the same as the other
# integration tests. Those tests only run in the jobs for an exact Salt version.

$Script:sp_source = "https://packages.broadcom.com/artifactory/saltproject-generic/onedir"

function Get-ProcessTestVersion {
    # The exact version this job covers, or $null if it does not cover exact
    # installs. Same as test_install_exact_ver.ps1
    $env_value = $env:SALT_TEST_VERSION
    if (-not $env_value) {
        # Local ad-hoc run: use the first exact Salt version under test.
        return (Get-SaltTestVersionPairs | Select-Object -First 1).Exact
    }
    if ($env_value -match '^(\d+)-(\d+)$') {
        return "$($Matches[1]).$($Matches[2])"
    }
    # Major-only or upgrade-step job - exact-version install isn't its concern.
    return $null
}

function setUpScript {
    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done
    Write-Host "Setting up the stand-in vmtoolsd.exe: " -NoNewline
    $Script:sp_fake = Enable-FakeVmtoolsd
    Write-Done
}

function tearDownScript {
    Write-Host "Restoring vmtoolsd.exe: " -NoNewline
    Disable-FakeVmtoolsd $Script:sp_fake
    Write-Done
    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done
}

function Get-ProcessStatus {
    return (Invoke-SvtminionProcess -Arguments @("-Status")).ExitCode
}

function test_process_exit_codes_without_guestvars {
    # The codes VMware Tools is waiting for from a system without Salt
    $cases = @(
        @{ Arguments = @("-Version"); Expected = 0 },
        @{ Arguments = @("-Help"); Expected = 0 },
        @{ Arguments = @("-Depend"); Expected = 0 },
        @{ Arguments = @("-Status"); Expected = $STATUS_CODES["notInstalled"] },
        # No action on the CLI or in guestVars
        @{ Arguments = @(); Expected = $STATUS_CODES["scriptFailed"] },
        # Already removed
        @{ Arguments = @("-Remove"); Expected = 0 }
    )
    $failed = 0
    foreach ($case in $cases) {
        $result = Invoke-SvtminionProcess -Arguments $case.Arguments
        if ($result.ExitCode -ne $case.Expected) {
            Write-Host "FAILED: '$($case.Arguments -join ' ')' exited $($result.ExitCode), expected $($case.Expected)" -ForegroundColor Red
            $failed = 1
        }
    }
    return $failed
}

function test_process_desired_state_from_guestvars {
    # With no parameters the action is the desiredstate guestVar
    $failed = 0
    # absent and status work on a system without Salt, and install nothing
    $result = Invoke-SvtminionProcess -State "absent"
    if ($result.ExitCode -ne 0) {
        Write-Host "FAILED: desiredstate absent exited $($result.ExitCode)" -ForegroundColor Red
        $failed = 1
    }
    $result = Invoke-SvtminionProcess -State "status"
    if ($result.ExitCode -ne $STATUS_CODES["notInstalled"]) {
        Write-Host "FAILED: desiredstate status exited $($result.ExitCode)" -ForegroundColor Red
        $failed = 1
    }
    # Not an action
    $result = Invoke-SvtminionProcess -State "bogus"
    if ($result.ExitCode -ne $STATUS_CODES["scriptFailed"]) {
        Write-Host "FAILED: an invalid desiredstate exited $($result.ExitCode)" -ForegroundColor Red
        $failed = 1
    }
    return $failed
}

function test_process_invalid_script_options_in_guestvars {
    # An invalid value in guestVars exits 126 and installs nothing, whatever
    # the log level, including silent
    $failed = 0
    foreach ($guest_args in @(
            "master=m source=ftp:/bad",
            "loglevel=silent source=http://x/a;id",
            "loglevel=silent minionversion=abc",
            "loglevel=loud")) {
        $result = Invoke-SvtminionProcess -State "present" -GuestArgs $guest_args
        if ($result.ExitCode -ne $STATUS_CODES["scriptFailed"]) {
            Write-Host "FAILED: '$guest_args' exited $($result.ExitCode), expected 126" -ForegroundColor Red
            $failed = 1
        }
        # 126 is also what no action at all gives, make sure it is because the
        # guestVars were read and the value rejected
        if (($result.Output -join "`n") -notmatch "Invalid (Source|MinionVersion|loglevel)") {
            Write-Host "FAILED: '$guest_args' was not rejected for the value" -ForegroundColor Red
            $failed = 1
        }
    }
    if (Test-Path "$salt_dir\salt-call.exe") {
        Write-Host "FAILED: salt was installed" -ForegroundColor Red
        $failed = 1
    }
    return $failed
}

function test_process_invalid_script_options_on_cli {
    # Options on the CLI, followed by a switch, the way VMware Tools passes them
    $failed = 0
    foreach ($cli_args in @(
            @("-Install", "source=notascheme://bad", "-LogLevel", "debug"),
            @("-Install", "loglevel=silent", "source=http://x/a;id"),
            @("-Install", "minionversion=abc", "-LogLevel", "info"))) {
        $result = Invoke-SvtminionProcess -Arguments $cli_args
        if ($result.ExitCode -ne $STATUS_CODES["scriptFailed"]) {
            Write-Host "FAILED: '$($cli_args -join ' ')' exited $($result.ExitCode), expected 126" -ForegroundColor Red
            $failed = 1
        }
        if (($result.Output -join "`n") -notmatch "Invalid (Source|MinionVersion|loglevel)") {
            Write-Host "FAILED: '$($cli_args -join ' ')' was not rejected for the value" -ForegroundColor Red
            $failed = 1
        }
    }
    return $failed
}

function test_process_unreachable_source_in_guestvars {
    # Proves source is used. The default repository works, this one can not,
    # so the script can only fail if guestVars changed the source
    $result = Invoke-SvtminionProcess -State "present" `
        -GuestArgs "master=m source=https://source-must-be-used.invalid/onedir"
    $failed = 0
    # The script exits with 126 inside Install, but the try/finally around Main
    # turns that into 130 (scriptTerminated). Any failure is fine here
    if ($result.ExitCode -eq 0) {
        Write-Host "FAILED: an unreachable source installed Salt" -ForegroundColor Red
        $failed = 1
    }
    # and it failed because it went to that source, not for another reason
    if (($result.Output -join "`n") -notmatch "Failed to get version information") {
        Write-Host "FAILED: the script did not try the source from guestVars" -ForegroundColor Red
        $failed = 1
    }
    if (Test-Path "$salt_dir\salt-call.exe") {
        Write-Host "FAILED: salt was installed" -ForegroundColor Red
        $failed = 1
    }
    # Put the status back to not installed
    Invoke-SvtminionProcess -Arguments @("-Remove") | Out-Null
    return $failed
}

function Test-ProcessInstalledMinion {
    # Check what the script installed, returns the number of failures
    param(
        [String] $ExpectedVersion,
        [String] $ExpectedMaster,
        [String] $ExpectedId
    )
    $failed = 0
    $status = Get-ProcessStatus
    if ($status -ne $STATUS_CODES["installed"]) {
        $failed = 1; Write-Host "FAILED: -Status exited $status, expected 100"
    }
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if (!$service) {
        $failed = 1; Write-Host "FAILED: service not registered"
    } elseif ($service.Status -ne "Running") {
        $failed = 1; Write-Host "FAILED: service not running"
    }
    if (Test-Path "$salt_dir\salt-call.exe") {
        $version = & "$salt_dir\salt-call" --version
        if (!($version -like "*$ExpectedVersion*")) {
            $failed = 1; Write-Host "FAILED: expected version $ExpectedVersion, got: $version"
        }
    } else {
        $failed = 1; Write-Host "FAILED: salt-call.exe missing"
    }
    # The minion config has the minion options and not the script options
    $master_found = $false
    $id_found = $false
    foreach ($line in Get-Content $salt_config_file) {
        if ($line -match "^master: $([regex]::Escape($ExpectedMaster))$") { $master_found = $true }
        if ($line -match "^id: $([regex]::Escape($ExpectedId))$") { $id_found = $true }
        if ($line -match "^(source|minionversion|loglevel):") {
            $failed = 1; Write-Host "FAILED: script option in the minion config: $line"
        }
    }
    if (!$master_found -or !$id_found) {
        $failed = 1; Write-Host "FAILED: minion config incorrect"
    }
    return $failed
}

function test_process_install_and_remove_from_guestvars {
    # What VMware Tools does when it only runs the script: the action is the
    # desiredstate guestVar, and the source, version and minion config are
    # all in the args guestVar
    $test_version = Get-ProcessTestVersion
    if (!$test_version) {
        Write-Host "Skipped - this job does not cover exact-version installs"
        return 0
    }
    $failed = 0

    Write-Host "Installing salt ($test_version from guestVars): " -NoNewline
    $result = Invoke-SvtminionProcess -State "present" -GuestArgs (
        "master=gv_master id=gv_minion source=$Script:sp_source " +
        "minionversion=$test_version loglevel=info")
    Write-Done
    if ($result.ExitCode -ne 0) {
        $failed = 1; Write-Host "FAILED: install exited $($result.ExitCode), expected 0"
    }
    if ((Test-ProcessInstalledMinion -ExpectedVersion $test_version `
            -ExpectedMaster "gv_master" -ExpectedId "gv_minion") -ne 0) { $failed = 1 }

    # Running it again is not an error, and does not change anything
    $result = Invoke-SvtminionProcess -State "present" -GuestArgs (
        "master=other id=other source=$Script:sp_source minionversion=$test_version")
    if ($result.ExitCode -ne 0) {
        $failed = 1; Write-Host "FAILED: second install exited $($result.ExitCode), expected 0"
    }

    $result = Invoke-SvtminionProcess -State "absent"
    if ($result.ExitCode -ne 0) {
        $failed = 1; Write-Host "FAILED: remove exited $($result.ExitCode), expected 0"
    }
    $status = Get-ProcessStatus
    if ($status -ne $STATUS_CODES["notInstalled"]) {
        $failed = 1; Write-Host "FAILED: -Status after remove exited $status, expected 102"
    }
    if (Test-Path "$salt_dir\salt-call.exe") {
        $failed = 1; Write-Host "FAILED: salt was not removed"
    }
    return $failed
}

function test_process_tools_conf_beats_guestvars {
    # tools.conf, with white space around the = and Windows line endings, beats
    # guestVars. VMware Tools adding the guestVars to the CLI is not the case
    # here, so the precedence is the one in the documentation
    $test_version = Get-ProcessTestVersion
    if (!$test_version) {
        Write-Host "Skipped - this job does not cover exact-version installs"
        return 0
    }
    $failed = 0
    $tc_backup = $null
    if (Test-Path $vmtools_conf_file) {
        $tc_backup = [System.IO.File]::ReadAllBytes($vmtools_conf_file)
    }
    try {
        New-Item -Path (Split-Path $vmtools_conf_file) -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllText($vmtools_conf_file,
            "[salt_minion]`r`n  minionversion  =  $test_version`r`n")

        Write-Host "Installing salt ($test_version from tools.conf): " -NoNewline
        # guestVars asks for the newest version, tools.conf has to win
        $result = Invoke-SvtminionProcess -State "present" -GuestArgs (
            "master=gv_master id=gv_minion source=$Script:sp_source minionversion=latest")
        Write-Done
        if ($result.ExitCode -ne 0) {
            $failed = 1; Write-Host "FAILED: install exited $($result.ExitCode), expected 0"
        }
        if ((Test-ProcessInstalledMinion -ExpectedVersion $test_version `
                -ExpectedMaster "gv_master" -ExpectedId "gv_minion") -ne 0) { $failed = 1 }
    } finally {
        if ($null -ne $tc_backup) {
            [System.IO.File]::WriteAllBytes($vmtools_conf_file, $tc_backup)
        } else {
            Remove-Item -Path $vmtools_conf_file -Force -ErrorAction SilentlyContinue
        }
        Invoke-SvtminionProcess -State "absent" | Out-Null
    }
    return $failed
}
