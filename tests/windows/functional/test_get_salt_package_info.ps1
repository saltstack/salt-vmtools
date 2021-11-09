function test_Get-SaltPackageInfo_latest {
    function Convert-PSObjectToHashtable {
        return @{
            latest = @{
                "salt-3003.3-1-linux-amd64.tar.gz" = @{
                    name = "salt-3003.3-1-linux-amd64.tar.gz"
                    version = "3003.3-1"
                    SHA512 = "longstringof123andABC1"
                }
                "salt-3003.3-1-windows-amd64.zip" = @{
                    name = "salt-3003.3-1-windows-amd64.zip"
                    version = "3003.3-1"
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
        }
    }
    $MinionVersion = "latest"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ($test.url -ne "https://repo.saltproject.io/salt/vmware-tools-onedir/3003.3-1/salt-3003.3-1-windows-amd64.zip") { $failed = 1 }
    if ($test.hash -ne "longstringof123andABC2") { $failed = 1 }
    if ($test.file_name -ne "salt-3003.3-1-windows-amd64.zip") { $failed = 1 }
    return $failed
}

function test_Get-SaltPackageInfo_version{

    function Convert-PSObjectToHashtable {
        return @{
            latest = @{
                "salt-3003.3-1-linux-amd64.tar.gz" = @{
                    name = "salt-3003.3-1-linux-amd64.tar.gz"
                    version = "3003.3-1"
                    SHA512 = "longstringof123andABC1"
                }
                "salt-3003.3-1-windows-amd64.zip" = @{
                    name = "salt-3003.3-1-windows-amd64.zip"
                    version = "3003.3-1"
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
        }
    }
    $MinionVersion = "3004-1"
    $test = Get-SaltPackageInfo -MinionVersion $MinionVersion
    $failed = 0
    if ($test.url -ne "https://repo.saltproject.io/salt/vmware-tools-onedir/3004-1/salt-3004-1-windows-amd64.zip") { $failed = 1 }
    if ($test.hash -ne "longstringof123andABC4") { $failed = 1 }
    if ($test.file_name -ne "salt-3004-1-windows-amd64.zip") { $failed = 1 }
    return $failed
}
