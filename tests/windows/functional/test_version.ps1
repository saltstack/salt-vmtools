# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function test_Version {
    $test_version = Get-Version
    if ( $env:CI_COMMIT_TAG ) {
        $expected = $env:CI_COMMIT_TAG
    } elseif ( $env:CI_COMMIT_SHORT_SHA ) {
        $expected = $env:CI_COMMIT_SHORT_SHA
    } else {
        $expected = "SCRIPT_VERSION_REPLACE"
    }
    if ( $test_version -match "$expected$" ) {
        return 0
    }
    return 1
}
