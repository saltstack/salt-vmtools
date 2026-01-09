$path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"

function test_Add-SystemPathValue {
    Add-SystemPathValue -Path "C:\spongebob"
    $path = Get-ItemProperty -Path $path_reg_key -Name Path
    if ($path.Path -like "*C:\spongebob*") { return 0 } else { return 1 }
}

function test_Remove-SystemPathValue {
    Remove-SystemPathValue -Path "C:\spongebob"
    $path = Get-ItemProperty -Path $path_reg_key -Name Path
    if ($path.Path -notlike "*C:\spongebob*") { return 0 } else { return 1 }
}
