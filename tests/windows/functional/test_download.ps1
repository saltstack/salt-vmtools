# Copyright (c) 2021 VMware, Inc. All rights reserved.

$web_file = "$base_salt_install_location\$salt_web_file_name"
$hash_file = "$base_salt_install_location\$salt_hash_name"

function setUpScript {
    Write-Host "Downloading zip file: " -NoNewline
    Get-SaltFromWeb
    Write-Done

    Write-Host "Expanding zip file: " -NoNewline
    Expand-ZipFile -ZipFile $web_file -Destination $base_salt_install_location
    Write-Done
}

function tearDownScript {
    Write-Host "Removing downloaded and unzipped files: " -NoNewline
    Remove-Item -Path $base_salt_install_location -Force -Recurse
    Write-Done
}

function test_Get-SaltFromWeb_verify_file_present {
    if (!(Test-Path -Path $web_file)) { return 1 }
    return 0
}

function test_Get-SaltFromWeb_verify_hash_file_present {
    if (!(Test-Path -Path $hash_file)) { return 1 }
    return 0
}

function test_Get-SaltFromWeb_verify_hash_match {
    $exp_hash = Get-HashFromFile $hash_file $salt_web_file_name
    $file_hash = (Get-FileHash -Path $web_file -Algorithm SHA512).Hash
    if ($file_hash -notlike $exp_hash) { return 1 }
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
