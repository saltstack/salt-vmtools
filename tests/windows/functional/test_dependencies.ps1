# Copyright (c) 2021 VMware, Inc. All rights reserved.

function setUp {
    # Adding back the registry so we can check the files
    Write-Host "Ensuring registr key present: " -NoNewline
    New-Item -Path $vmtools_base_reg -Force | Out-Null
    New-ItemProperty -Path $vmtools_base_reg -Name InstallPath -Value "$vmtools_base_path" -Force | Out-Null
    Write-Done

}

function tearDown {
    if (!(Test-Path "$vmtools_base_dir\vmtoolsd.exe")) {
        Write-Host "Creating vmtoolsd.exe: " -NoNewline
        New-Item -Path "$vmtools_base_path\vmtoolsd.exe" -ItemType file -Force | Out-Null
        Write-Done
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
    Remove-Item "$vmtools_base_dir\vmtoolsd.exe"
    $result = Confirm-Dependencies
    if ($result -eq $false) { return 0 } else { return 1 }
}
