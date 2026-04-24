# Requires runtests.ps1 setup: Import-Module of svtminion.ps1 (Administrator so
# the script defines functions before its admin gate).

function Test-CalVerHelpersAvailable {
    return (
        (Get-Command Test-SaltOnedirVersionIsGA -ErrorAction SilentlyContinue) -and
        (Get-Command Compare-SaltCalVer -ErrorAction SilentlyContinue)
    )
}

function test_Test-SaltOnedirVersionIsGA {
    if (-not (Test-CalVerHelpersAvailable)) {
        return 1
    }
    $cases = @(
        @{ Version = "3006.24"; Expected = $true }
        @{ Version = "3008.0"; Expected = $true }
        @{ Version = "3006.1"; Expected = $true }
        @{ Version = "3008.0rc1"; Expected = $false }
        @{ Version = "3007.1dev1"; Expected = $false }
        @{ Version = "notaversion"; Expected = $false }
    )
    $failed = 0
    foreach ( $c in $cases ) {
        $got = Test-SaltOnedirVersionIsGA -Version $c.Version
        if ( $got -ne $c.Expected ) {
            $failed = 1
            break
        }
    }
    return $failed
}

function test_Compare-SaltCalVer {
    if (-not (Test-CalVerHelpersAvailable)) {
        return 1
    }
    $cases = @(
        @{ Left = "3007.1"; Right = "3006.24"; Expected = 1 }
        @{ Left = "3006.24"; Right = "3007.1"; Expected = -1 }
        @{ Left = "3006.8"; Right = "3006.8"; Expected = 0 }
        @{ Left = "3006.24"; Right = "3006.8"; Expected = 1 }
        @{ Left = "3006.8"; Right = "3006.24"; Expected = -1 }
        @{ Left = "3008.0"; Right = "3007.99"; Expected = 1 }
    )
    $failed = 0
    foreach ( $c in $cases ) {
        $got = Compare-SaltCalVer -Left $c.Left -Right $c.Right
        if ( $got -ne $c.Expected ) {
            $failed = 1
            break
        }
    }
    return $failed
}
