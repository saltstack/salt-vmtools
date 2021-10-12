# Copyright (c) 2021 VMware, Inc. All rights reserved.

$Script:service_status = $null

function setUpScript {
    # Current status
    Write-Host "Getting original service status: " -NoNewline
    $Script:service_status = (Get-Service -Name CertPropSvc).Status
    Write-Done
}

function tearDownScript {
    # Set it back to Running status if it was running to begin with
    Write-Host "Restoring original service status: " -NoNewline
    if ($Script:service_status -eq "Running") { Start-Service -Name CertPropSvc }
    Write-Done
}

function test_Start-MinionService{
    # Make sure the service is stopped before beginning
    Stop-Service -Name CertPropSvc

    Start-MinionService -ServiceName CertPropSvc
    if ((Get-Service -Name CertPropSvc).Status -eq "Running") { return 0 } else { return 1 }
}

function test_Stop-MinionService {
    # Make sure the service is started before beginning
    Start-Service -Name CertPropSvc

    Stop-MinionService -ServiceName CertPropSvc
    if ((Get-Service -Name CertPropSvc).Status -eq "Stopped") { return 0 } else { return 1 }
}
