function test_Remove-FileOrFolder_directory {
    $path = "C:\RemoveDir"
    New-Item -Path $path -ItemType directory -Force | Out-Null
    Remove-FileOrFolder -Path $path
    if (!(Test-Path -Path $path)) { return 0 } else { return 1 }
}

function test_Remove-FileOrFolder_file {
    $path = "C:\RemoveFile.txt"
    New-Item -Path $path -ItemType file -Force | Out-Null
    Remove-FileOrFolder -Path $path
    if (!(Test-Path -Path $path)) { return 0 } else { return 1 }
}
