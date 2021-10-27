# Copyright (c) 2021 VMware, Inc. All rights reserved.

function setUpScript {
    if (!(Test-Path($script_log_dir))) {
        Write-Host "Creating log dir: " -NoNewline
        New-Item -Path $script_log_dir -ItemType Directory | Out-Null
        Write-Done
    }

    Write-Host "Creating $($script_log_file_count + 2) log files: " -NoNewline
    1..$($script_log_file_count + 2) | foreach {
        $script_date = Get-Date -Format "yyyyMMddHHmmss"
        $file_name = "$script_log_base_name-$script_date$_.log" -f $($script_log_file_count + 2)
        New-Item -Path $script_log_dir\$file_name
        Write-Host $file_name
    } | Out-Null
    Write-Done

    Write-Host "Creating $script_log_file_count log files: " -NoNewline
    1..$script_log_file_count | foreach {
        $script_date = Get-Date -Format "yyyyMMddHHmmss"
        $file_name = "$script_log_base_name-$script_date$_.log" -f $script_log_file_count
        New-Item -Path $script_log_dir\$file_name
    } | Out-Null
    Write-Done

    Write-Host "Creating $($script_log_file_count - 1) log files: " -NoNewline
    1..$($script_log_file_count - 1) | foreach {
        $script_date = Get-Date -Format "yyyyMMddHHmmss"
        $file_name = "$script_log_base_name-$script_date$_.log" -f $($script_log_file_count - 1)
        New-Item -Path $script_log_dir\$file_name
    } | Out-Null
    Write-Done

    Write-Host "Creating 1 log file: " -NoNewline
    $script_date = Get-Date -Format "yyyyMMddHHmmss"
    $file_name = "$script_log_base_name-$script_date.log" -f 1
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
    $Action = [String]1
    Clear-OldLogs
    $filter = "*$script_log_base_name*.log" -f $Action.ToLower()
    $files = Get-ChildItem $script_log_dir -Filter $filter
    if ($files.Count -eq 1) { return 0 }
    return 1
}

function test_Clear-OldLogs_less_than {
    $Action = [String]$($script_log_file_count - 1)
    Clear-OldLogs
    $filter = "*$script_log_base_name*.log" -f $Action.ToLower()
    $files = Get-ChildItem $script_log_dir -Filter $filter
    if ($files.Count -eq $($script_log_file_count - 1)) { return 0 }
    return 1
}

function test_Clear-OldLogs_exact {
    $Action = [String]$script_log_file_count
    Clear-OldLogs
    $filter = "*$script_log_base_name*.log" -f $Action.ToLower()
    $files = Get-ChildItem $script_log_dir -Filter $filter
    if ($files.Count -eq $($script_log_file_count - 1)) { return 0 }
    return 1
}

function test_Clear-OldLogs_more_than {
    $Action = [String]$($script_log_file_count + 2)
    Clear-OldLogs
    $filter = "*$script_log_base_name*.log" -f $Action.ToLower()
    $files = Get-ChildItem $script_log_dir -Filter $filter
    if ($files.Count -eq $($script_log_file_count - 1)) { return 0 }
    return 1
}
