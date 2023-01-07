# Copyright (c) 2023 VMware, Inc. All rights reserved.

# This test now does nothing now that the script no longer depends on
# vmtoolsd.exe. I am leaving it in case we actually do add some dependencies in
# the future

#function setUp {
#    if (!(Test-Path "$vmtools_base_dir\vmtoolsd.exe")) {
#        Write-Host "Ensuring vmtoolsd present: " -NoNewline
#        New-Item -Path "$vmtools_base_path\vmtoolsd.exe" -ItemType file -Force | Out-Null
#        Write-Done
#    }
#
#}
#
#function tearDown {
#    if (!(Test-Path "$vmtools_base_dir\vmtoolsd.exe")) {
#        Write-Host "Ensuring vmtoolsd present: " -NoNewline
#        New-Item -Path "$vmtools_base_path\vmtoolsd.exe" -ItemType file -Force | Out-Null
#        Write-Done
#    }
#}
#
#function test_Confirm-Dependencies_all_present {
#    $result = Confirm-Dependencies
#    if ($result -eq $true) { return 0 } else { return 1 }
#}
#
#function test_Confirm-Dependencies_missing_vmtoolsd.exe {
#    Remove-Item "$vmtools_base_dir\vmtoolsd.exe"
#    $result = Confirm-Dependencies
#    if ($result -eq $false) { return 0 } else { return 1 }
#}
