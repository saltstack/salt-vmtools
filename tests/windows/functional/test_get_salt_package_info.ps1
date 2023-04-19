# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

$online_hash_data = @{
    latest = @{
        "salt-3004-1-linux-amd64.tar.gz" = @{
            name = "salt-3004-1-linux-amd64.tar.gz"
            version = "3004-1"
            SHA512 = "longstringof123andABC1"
        }
        "salt-3004-1-windows-amd64.zip" = @{
            name = "salt-3004-1-windows-amd64.zip"
            version = "3004-1"
            SHA512 = "longstringof123andABC2"
        }
    }
    "3004-1" = @{
        "salt-3004-1-linux-amd64.tar.gz" = @{
            name = "salt-3004-1-linux-amd64.tar.gz"
            version = "3004-1"
            SHA512 = "longstringof123andABC3"
        }
        "salt-3004-1-windows-amd64.zip" = @{
            name = "salt-3004-1-windows-amd64.zip"
            version = "3004-1"
            SHA512 = "longstringof123andABC4"
        }
    }
    "3003.3-1" = @{
        "salt-3003.3-1-linux-amd64.tar.gz" = @{
            name = "salt-3003.3-1-linux-amd64.tar.gz"
            version = "3003.3-1"
            SHA512 = "longstringof123andABC5"
        }
        "salt-3003.3-1-windows-amd64.zip" = @{
            name = "salt-3003.3-1-windows-amd64.zip"
            version = "3003.3-1"
            SHA512 = "longstringof123andABC6"
        }
    }
}

function setUpScript {
    $base_url = "$($pwd.Path)\tests\testarea"
    # By default, git does not clone down symlinks. Instead, they are converted
    # to files. This test requires the latest symlink, so we'll have to create
    # it if it's not a symlink
    $file = Get-Item "$base_url\latest" -Force -ErrorAction SilentlyContinue
    if (!([bool]($file.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
        Remove-Item "$base_url\latest" -Force | Out-Null
        New-Item -ItemType SymbolicLink `
                 -Path "$base_url\latest" `
                 -Target "$base_url\3004-1" | Out-Null
    }
}

function test_Get-SaltPackageInfo_online_default {
    function Convert-PSObjectToHashtable {
        return $online_hash_data
    }
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ($test.url -ne "https://repo.saltproject.io/salt/py3/onedir/3004-1/salt-3004-1-windows-amd64.zip") { $failed = 1 }
    if ($test.hash -ne "longstringof123andABC2") { $failed = 1 }
    if ($test.file_name -ne "salt-3004-1-windows-amd64.zip") { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_online_version{

    function Convert-PSObjectToHashtable {
        return $online_hash_data
    }
    $MinionVersion = "3003.3-1"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ($test.url -ne "https://repo.saltproject.io/salt/vmware-tools-onedir/3003.3-1/salt-3003.3-1-windows-amd64.zip") { $failed = 1 }
    if ($test.hash -ne "longstringof123andABC6") { $failed = 1 }
    if ($test.file_name -ne "salt-3003.3-1-windows-amd64.zip") { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_online_default_no_repo.json{

    function Convert-PSObjectToHashtable {
        return @{}
    }
    # Can't test latest because this is real data
    $MinionVersion = "3006.0"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ($test.url -ne "https://repo.saltproject.io/salt/py3/onedir/minor/3006.0/salt-3006.0-onedir-windows-amd64.zip") { $failed = 1 }
    if ($test.hash -ne "cc27ad5d31cc1dc5084c7e263f0c3834d0aed61344d8ca1d27714dbe5f04971078107d8bcc5c30f9e42223cce6e5ba23e0c169bed27ea2a3a12fc796551f204d") { $failed = 1 }
    if ($test.file_name -ne "salt-3006.0-onedir-windows-amd64.zip") { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_online_version_no_repo.json{

    function Convert-PSObjectToHashtable {
        return @{}
    }
    $MinionVersion = "3003.3-1"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ($test.url -ne "https://repo.saltproject.io/salt/vmware-tools-onedir/3003.3-1/salt-3003.3-1-windows-amd64.zip") { $failed = 1 }
    if ($test.hash -ne "bd4cf7d4e467fc9a3058332ff67f800118d8cdcc91d0cd47171c19fab44ea66dde4252a4544b653cbc8b5b46afd723b961c8a94a695929985dfe0d33e105a3ba") { $failed = 1 }
    if ($test.file_name -ne "salt-3003.3-1-windows-amd64.zip") { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_local_default{
    $base_url = "$($pwd.Path)\tests\testarea"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ($test.url -ne "$($pwd.Path)\tests\testarea/3004-1/salt-3004-1-windows-amd64.zip") { $failed = 1 }
    if ($test.hash -ne "6ac23ad6e8c261964642f98f1d7d38aed265795bbfa5a724eddd044e97246e77663d9e4a5d0d3a487bce4285c05d31a22a69e1c537674222f50bc58c4193a662") { $failed = 1 }
    if ($test.file_name -ne "salt-3004-1-windows-amd64.zip") { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_local_version{
    $base_url = "$($pwd.Path)\tests\testarea"
    $MinionVersion = "3003.3-1"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ($test.url -ne "$($pwd.Path)\tests\testarea/3003.3-1/salt-3003.3-1-windows-amd64.zip") { $failed = 1 }
    if ($test.hash -ne "bd4cf7d4e467fc9a3058332ff67f800118d8cdcc91d0cd47171c19fab44ea66dde4252a4544b653cbc8b5b46afd723b961c8a94a695929985dfe0d33e105a3ba") { $failed = 1 }
    if ($test.file_name -ne "salt-3003.3-1-windows-amd64.zip") { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_local_default_no_repo.json{
    function Convert-PSObjectToHashtable {
        return @{}
    }
    $base_url = "$($pwd.Path)\tests\testarea"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ($test.url -ne "$($pwd.Path)\tests\testarea\latest/salt-3004-1-windows-amd64.zip") { $failed = 1 }
    if ($test.hash -ne "6ac23ad6e8c261964642f98f1d7d38aed265795bbfa5a724eddd044e97246e77663d9e4a5d0d3a487bce4285c05d31a22a69e1c537674222f50bc58c4193a662") { $failed = 1 }
    if ($test.file_name -ne "salt-3004-1-windows-amd64.zip") { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_local_version_no_repo.json{
    function Convert-PSObjectToHashtable {
        return @{}
    }
    $base_url = "$($pwd.Path)\tests\testarea"
    $MinionVersion = "3003.3-1"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ($test.url -ne "$($pwd.Path)\tests\testarea\3003.3-1/salt-3003.3-1-windows-amd64.zip") { $failed = 1 }
    if ($test.hash -ne "bd4cf7d4e467fc9a3058332ff67f800118d8cdcc91d0cd47171c19fab44ea66dde4252a4544b653cbc8b5b46afd723b961c8a94a695929985dfe0d33e105a3ba") { $failed = 1 }
    if ($test.file_name -ne "salt-3003.3-1-windows-amd64.zip") { $failed = 1 }
    return $failed
}
