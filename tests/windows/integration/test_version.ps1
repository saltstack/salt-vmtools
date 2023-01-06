# Copyright (c) 2023 VMware, Inc. All rights reserved.

function test_Version {
    $test_version = Get-Version
    if ( $env:CI_COMMIT_TAG ) {
        $expected = $env:CI_COMMIT_TAG
    } else {
        $expected = "SCRIPT_VERSION_REPLACES"
    }
    if ( $test_version -eq $expected ) {
        return 0
    }
    Write-Warning ""
    Write-Warning "Expected: $expected"
    Write-Warning "Found: $test_version"
    return 1
}
