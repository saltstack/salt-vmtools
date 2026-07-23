function test_Test-SourceParameter {
    $cases = @(
        @{ Source = "https://packages.broadcom.com/artifactory/salt/onedir"; Expected = $true }
        @{ Source = "http://my.server.com/salt"; Expected = $true }
        @{ Source = "ftp://ftp.example.com/salt"; Expected = $true }
        @{ Source = "\\fileserver\salt"; Expected = $true }
        @{ Source = "\\file-server\salt packages"; Expected = $true }
        @{ Source = "C:\salt\repo"; Expected = $true }
        @{ Source = "C:\My Salt Repo"; Expected = $true }
        @{ Source = "https://evil.com/path with spaces"; Expected = $false }
        @{ Source = 'https://evil.com/path`bad'; Expected = $false }
        @{ Source = "https://evil.com/path;bad"; Expected = $false }
        @{ Source = "https://evil.com/path&bad"; Expected = $false }
        @{ Source = "https://evil.com/path|bad"; Expected = $false }
        @{ Source = "https://evil.com/path<bad"; Expected = $false }
        @{ Source = "https://evil.com/path>bad"; Expected = $false }
        @{ Source = "notascheme://bad"; Expected = $false }
        @{ Source = ""; Expected = $false }
        @{ Source = "   "; Expected = $false }
        @{ Source = "\\missingshare"; Expected = $false }
    )
    $failed = 0
    foreach ($c in $cases) {
        $got = Test-SourceParameter -Source $c.Source
        if ($got -ne $c.Expected) {
            Write-Host ""
            Write-Host "Source: '$($c.Source)' Expected: $($c.Expected) Got: $got"
            $failed = 1
        }
    }
    return $failed
}


function test_Test-MinionVersionParameter {
    $cases = @(
        @{ MinionVersion = "latest"; Expected = $true }
        @{ MinionVersion = "3006"; Expected = $true }
        @{ MinionVersion = "3006.2"; Expected = $true }
        @{ MinionVersion = "3006.24"; Expected = $true }
        @{ MinionVersion = "3008.0"; Expected = $true }
        @{ MinionVersion = "3008.0rc1"; Expected = $true }
        @{ MinionVersion = "3009.0rc2"; Expected = $true }
        @{ MinionVersion = "3009.1.2"; Expected = $true }
        @{ MinionVersion = "3008.1-1"; Expected = $true }
        @{ MinionVersion = "3004.2-1"; Expected = $true }
        @{ MinionVersion = "bad version"; Expected = $false }
        @{ MinionVersion = "3006/evil"; Expected = $false }
        @{ MinionVersion = "abc"; Expected = $false }
        @{ MinionVersion = '3006;rm -rf /'; Expected = $false }
        @{ MinionVersion = ""; Expected = $false }
        @{ MinionVersion = "3006 .2"; Expected = $false }
        @{ MinionVersion = "3008.1-1-2"; Expected = $false }
    )
    $failed = 0
    foreach ($c in $cases) {
        $got = Test-MinionVersionParameter -MinionVersion $c.MinionVersion
        if ($got -ne $c.Expected) {
            Write-Host ""
            Write-Host "MinionVersion: '$($c.MinionVersion)' Expected: $($c.Expected) Got: $got"
            $failed = 1
        }
    }
    return $failed
}
