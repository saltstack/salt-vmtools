function Get-MajorVersionsUnderTest {
    $env_value = $env:SALT_TEST_VERSION
    if (-not $env_value) {
        # Local ad-hoc run: exercise every major Salt version under test.
        return @(Get-SaltTestVersionPairs | ForEach-Object { $_.Major })
    }
    if ($env_value -match '^\d+$') {
        return @($env_value)
    }
    # Exact-version or upgrade-step job - major-version install isn't its concern.
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

function test_install_major_versions {
    $majors = Get-MajorVersionsUnderTest
    if ($majors.Count -eq 0) {
        Write-Host "Skipped - this job does not cover major-version installs"
        return 0
    }

    $failed = 0
    foreach ($major in $majors) {
        Write-Host ""
        Write-Host "Testing major version: $major"

        $MinionVersion = $major
        function Get-GuestVars { "master=gv_master id=gv_minion" }
        Write-Host "Installing salt ($MinionVersion): " -NoNewline
        Install *> $null
        Write-Done

        # This is kind of using the script itself to test the script... maybe
        # need to get the latest version a different way
        $versions = Get-AvailableVersions
        $expected_version = $versions[$major]

        try {
            $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
        } catch {
            $current_status = $STATUS_CODES["notInstalled"]
        }
        if ($current_status -ne $STATUS_CODES["installed"]) {
            $failed = 1; Write-Host "FAILED ($major): status not installed"
        }

        if (!(Test-Path $ssm_bin)) { $failed = 1; Write-Host "FAILED ($major): ssm binary missing" }
        if (!(Test-Path "$salt_dir\salt-call.exe")) { $failed = 1; Write-Host "FAILED ($major): salt-call.exe missing" }
        if (!(Test-Path "$salt_dir\salt-minion.exe")) { $failed = 1; Write-Host "FAILED ($major): salt-minion.exe missing" }

        $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
        if (!($service)) { $failed = 1; Write-Host "FAILED ($major): service not registered" }
        elseif ($service.Status -ne "Running") { $failed = 1; Write-Host "FAILED ($major): service not running" }

        if (!(Test-Path $salt_config_file)) { $failed = 1; Write-Host "FAILED ($major): config missing" }

        $minion_not_found = 1
        $master_not_found = 1
        foreach ($line in Get-Content $salt_config_file) {
            if ($line -match "^id: gv_minion$") { $minion_not_found = 0 }
            if ($line -match "^master: gv_master$") { $master_not_found = 0 }
        }
        if ($minion_not_found -or $master_not_found) {
            $failed = 1; Write-Host "FAILED ($major): config incorrect"
        }

        $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
        $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
        if (!($current_path -like "*$salt_dir*")) {
            $failed = 1; Write-Host "FAILED ($major): salt not added to path"
        }

        $result = & "$salt_dir\salt-call" --local test.ping
        if (!($result -like "local:*") -or !($result -like "*True")) {
            $failed = 1; Write-Host "FAILED ($major): salt-call test.ping failed"
        }

        $result = & "$salt_dir\salt-call" --version
        if (!($result -like "*$expected_version*")) {
            $failed = 1
            Write-Host "FAILED ($major): expected version $expected_version, got: $result"
        }

        Write-Host "Resetting environment: " -NoNewline
        Reset-Environment *> $null
        Write-Done
    }
    return $failed
}
