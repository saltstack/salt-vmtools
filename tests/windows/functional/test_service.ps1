# Copyright 2021-2023 VMware, Inc.
# SPDX-License-Identifier: Apache-2

$Script:service_status = $null
$Script:test_service = "CertPropSvc"

function setUpScript {
    # Current status
    Write-Host "Getting original service status: " -NoNewline
    $Script:service_status = (Get-Service -Name $Script:test_service).Status
    Write-Done
}

function tearDownScript {
    # Set it back to Running status if it was running to begin with
    Write-Host "Restoring original service status: " -NoNewline
    if ($Script:service_status -eq "Running") { Start-Service -Name $Script:test_service}
    Write-Done
}

function test_Start-MinionService{
    # Make sure the service is stopped before beginning
    Stop-Service -Name $Script:test_service

    Start-MinionService -ServiceName $Script:test_service
    if ((Get-Service -Name $Script:test_service).Status -eq "Running") { return 0 }
    return 1
}

function test_Stop-MinionService {
    # Make sure the service is started before beginning
    Start-Service -Name $Script:test_service

    Stop-MinionService -ServiceName $Script:test_service
    if ((Get-Service -Name $Script:test_service).Status -eq "Stopped") { return 0 }
    return 1
}
