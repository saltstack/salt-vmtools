function setUpScript {
    $base_url = "$($pwd.Path)\tests\testarea"
}

# Since this one is going out and getting the actual latest, we don't know
# exactly what it will return. So, we're just checking that it returned
# something and that it got a hash, filename, and url
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

function test_Get-SaltPackageInfo_online_exact_version{
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
    if ( $test.version -ne $MinionVersion ) { $failed = 1 }
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
    if ( $test.version -ne "3006.10" ) { $failed = 1 }
    $exp_name = "salt-$($test.version)-onedir-windows-amd64.zip"
    $exp_url = "$base_url/$($test.version)/$exp_name"
    $failed = 0
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    if ( $test.hash.Length -ne 64 ) { $failed = 1 }
    if ( $test.file_name -ne $exp_name ) { $failed = 1 }
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    return $failed
}

# testarea includes 3006.10 (GA) and 3006.10rc1 (prerelease). Global "latest"
# stays 3007.1; major "3006" picks GA 3006.10; exact "3006.10rc1" picks the RC dir.
function test_Get-SaltPackageInfo_local_latest_unchanged_when_rc_not_highest_ga {
    $base_url = "$($pwd.Path)\tests\testarea"
    $MinionVersion = "latest"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ( $test.version -ne "3007.1" ) { $failed = 1 }
    $exp_name = "salt-$($test.version)-onedir-windows-amd64.zip"
    $exp_url = "$base_url/$($test.version)/$exp_name"
    if ( $test.file_name -ne $exp_name ) { $failed = 1 }
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    if ( $test.hash.Length -ne 64 ) { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_local_major_3006_resolves_to_ga_not_rc {
    $base_url = "$($pwd.Path)\tests\testarea"
    $MinionVersion = "3006"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ( $test.version -ne "3006.10" ) { $failed = 1 }
    $exp_name = "salt-$($test.version)-onedir-windows-amd64.zip"
    $exp_url = "$base_url/$($test.version)/$exp_name"
    if ( $test.file_name -ne $exp_name ) { $failed = 1 }
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    if ( $test.hash.Length -notin 0, 64 ) { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_local_exact_rc_version {
    $base_url = "$($pwd.Path)\tests\testarea"
    $MinionVersion = "3006.10rc1"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ( $test.version -ne "3006.10rc1" ) { $failed = 1 }
    $exp_name = "salt-$($test.version)-onedir-windows-amd64.zip"
    $exp_url = "$base_url/$($test.version)/$exp_name"
    if ( $test.file_name -ne $exp_name ) { $failed = 1 }
    if ( $test.url -ne $exp_url ) { $failed = 1 }
    if ( $test.hash.Length -notin 0, 64 ) { $failed = 1 }
    return $failed
}
