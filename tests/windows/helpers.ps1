function Write-Header {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $Label,

        [Parameter(Mandatory=$false)]
        [String] $Filler = "="
    )
    if($Label) {
        $total = 80 - $Label.Length
        $begin = [math]::Floor($total / 2)
        $leftover = $total % 2
        $end = $begin + $leftover
        Write-Host "$("$Filler" * $begin) $Label $("$Filler" * $end)"
    } else {
        Write-Host "$("$Filler" * 82)"
    }
}


function Write-Status {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Failed
    )
    if ($Failed -ne 0) {
        $msg = "Failed"
        $color = "Red"
    } else {
        $msg = "Success"
        $color = "Green"
    }
    $total = 80 - $msg.Length
    $begin = [math]::Floor($total / 2)
    $leftover = $total % 2
    $end = $begin + $leftover
    Write-Host "$(":" * $begin) " -NoNewline
    Write-Host $msg -NoNewline -ForegroundColor $color
    Write-Host " $(":" * $end)"
}


function Write-Success {
    Write-Host "Success" -ForegroundColor Green
}


function Write-Failed {
    Write-Host "Failed" -ForegroundColor Red
}

function Write-Done {
    Write-Host "Done" -ForegroundColor Yellow
}

function Get-SaltTestPythonCommand {
    # Prefer `python`, fall back to the `py` launcher
    if (Get-Command python -ErrorAction SilentlyContinue) {
        return "python"
    }
    return "py"
}

function Get-SaltTestVersionPairs {
    # Reads the major/exact version pairs from generate.py, the single
    # source of truth for which Salt versions the test suites cover. Returns
    # an ordered array of @{ Major = ...; Exact = ... }.
    $python = Get-SaltTestPythonCommand
    $generate_py = ".github\workflows\templates\generate.py"
    $lines = & $python $generate_py --print-versions
    $pairs = [System.Collections.ArrayList]::new()
    foreach ($line in $lines) {
        $major, $exact = $line -split '\s+'
        $pairs.Add(@{ Major = $major; Exact = $exact }) | Out-Null
    }
    return $pairs
}

function Get-SaltTestUpgradeSteps {
    # Reads the upgrade-step list (one per adjacent major pair) from
    # generate.py. Returns an ordered array of
    # @{ FromExact = ...; ToMajor = ...; ToExact = ... }.
    $python = Get-SaltTestPythonCommand
    $generate_py = ".github\workflows\templates\generate.py"
    $lines = & $python $generate_py --print-upgrade-steps
    $steps = [System.Collections.ArrayList]::new()
    foreach ($line in $lines) {
        $from_exact, $to_major, $to_exact = $line -split '\s+'
        $steps.Add(@{ FromExact = $from_exact; ToMajor = $to_major; ToExact = $to_exact }) | Out-Null
    }
    return $steps
}

function Reset-Environment {
    # Stop and remove the salt-minion service if it exists
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Stopping the salt-minion service: " -NoNewline
        Stop-Service -Name salt-minion *> $null
        Write-Done
        Write-Host "Removing the salt-minion service: " -NoNewline
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='salt-minion'"
        $service.delete() *> $null
        Write-Done
    }

    # Remove Program Data directory
    if (Test-Path "$base_salt_config_location") {
        Write-Host "Removing config directory: " -NoNewline
        Remove-Item "$base_salt_config_location" -Force -Recurse
        Write-Done
    }

    # Remove Program Files directory
    if (Test-Path "$base_salt_install_location") {
        Write-Host "Removing install directory: " -NoNewline
        Remove-Item "$base_salt_install_location" -Force -Recurse
        Write-Done
    }

    # Removing from the path

    $path = "$salt_dir"
    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
    $new_path_list = [System.Collections.ArrayList]::new()
    $removed = 0
    foreach ($item in $current_path.Split(";")) {
        $regex_path = $path.Replace("\", "\\")
        # Bail if we find the new path in the current path
        if ($item -imatch "^$regex_path(\\)?$") {
            # Remove this one
            Write-Host "Removing salt from the system path: " -NoNewline
            $removed = 1
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }
    if ($removed) {
        $new_path = $new_path_list -join ";"
        Set-ItemProperty -Path $path_reg_key -Name Path -Value $new_path
        Write-Done
    }

}
