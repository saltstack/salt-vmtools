# Copyright (c) 2023 VMware, Inc. All rights reserved.

$hash_dir= "$env:Temp\HashDir"
$hash_file = "$env:Temp\HashFile.txt"

function setUpScript {
    Write-Host "Creating test hash objects: " -NoNewline
    New-Item -Path $hash_dir -ItemType Directory -Force | Out-Null
    New-Item -Path $hash_file -ItemType File -Force | Out-Null
    Set-Content -Path $hash_file -Value "Some test data"
    Write-Done
}

function tearDownScript {
    if (Test-Path -Path "$hash_dir") {
        Write-Host "Removing $($hash_dir): " -NoNewline
        Remove-Item -Path "$hash_dir" -Force -Recurse
        Write-Done
    }
    if (Test-Path -Path "$hash_file") {
        Write-Host "Removing $($hash_file): " -NoNewline
        Remove-Item -Path "$hash_file" -Force
        Write-Done
    }
}

function test_Get-FileHash_missing_file {
    $hash = Get-FileHash -Path "$env:Temp\missing.txt"
    if ($hash.Count -eq 0) { return 0 } else { return 1 }
}

function test_Get-FileHash_directory {
    $hash = Get-FileHash -Path $hash_dir
    if ($hash.Count -eq 0) { return 0 } else { return 1 }
}

function test_Get-FileHash_sha1 {
    $expected = "6E50BA56085F66BEE024AD0A001296CCEDB8FA96"
    $hash = Get-FileHash -Path $hash_file -Algorithm SHA1
    if ($hash.Hash -eq $expected) { return 0 } else { return 1 }
}

function test_Get-FileHash_sha256 {
    $expected = "D84C4F0AB044EEDEC68DB4C6DBF2FB6BE7F11930E17801F4FADAC2C2E6CE188D"
    $hash = Get-FileHash -Path $hash_file -Algorithm SHA256
    if ($hash.Hash -eq $expected) { return 0 } else { return 1 }
}

function test_Get-FileHash_sha384 {
    $expected = "E6364BE47DD307A5A4408EAC50172B865BA42F89C51BF4BFB7E660161839165974A506EA31E9618F88D9280B488FB372"
    $hash = Get-FileHash -Path $hash_file -Algorithm SHA384
    if ($hash.Hash -eq $expected) { return 0 } else { return 1 }
}

function test_Get-FileHash_sha512 {
    $expected = "8400A24D71F4BD5B6C673F393C4637176DD2BD4750300167B396926E929AA85477D7939A83C62E2840A81B8150E294BD303FC04040E3FFA221D3FF2280E6E86A"
    $hash = Get-FileHash -Path $hash_file -Algorithm SHA512
    if ($hash.Hash -eq $expected) { return 0 } else { return 1 }
}

function test_Get-FileHash_md5 {
    $expected = "9191A032DD46B6FF1CD157522AE9056D"
    $hash = Get-FileHash -Path $hash_file -Algorithm MD5
    if ($hash.Hash -eq $expected) { return 0 } else { return 1 }
}

function test_Get-FileHash_ripemd160 {
    $expected = "2A9E791684958676A262B0F506D9219D6820891B"
    $hash = Get-FileHash -Path $hash_file -Algorithm RIPEMD160
    if ($hash.Hash -eq $expected) { return 0 } else { return 1 }
}

function test_Get-FileHash_mactripledes {
    # Because this doesn't allow us to pass a key, this will always be a
    # different number, so we're just checking that something was returned
    $hash = Get-FileHash -Path $hash_file -Algorithm MACTripleDES
    if ($hash.Hash.Count -eq 0) { return 1 } else { return 0 }
}
