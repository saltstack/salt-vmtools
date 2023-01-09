# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

$info = Get-SaltPackageInfo -MinionVersion $MinionVersion
$zip_file = "$base_salt_install_location\$($info.file_name)"

function setUpScript {

    Write-Host "Downloading zip file: " -NoNewline
    Get-SaltFromWeb -Url $info.url -Destination $zip_file -Hash $info.hash
    Write-Done

    Write-Host "Expanding zip file: " -NoNewline
    Expand-ZipFile -ZipFile $zip_file -Destination $base_salt_install_location
    Write-Done
}

function tearDownScript {
    if (Test-Path -Path $base_salt_install_location) {
        Write-Host "Removing downloaded and unzipped files: " -NoNewline
        Remove-Item -Path $base_salt_install_location -Force -Recurse
        Write-Done
    }
}

function test_Get-SaltFromWeb_verify_file_present {
    if (!(Test-Path -Path $zip_file)) { return 1 }
    return 0
}

function test_Get-SaltFromWeb_verify_hash_match {
    $file_hash = (Get-FileHash -Path $zip_file -Algorithm SHA512).Hash
    if ($file_hash -notlike $info.hash) { return 1 }
    return 0
}

function test_Expand-ZipFile_salt_binary_present {
    if (!(Test-Path -Path $salt_bin)) { return 1 }
    return 0
}

function test_Expand-ZipFile_ssm_binary_present {
    if (!(Test-Path -Path $ssm_bin)) { return 1 }
    return 0
}
