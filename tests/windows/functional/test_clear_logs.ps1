# Copyright (c) 2021 VMware, Inc. All rights reserved.

function setUpScript {
    if (!(Test-Path($script_log_dir))) {
        Write-Host "Creating log dir: " -NoNewline
        New-Item -Path $script_log_dir -ItemType Directory | Out-Null
        Write-Done
    }

    Write-Host "Creating 12 log files: " -NoNewline
    1..12 | foreach {
        $script_date = Get-Date -Format "yyyyMMddHHmmss"
        $file_name = "$script_log_base_name-$script_date$_.log" -f "twelve"
        New-Item -Path $script_log_dir\$file_name
    } | Out-Null
    Write-Done

    Write-Host "Creating 10 log files: " -NoNewline
    1..10 | foreach {
        $script_date = Get-Date -Format "yyyyMMddHHmmss"
        $file_name = "$script_log_base_name-$script_date$_.log" -f "ten"
        New-Item -Path $script_log_dir\$file_name
    } | Out-Null
    Write-Done

    Write-Host "Creating 9 log files: " -NoNewline
    1..9 | foreach {
        $script_date = Get-Date -Format "yyyyMMddHHmmss"
        $file_name = "$script_log_base_name-$script_date$_.log" -f "nine"
        New-Item -Path $script_log_dir\$file_name
    } | Out-Null
    Write-Done

    Write-Host "Creating 1 log file: " -NoNewline
    $script_date = Get-Date -Format "yyyyMMddHHmmss"
    $file_name = "$script_log_base_name-$script_date.log" -f "one"
    New-Item -Path $script_log_dir\$file_name | Out-Null
    Write-Done

}

function tearDownScript {
    $files = Get-ChildItem $script_log_dir -Filter "vmware-svtminion*"
    Write-Host "Removing $($files.Count) files: " -NoNewline
    foreach ($file in $files) {
        Remove-Item -Path $file.FullName -Force
    }
    Write-Done
}

function setUp {
    $Script:log_cleared = $false
}

function test_Clear-OldLogs_none {
    # This one just shouldn't throw an error
    $Action = "none"
    Clear-OldLogs
    if ($Script:log_cleared) { return 0 }
    return 1
}

function test_Clear-OldLogs_one {
    $Action = "one"
    Clear-OldLogs
    $filter = "*$script_log_base_name*.log" -f $Action.ToLower()
    $files = Get-ChildItem $script_log_dir -Filter $filter
    if ($files.Count -eq 1) { return 0 }
    return 1
}

function test_Clear-OldLogs_nine {
    $Action = "nine"
    Clear-OldLogs
    $filter = "*$script_log_base_name*.log" -f $Action.ToLower()
    $files = Get-ChildItem $script_log_dir -Filter $filter
    if ($files.Count -eq 9) { return 0 }
    return 1
}

function test_Clear-OldLogs_ten {
    $Action = "ten"
    Clear-OldLogs
    $filter = "*$script_log_base_name*.log" -f $Action.ToLower()
    $files = Get-ChildItem $script_log_dir -Filter $filter
    if ($files.Count -eq 9) { return 0 }
    return 1
}

function test_Clear-OldLogs_twelve {
    $Action = "twelve"
    Clear-OldLogs
    $filter = "*$script_log_base_name*.log" -f $Action.ToLower()
    $files = Get-ChildItem $script_log_dir -Filter $filter
    if ($files.Count -eq 9) { return 0 }
    return 1
}
