function setUp {
    # Adding back the registry so we can check the files
    New-Item -Path $vmtools_base_reg -Force | Out-Null
    New-ItemProperty -Path $vmtools_base_reg -Name InstallPath -Value "$vmtools_base_path" -Force | Out-Null
    if (!(Test-Path "$vmtools_base_dir\vmtoolsd.exe")) {
        New-Item -Path "$vmtools_base_path\vmtoolsd.exe" -ItemType file -Force | Out-Null
    }
}

function tearDown {
    if (Test-Path "$vmtools_base_dir\vmtoolsd.exe.bak" ) {
        Move-Item "$vmtools_base_dir\vmtoolsd.exe.bak" "$vmtools_base_path\vmtoolsd.exe"
    }
    if (Test-Path ".\windows\salt-call.bak" ) {
        Move-Item ".\windows\salt-call.bak" ".\windows\salt-call.bat"
    }
    if (Test-Path ".\windows\salt-minion.bak" ) {
        Move-Item ".\windows\salt-minion.bak" ".\windows\salt-minion.bat"
    }
}

function test_Confirm-Dependencies_all_present {
    $result = Confirm-Dependencies
    if ($result -eq $true) { return 0 } else { return 1 }
}

function test_Confirm-Dependencies_missing_reg_key {
    Remove-Item -Path $vmtools_base_reg
    $result = Confirm-Dependencies
    if ($result -eq $false) { return 0 } else { return 1 }
}

function test_Confirm-Dependencies_missing_reg_value {
    Remove-Item -Path $vmtools_base_reg
    New-Item -Path $vmtools_base_reg -Force | Out-Null
    $result = Confirm-Dependencies
    if ($result -eq $false) { return 0 } else { return 1 }
}

function test_Confirm-Dependencies_missing_vmtoolsd.exe {
    Move-Item "$vmtools_base_dir\vmtoolsd.exe" "$vmtools_base_path\vmtoolsd.exe.bak"
    $result = Confirm-Dependencies
    if ($result -eq $false) { return 0 } else { return 1 }
}

function test_Confirm-Dependencies_missing_salt-call.bat {
    Move-Item ".\windows\salt-call.bat" ".\windows\salt-call.bak"
    $result = Confirm-Dependencies
    if ($result -eq $false) { return 0 } else { return 1 }
}

function test_Confirm-Dependencies_missing_salt-minion.bat {
    Move-Item ".\windows\salt-minion.bat" ".\windows\salt-minion.bak"
    $result = Confirm-Dependencies
    if ($result -eq $false) { return 0 } else { return 1 }
}
