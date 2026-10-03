# Tests for Get-MainExitCode. VMware Tools relies on the exit code of the script
# (0, 100 - 107, 126, 130), it must be exactly the last value Main returns, even
# if a function Main calls leaks output into Main's return value.

function test_Get-MainExitCode_plain_number {
    function Main { return 100 }
    $code = Get-MainExitCode
    if ($code -isnot [int]) { return 1 }
    if ($code -ne 100) { return 1 }
    return 0
}

function test_Get-MainExitCode_all_codes {
    # Every code VMware Tools gets from this script
    $failed = 0
    foreach ($expected in @(0, 100, 101, 102, 103, 104, 105, 106, 107, 126, 130)) {
        $Script:so_expected = $expected
        function Main { return $Script:so_expected }
        if ((Get-MainExitCode) -ne $expected) {
            Write-Host "Wrong exit code for $expected" -ForegroundColor Red
            $failed = 1
        }
    }
    return $failed
}

function test_Get-MainExitCode_leaked_output_before_non_zero_code {
    # The case this exists for. Something Main calls outputs a value, and the
    # exit code that follows is not 0. Without this the script exits with 0
    function Main {
        "leaked text"
        [PSCustomObject]@{ Name = "salt-minion"; Status = "Running" }
        return 107
    }
    $code = Get-MainExitCode
    if ($code -ne 107) { return 1 }
    return 0
}

function test_Get-MainExitCode_leaked_output_before_zero {
    # What install does today: Get-Service output, then 0
    function Main {
        [PSCustomObject]@{ Name = "salt-minion"; Status = "Running" }
        return 0
    }
    $code = Get-MainExitCode
    if ($code -isnot [int]) { return 1 }
    if ($code -ne 0) { return 1 }
    return 0
}

function test_Get-MainExitCode_nothing_returned {
    # No exit code, the caller reports "Script Terminated"
    function Main { }
    $code = Get-MainExitCode
    if ($null -ne $code) { return 1 }
    return 0
}

function test_exit_with_an_array_is_zero {
    # This is why Get-MainExitCode exists. exit does not fail for an array,
    # it exits with 0, whatever number is in it. If this test fails PowerShell
    # changed and the comment in Get-MainExitCode needs to be updated.
    powershell -NoProfile -Command "exit @('leaked', 107)"
    if ($LASTEXITCODE -ne 0) { return 1 }
    # and the last value works
    powershell -NoProfile -Command "exit (@('leaked', 107) | Select-Object -Last 1)"
    if ($LASTEXITCODE -ne 107) { return 1 }
    return 0
}
