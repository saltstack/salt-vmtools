# Copyright (c) 2021 VMware, Inc. All rights reserved.

function test_Get-SaltFromWeb {
    $failed = 0

    Get-SaltFromWeb
    $web_file = "$base_salt_install_location\$salt_web_file_name"
    if (!(Test-Path -Path $web_file)) { $failed = 1 }

    $hash_file = "$base_salt_install_location\$salt_hash_name"
    if (!(Test-Path -Path $hash_file)) { $failed = 1 }

    $exp_hash = Get-HashFromFile $hash_file $salt_web_file_name
    $file_hash = (Get-FileHash -Path $web_file -Algorithm SHA512).Hash
    if ($file_hash -notlike $exp_hash) { Write-Failed; $failed = 1 }

    return $failed
}

function test_Expand-ZipFile {
    $failed = 0

    Get-SaltFromWeb
    $web_file = "$base_salt_install_location\$salt_web_file_name"
    Expand-ZipFile -ZipFile $web_file -Destination $base_salt_install_location
    if (!(Test-Path -Path $salt_bin)) { $failed = 1 }

    if (!(Test-Path -Path $ssm_bin)) { $failed = 1 }

    return $failed
}
