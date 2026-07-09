function Get-ExactVersionsUnderTest {
    $env_value = $env:SALT_TEST_VERSION
    if (-not $env_value) {
        # Local ad-hoc run: exercise every exact Salt version under test.
        return @(Get-SaltTestVersionPairs | ForEach-Object { $_.Exact })
    }
    if ($env_value -match '^(\d+)-(\d+)$') {
        return @("$($Matches[1]).$($Matches[2])")
    }
    # Major-only or upgrade-step job - exact-version install isn't its concern.
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

function test_install_exact_versions {
    $exact_versions = Get-ExactVersionsUnderTest
    if ($exact_versions.Count -eq 0) {
        Write-Host "Skipped - this job does not cover exact-version installs"
        return 0
    }

    $failed = 0
    foreach ($test_version in $exact_versions) {
        Write-Host ""
        Write-Host "Testing exact version: $test_version"

        $MinionVersion = $test_version
        function Get-GuestVars { "master=gv_master id=gv_minion" }
        Write-Host "Installing salt ($MinionVersion): " -NoNewline
        Install *> $null
        Write-Done

        try {
            $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
        } catch {
            $current_status = $STATUS_CODES["notInstalled"]
        }
        if ($current_status -ne $STATUS_CODES["installed"]) {
            $failed = 1; Write-Host "FAILED ($test_version): status not installed"
        }

        if (!(Test-Path $ssm_bin)) { $failed = 1; Write-Host "FAILED ($test_version): ssm binary missing" }
        if (!(Test-Path "$salt_dir\salt-call.exe")) { $failed = 1; Write-Host "FAILED ($test_version): salt-call.exe missing" }
        if (!(Test-Path "$salt_dir\salt-minion.exe")) { $failed = 1; Write-Host "FAILED ($test_version): salt-minion.exe missing" }

        $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
        if (!($service)) { $failed = 1; Write-Host "FAILED ($test_version): service not registered" }
        elseif ($service.Status -ne "Running") { $failed = 1; Write-Host "FAILED ($test_version): service not running" }

        if (!(Test-Path $salt_config_file)) { $failed = 1; Write-Host "FAILED ($test_version): config missing" }

        $minion_not_found = 1
        $master_not_found = 1
        foreach ($line in Get-Content $salt_config_file) {
            if ($line -match "^id: gv_minion$") { $minion_not_found = 0 }
            if ($line -match "^master: gv_master$") { $master_not_found = 0 }
        }
        if ($minion_not_found -or $master_not_found) {
            $failed = 1; Write-Host "FAILED ($test_version): config incorrect"
        }

        $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
        $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
        if (!($current_path -like "*$salt_dir*")) {
            $failed = 1; Write-Host "FAILED ($test_version): salt not added to path"
        }

        $result = & "$salt_dir\salt-call" --local test.ping
        if (!($result -like "local:*") -or !($result -like "*True")) {
            $failed = 1; Write-Host "FAILED ($test_version): salt-call test.ping failed"
        }

        $result = & "$salt_dir\salt-call" --version
        if (!($result -like "*$test_version*")) {
            $failed = 1
            Write-Host "FAILED ($test_version): expected version $test_version, got: $result"
        }

        Write-Host "Resetting environment: " -NoNewline
        Reset-Environment *> $null
        Write-Done
    }
    return $failed
}
