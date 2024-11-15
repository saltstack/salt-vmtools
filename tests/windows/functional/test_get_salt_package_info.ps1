# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

function setUpScript {
    $base_url = "$($pwd.Path)\tests\testarea"
}

function test_Get-SaltPackageInfo_online_default {
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $exp_name = "salt-$($test.version)-onedir-windows-amd64.zip"
    $exp_url = "$base_url/$($test.version)/$exp_name"
    $failed = 0
    if ( $test.version -notmatch "\d{4}\.\d{1,2}" ) { $failed = 1}
    if ( $test.hash.Length -ne 64 ) { $failed = 1 }
    if ( $test.file_name -ne $exp_name) { $failed = 1 }
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_online_version{
    $MinionVersion = "3006.1"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $exp_name = "salt-$($test.version)-onedir-windows-amd64.zip"
    $exp_url = "$base_url/$($test.version)/$exp_name"
    $failed = 0
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    if ( $test.hash.Length -ne 64 ) { $failed = 1 }
    if ( $test.file_name -ne $exp_name ) { $failed = 1 }
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_online_major_version{
    $MinionVersion = "3006"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $exp_name = "salt-$($test.version)-onedir-windows-amd64.zip"
    $exp_url = "$base_url/$($test.version)/$exp_name"
    $failed = 0
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    if ( $test.hash.Length -ne 64 ) { $failed = 1 }
    if ( $test.file_name -ne $exp_name ) { $failed = 1 }
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_local_default{
    $base_url = "$($pwd.Path)\tests\testarea"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $exp_name = "salt-$($test.version)-onedir-windows-amd64.zip"
    $exp_url = "$base_url/$($test.version)/$exp_name"
    $failed = 0
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    if ( $test.hash.Length -ne 64 ) { $failed = 1 }
    if ( $test.file_name -ne $exp_name ) { $failed = 1 }
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_local_version{
    $base_url = "$($pwd.Path)\tests\testarea"
    $MinionVersion = "3006.1"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $exp_name = "salt-$($test.version)-onedir-windows-amd64.zip"
    $exp_url = "$base_url/$($test.version)/$exp_name"
    $failed = 0
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    if ( $test.hash.Length -ne 64 ) { $failed = 1 }
    if ( $test.file_name -ne $exp_name ) { $failed = 1 }
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_local_major_version{
    $base_url = "$($pwd.Path)\tests\testarea"
    $MinionVersion = "3006"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $exp_name = "salt-$($test.version)-onedir-windows-amd64.zip"
    $exp_url = "$base_url/$($test.version)/$exp_name"
    $failed = 0
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    if ( $test.hash.Length -ne 64 ) { $failed = 1 }
    if ( $test.file_name -ne $exp_name ) { $failed = 1 }
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    return $failed
}
