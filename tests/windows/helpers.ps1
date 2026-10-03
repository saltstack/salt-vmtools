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

function Save-ScriptState {
    # Main sets script scoped variables (Source, MinionVersion, LogLevel and
    # the values that come from them) and all the test files share one script
    # scope. Save what a test that runs Main changes so Restore-ScriptState can
    # put it back
    $state = @{}
    foreach ($name in @("Source", "MinionVersion", "LogLevel", "log_level_value",
                        "base_url", "api_url", "cli_parameters")) {
        $var = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $state[$name] = @{ Exists = [bool]$var; Value = $var.Value }
    }
    return $state
}

function Restore-ScriptState {
    param($State)
    foreach ($name in $State.Keys) {
        if ($State[$name].Exists) {
            Set-Variable -Name $name -Scope Script -Value $State[$name].Value
        } else {
            Remove-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        }
    }
}

function New-FakeVmtoolsd {
    # Build a stand-in for vmtoolsd.exe. The script reads guestVars by running
    #     vmtoolsd.exe --cmd "info-get guestinfo./vmware.components.salt_minion.<name>"
    # and there is no VMware Tools, or host to set the values, on a test
    # system. This answers that command from environment variables, which the
    # process the script runs in inherits:
    #     FAKE_GV_ARGS  - the value of the ".args" guestVar
    #     FAKE_GV_STATE - the value of the ".desiredstate" guestVar
    # A guestVar whose variable is not set fails, like a guestVar that is not
    # set on the host.
    #
    # Args:
    #     Path (string): where to build the exe
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )
    $source = @'
using System;
public static class FakeVmtoolsd {
    public static int Main(string[] args) {
        string command = args.Length > 1 ? args[1] : "";
        string value = null;
        if (command.EndsWith(".args")) {
            value = Environment.GetEnvironmentVariable("FAKE_GV_ARGS");
        } else if (command.EndsWith(".desiredstate")) {
            value = Environment.GetEnvironmentVariable("FAKE_GV_STATE");
        }
        if (value == null) return 1;
        Console.Write(value);
        return 0;
    }
}
'@
    if (Test-Path $Path) { Remove-Item -Path $Path -Force }
    Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $Path `
        -OutputType ConsoleApplication
}

function Enable-FakeVmtoolsd {
    # Put the stand-in in place of the vmtoolsd.exe the script uses,
    # $vmtoolsd_bin. Returns what Disable-FakeVmtoolsd needs to put it back
    $fake = Join-Path $env:TEMP "fake_vmtoolsd_$PID.exe"
    New-FakeVmtoolsd -Path $fake
    $backup = $null
    if (Test-Path $vmtoolsd_bin) {
        $backup = [System.IO.File]::ReadAllBytes($vmtoolsd_bin)
    }
    New-Item -Path (Split-Path $vmtoolsd_bin) -ItemType Directory -Force | Out-Null
    Copy-Item -Path $fake -Destination $vmtoolsd_bin -Force
    return @{ Fake = $fake; Backup = $backup }
}

function Disable-FakeVmtoolsd {
    param($State)
    if ($null -ne $State.Backup) {
        [System.IO.File]::WriteAllBytes($vmtoolsd_bin, $State.Backup)
    } else {
        Remove-Item -Path $vmtoolsd_bin -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $State.Fake -Force -ErrorAction SilentlyContinue
}

function Invoke-SvtminionProcess {
    # Run the script the way VMware Tools does, as its own PowerShell process
    # with the same options, and get what VMware Tools gets: the exit code.
    # The guestVars are answered by the stand-in from Enable-FakeVmtoolsd.
    #
    # Args:
    #     Arguments (string[]): The script's arguments
    #     State (string): The desiredstate guestVar, not set if not passed
    #     GuestArgs (string): The args guestVar, not set if not passed
    #
    # Returns a hashtable with ExitCode and Output
    param(
        [Parameter(Mandatory=$false)]
        [String[]] $Arguments = @(),

        [Parameter(Mandatory=$false)]
        [String] $State,

        [Parameter(Mandatory=$false)]
        [String] $GuestArgs
    )
    $env:FAKE_GV_STATE = if ($PSBoundParameters.ContainsKey("State")) { $State } else { $null }
    $env:FAKE_GV_ARGS = if ($PSBoundParameters.ContainsKey("GuestArgs")) { $GuestArgs } else { $null }
    try {
        $output = & powershell.exe -NoProfile -NonInteractive `
            -ExecutionPolicy RemoteSigned `
            -File ".\windows\svtminion.ps1" @Arguments 2>&1
        $exit_code = $LASTEXITCODE
    } finally {
        $env:FAKE_GV_STATE = $null
        $env:FAKE_GV_ARGS = $null
    }
    return @{ ExitCode = $exit_code; Output = @($output) }
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
