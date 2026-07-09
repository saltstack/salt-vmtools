function Get-UpgradeStepsUnderTest {
    $env_value = $env:SALT_TEST_VERSION
    if (-not $env_value) {
        # Local ad-hoc run: exercise every upgrade step under test.
        return @(Get-SaltTestUpgradeSteps)
    }
    if ($env_value -match '^upgrade-(\d+)$') {
        $to_major = $Matches[1]
        return @(Get-SaltTestUpgradeSteps | Where-Object { $_.ToMajor -eq $to_major })
    }
    # Major-only or exact-version job - upgrade isn't its concern.
    return @()
}

function setUpScript {
    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done
}

function tearDownScript {
    Write-Host "Resetting environment: " -NoNewline
    Reset-Environment *> $null
    Write-Done
}

function test_upgrade_steps {
    $steps = Get-UpgradeStepsUnderTest
    if ($steps.Count -eq 0) {
        Write-Host "Skipped - this job does not cover upgrade testing"
        return 0
    }

    $failed = 0
    foreach ($step in $steps) {
        $start_ver = $step.FromExact
        $upgrade_ver = $step.ToExact
        Write-Host ""
        Write-Host "Testing upgrade: $start_ver -> $upgrade_ver"

        $MinionVersion = $start_ver
        function Get-GuestVars { "master=existing_master id=existing_minion" }
        Write-Host "Installing salt ($MinionVersion): " -NoNewline
        Install *> $null
        Write-Done

        $MinionVersion = $upgrade_ver
        $Upgrade = $true
        Write-Host "Upgrading salt ($MinionVersion): " -NoNewline
        function Get-GuestVars { "master=gv_master id=gv_minion" }
        Install *> $null
        Write-Done
        $Upgrade = $false

        # Only check things that relate to the upgrade itself - binaries
        # present, path, and ping are already covered by the fresh-install
        # tests and don't exercise anything upgrade-specific.
        try {
            $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
        } catch {
            $current_status = $STATUS_CODES["notInstalled"]
        }
        if ($current_status -ne $STATUS_CODES["installed"]) {
            $failed = 1; Write-Host "FAILED ($start_ver -> $upgrade_ver): status not installed"
        }

        $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
        if (!($service)) { $failed = 1; Write-Host "FAILED ($start_ver -> $upgrade_ver): service not registered" }
        elseif ($service.Status -ne "Running") { $failed = 1; Write-Host "FAILED ($start_ver -> $upgrade_ver): service not running" }

        # An upgrade preserves the existing config - the guest vars passed to
        # the upgrade call above are expected to be ignored.
        $minion_not_found = 1
        $master_not_found = 1
        foreach ($line in Get-Content $salt_config_file) {
            if ($line -match "^id: existing_minion$") { $minion_not_found = 0 }
            if ($line -match "^master: existing_master$") { $master_not_found = 0 }
        }
        if ($minion_not_found -or $master_not_found) {
            $failed = 1; Write-Host "FAILED ($start_ver -> $upgrade_ver): config not preserved across upgrade"
        }

        $result = & "$salt_dir\salt-call" --version
        if (!($result -like "*$upgrade_ver*")) {
            $failed = 1
            Write-Host "FAILED ($start_ver -> $upgrade_ver): expected version $upgrade_ver, got: $result"
        }

        Write-Host "Resetting environment: " -NoNewline
        Reset-Environment *> $null
        Write-Done
    }
    return $failed
}
