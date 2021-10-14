# Copyright (c) 2021 VMware, Inc. All rights reserved.

<#
.SYNOPSIS
Script for running tests for the VMtools Windows salt-minion script

.DESCRIPTION
This script runs the test suite for the VMtools Windows salt-minion script. If
run without any parameters the functional tests will run. Pass the -Integration
option to run the integration tests.

.NOTES
This Script must be run from the root of the project

This script must be run using powershell -file

.EXAMPLE
PS>powershell -file .\tests\windows\runtests.ps1

.EXAMPLE
PS>powershell -file .\tests\windows\runtests.ps1 -Integration

.EXAMPLE
PS>powershell -file .\tests\windows\runtests.ps1 -Man
PS>powershell -file .\tests\windows\runtests.ps1 -h

.EXAMPLE
PS>powershell -file .\tests\windows\runtests.ps1 -Path .\tests\windows\functional\test_config.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [Alias("p")]
    # This allows you to run the tests in a single file instead of running the
    # entire test suite.
    [String] $Path,

    [Parameter(Mandatory=$false)]
    [Alias("i")]
    # Functional tests are run by default. Pass this switch to run the
    # integration tests.
    [Switch] $Integration,

    [Parameter(Mandatory=$false)]
    [Alias("h")]
    # Display help
    [Switch] $Help
)
if ($Help) {
    # Get the full script name
    $this_script = & {$myInvocation.ScriptName}
    Get-Help $this_script -Detailed
    exit 0
}
$ProgressPreference = "SilentlyContinue"
Import-Module .\tests\windows\helpers.ps1

$vmtools_base_reg = "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools"
$vmtools_base_path = "C:\temp_test"
New-Item -Path $vmtools_base_reg -Force | Out-Null
New-ItemProperty -Path $vmtools_base_reg -Name InstallPath -Value "$vmtools_base_path" -Force | Out-Null
New-Item -Path "$vmtools_base_path" -ItemType directory -Force | Out-Null
New-Item -Path "$vmtools_base_path\vmtoolsd.exe" -ItemType file -Force | Out-Null

$Action = "test"
Import-Module .\windows\svtminion.ps1
# Suppress error messages
$log_level_value = 0

$Script:total_tests = 0
$failed_tests = [System.Collections.ArrayList]::new()

function Run-TestFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )

    # Load current functions
    $current_functions = Get-ChildItem function:

    # Import the test file
    Import-Module "$Path"

    # Get a list of functions inside the script
    $script_functions = Get-ChildItem function: | Where-Object { $current_functions -notcontains $_}

    $short_path = Resolve-Path -Path $Path -Relative
    Write-Header $short_path

    $setUpScript = ($script_functions | Select-Object | Where-Object {$_.Name -like "setUpScript" }).Name
    $tearDownScript = ($script_functions | Select-Object | Where-Object {$_.Name -like "tearDownScript" }).Name

    try {
        if ($setUpScript) {
            Write-Header "Setting Things Up (Script)" -Filler "-"
            & $setUpScript
            Write-Header -Filler "-"
        }

        $script_functions | ForEach-Object {
            $setUp = ($script_functions | Select-Object | Where-Object {$_.Name -like "setUp" }).Name
            $tearDown = ($script_functions | Select-Object | Where-Object {$_.Name -like "tearDown" }).Name
            try {
                if ($setUp) {
                    Write-Header "Setting Things Up (Function)" -Filler "-"
                    & $setUp
                }
                if ($_.Name -like "test_*") {
                    Write-Host "$($_.Name): " -NoNewline
                    $individual_test_failed = 0

                    try {
                        $test_success = $false
                        $individual_test_failed = & $_.ScriptBlock
                        $test_success = $true
                        if ($individual_test_failed -ne 0) {
                            $test_success = $false
                        }
                    } finally {
                        $Script:total_tests += 1
                        if (!($test_success)){
                            $failed_tests.Add("$short_path::$($_.Name)") | Out-Null
                            Write-Failed
                        } else {
                            Write-Success
                        }
                    }

                }
            } finally {
                if ($tearDown) {
                    Write-Header "Cleaning Up (Function)" -Filler "-"
                    & $tearDown
                    Write-Header -Filler "-"
                }
            }
        }
    } finally {
        if ($tearDownScript) {
            Write-Header "Cleaning Up (Script)" -Filler "-"
            & $tearDownScript
            Write-Header -Filler "-"
        }
    }

    Write-Status $failed_tests.Count
    if ($failed_tests.Count -gt 0) {
        foreach ($test in $failed_tests) {
            Write-Host $test
        }
    }
    Write-Header
    Write-Host ""
}

function Create-Report {
    Write-Header "TESTING COMPLETE"
    Write-Host "$Script:total_tests Tests Run"
    if ($failed_tests.Count -eq 0) {
        Write-Host "All Tests Completed Successfully" -ForegroundColor Green
    } else {
        Write-Host "Test Failures: $($failed_tests.Count)" -ForegroundColor Red
        Write-Header "Failed Tests" -Filler "-"
        foreach ($test in $failed_tests) {
            Write-Host $test
        }
    }
    Write-Header
}

if ($Path) {
    if (Test-Path -Path $Path) {
        try {
            Run-TestFile -Path $Path
        } finally {
            Create-Report
        }
    } else {
        Write-Host "Invalid path: $Path"
    }
} else {
    if ($Integration) {
        $test_files = Get-ChildItem .\tests\windows\integration\
    } else {
        $test_files = Get-ChildItem .\tests\windows\functional\
    }
    Write-Host "Found $($test_files.Count) test files"
    try {
        $test_files | ForEach-Object {
            if ($_.Name -like "test_*") {
                Run-TestFile -Path $_.FullName
            }
        }
    } finally {
        Create-Report
    }
}

if ($failed_tests.Count -eq 0) {
    exit 0
} else {
    exit 1
}
