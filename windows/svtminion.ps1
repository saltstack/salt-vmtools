# Copyright (c) 2021 VMware, Inc. All rights reserved.

<#
.SYNOPSIS
VMware Tools script for managing the salt minion on a Windows guest

.DESCRIPTION
This script manages the salt minion on a Windows guest. The minion is a tiamat
build hosted on https://repo.saltproject.io/salt/vmware-tools-onedir. You can
install the minion, remove it, check script dependencies, get the script status,
and reset the minion.

When this script is run without any parameters the options will be obtained from
guestVars if present. If not they will be obtained from tools.conf. This
includes the action (install, remove, etc) and the minion config options
(master=192.168.10.10, etc.). The order of precedence is CLI options, then
guestVars, and finally tools.conf.

This script returns status exit codes when passing the Status option. Additional
exit codes that may be returned by this script pertain to its success or
failure. They are as follows:

0 - scriptSuccess
126 - scriptFailed
130 - scriptTerminated

.EXAMPLE
PS>svtminion.ps1 -install
PS>svtminion.ps1 -install -version 3004-1 master=192.168.10.10 id=vmware_minion

.EXAMPLE
PS>svtminion.ps1 -clear -prefix new_minion

.EXAMPLE
PS>svtminion.ps1 -status

.EXAMPLE
PS>svtminion.ps1 -depend

.EXAMPLE
PS>svtminion.ps1 -remove -loglevel debug

#>

[CmdletBinding(DefaultParameterSetName = "Install")]
param(

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Alias("i")]
    # Download, install, and start the salt-minion service.
    [Switch] $Install,

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Alias("m")]
    # The version of salt minion to install. Default is 3003.3-1.
    [String] $MinionVersion="3003.3-1",

    [Parameter(Mandatory=$false, ParameterSetName="Install",
            Position=0, ValueFromRemainingArguments=$true)]
    # Any number of minion config options specified by the name of the config
    # option as found in salt documentation. All options will be lower-cased and
    # written to the minion config as passed. All values are in the key=value.
    # format. eg: master=localhost
    [String[]] $ConfigOptions,

    [Parameter(Mandatory=$false, ParameterSetName="Remove")]
    [Alias("r")]
    # Stop and uninstall the salt-minion service.
    [Switch] $Remove,

    [Parameter(Mandatory=$false, ParameterSetName="Clear")]
    [Alias("c")]
    # Reset the salt-minion. Randomize the minion id and remove the minion keys.
    # The randomized minion id will be the old minion id, an underscore, and 5
    # random digits.
    [Switch] $Clear,

    [Parameter(Mandatory=$false, ParameterSetName="Status")]
    [Alias("s")]
    # Get the status of the salt minion installation. This returns a numeric
    # value that corresponds as follows:
    # 100 - installed
    # 101 - installing
    # 102 - notInstalled
    # 103 - installFailed
    # 104 - removing
    # 105 - removeFailed
    [Switch] $Status,

    [Parameter(Mandatory=$false, ParameterSetName="Depend")]
    [Alias("d")]
    # Ensure the required dependencies are available. Exits with a scriptFailed
    # error code (126) if any dependencies are missing.
    [Switch] $Depend,

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Parameter(ParameterSetName="Clear")]
    [Parameter(ParameterSetName="Status")]
    [Parameter(ParameterSetName="Depend")]
    [Parameter(ParameterSetName="Remove")]
    [Alias("l")]
    [ValidateSet(
            "silent",
            "error",
            "warning",
            "info",
            "debug",
            IgnoreCase=$true)]
    [String]
    # Sets the log level to display and log. Default is warning. Silent
    # suppresses all logging output
    $LogLevel = "warning",

    [Parameter(Mandatory=$false, ParameterSetName="Help")]
    [Parameter(ParameterSetName="Install")]
    [Parameter(ParameterSetName="Clear")]
    [Parameter(ParameterSetName="Status")]
    [Parameter(ParameterSetName="Depend")]
    [Parameter(ParameterSetName="Remove")]
    [Alias("h")]
    [Switch]
    # Displays help for this script.
    $Help,

    [Parameter(Mandatory=$false, ParameterSetName="Version")]
    [Parameter(ParameterSetName="Install")]
    [Parameter(ParameterSetName="Clear")]
    [Parameter(ParameterSetName="Status")]
    [Parameter(ParameterSetName="Depend")]
    [Parameter(ParameterSetName="Remove")]
    [Alias("v")]
    [Switch]
    # Displays the version of this script.
    $Version

)

################################ HELP/VERSION ##################################
# We'll put these functions first because they don't require administrator
# privileges to run

# Check for help switch
if ($help) {
    # Get the full script name
    $this_script = & {$myInvocation.ScriptName}
    Get-Help $this_script -Detailed
    exit 0
}

# This value is populated via CICD during build
$script_version = "SCRIPT_VERSION_REPLACE"
if ($Version) {
    Write-Host $script_version
    exit 0
}

################################# STATUS CODES #################################
$STATUS_CODES = @{
    "scriptSuccess" = 0;
    "installed" = 100;
    "installing" = 101;
    "notInstalled" = 102;
    "installFailed" = 103;
    "removing" = 104;
    "removeFailed" = 105;
    "scriptFailed" = 126;
    "scriptTerminated" = 130;
    100 = "installed";
    101 = "installing";
    102 = "notInstalled";
    103 = "installFailed"
    104 = "removing";
    105 = "removeFailed";
}

################################ REQUIREMENTS ##################################
# Make sure the script is run as Administrator
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
if (!($Principal.IsInRole(
        [System.Security.Principal.WindowsBuiltInRole]::Administrator
))) {
    Write-Host "This script must run as Administrator" -ForegroundColor Red
    exit $STATUS_CODES["scriptFailed"]
}


################################# LOGGING ######################################
$LOG_LEVELS = @{
    "silent" = 0;
    "error" = 1;
    "warning" = 2;
    "info" = 3;
    "debug" = 4
}
$log_level_value = $LOG_LEVELS[$LogLevel.ToLower()]

################################# SETTINGS #####################################
$Global:ErrorActionPreference = "Stop"
$Global:ProgressPreference = "SilentlyContinue"
$download_retry_count = 5
$current_date = Get-Date -Format "yyyy-MM-dd"
$script_name = $MyInvocation.MyCommand.Name
$script_log_dir = "$env:ProgramData\VMware\logs"

################################# VARIABLES ####################################
# Repository locations and names
$salt_name = "salt"
$salt_version = $MinionVersion
$base_url = "https://repo.saltproject.io/salt/vmware-tools-onedir"
$salt_web_file_name = "$salt_name-$salt_version-windows-amd64.zip"
$salt_web_file_url = "$base_url/$salt_version/$salt_web_file_name"
$salt_hash_name = "$salt_name-$salt_version" + "_SHA512"
$salt_hash_url = "$base_url/$salt_version/$salt_hash_name"

# Salt file and directory locations
$base_salt_install_location = "$env:ProgramFiles\VMware\Salt Project"
$salt_dir = "$base_salt_install_location\$salt_name"
$salt_bin = "$salt_dir\salt\salt.exe"
$ssm_bin = "$salt_dir\ssm.exe"

$base_salt_config_location = "$env:ProgramData\VMware\Salt Project"
$salt_root_dir = "$base_salt_config_location\$salt_name"
$salt_config_dir = "$salt_root_dir\conf"
$salt_config_name = "minion"
$salt_config_file = "$salt_config_dir\$salt_config_name"
$salt_pki_dir = "$salt_config_dir\pki\$salt_config_name"

# Files/Dirs to remove
$file_dirs_to_remove = [System.Collections.ArrayList]::new()
$file_dirs_to_remove.Add($base_salt_config_location) | Out-Null
$file_dirs_to_remove.Add($base_salt_install_location) | Out-Null

## VMware registry locations
$vmtools_base_reg = "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools"
$vmtools_salt_minion_status_name = "SaltMinionStatus"

$Error.Clear()
try{
    $reg_key = Get-ItemProperty $vmtools_base_reg
} catch {
    $msg = "Unable to find valid VMtools installation : $Error"
    Write-Host $mst -ForeGroundColor Red
    exit $STATUS_CODES["scriptFailed"]
}
if (!($reg_key.PSObject.Properties.Name -contains "InstallPath")) {
    Write-Host "Unable to find valid VMtools installation" -ForeGroundColor Red
    exit $STATUS_CODES["scriptFailed"]
}

## VMware file and directory locations
$vmtools_base_dir = Get-ItemPropertyValue -Path $vmtools_base_reg `
                                          -Name "InstallPath"
$vmtools_conf_dir = "$env:ProgramData\VMware\VMware Tools"
$vmtools_conf_file = "$vmtools_conf_dir\tools.conf"
$vmtoolsd_bin = "$vmtools_base_dir\vmtoolsd.exe"

## VMware guestVars file and directory locations
$guestvars_base = "guestinfo./vmware.components"
$guestvars_section = "salt_minion"
$guestvars_salt = "$guestvars_base.$guestvars_section"
$guestvars_salt_args = "$guestvars_salt.args"


############################### HELPER FUNCTIONS ###############################


function Write-Log {
    # Functions for writing logs to the screen and to the log file
    #
    # Args:
    #     Message (string): The log message
    #     Level (string):
    #         The log level. Must be one of error, info, warning, debug. Default
    #         is info
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [String] $Message,

        [Parameter()]
        [ValidateSet("error", "info", "warning", "debug", IgnoreCase=$true)]
        [String] $Level = "info"
    )

    $Level = $Level.ToUpper()
    $level_text = $Level + " " * (7 - $Level.Length)

    if ( $LOG_LEVELS[$Level.ToLower()] -le $log_level_value ) {
        $date_time = Get-Date -Format "yyyy-MM-dd:HH:mm:ss.ffff"
        $log_message = "[$date_time] [$level_text] $Message"
        $log_file_message = "[$date_time] [$PID] [$level_text] $Message"
        if (!(Test-Path($script_log_dir))) {
            Write-Host "[$date_time] [INFO   ] : Creating log file directory"
            New-Item -Path $script_log_dir -ItemType Directory | Out-Null
        }
        $base_name = $script_name.Split(".")[0]
        $log_path = "$script_log_dir\vmware-$base_name-$current_date.log"
        Add-Content -Path $log_path -Value $log_file_message
        switch ($Level) {
            "ERROR" { $color = "Red" }
            "WARNING" { $color = "Yellow" }
            default { $color = "White"}
        }
        if ($log_level_value -ge $LOG_LEVELS["error"] ) {
            Write-Host $log_message -ForegroundColor $color
        }
    }
}


function Get-ScriptRunningStatus {
    # Try to detect if this script is already running under another process
    #
    # Returns True if running, otherwise False

    Write-Log "Checking for a running instance of this script" -Level info

    #Get all running powershell processes
    $filter = "Name='powershell.exe' AND CommandLine LIKE '%$script_name%'"
    $processes = Get-WmiObject Win32_Process -Filter $filter | `
                 Select-Object CommandLine,ProcessId

    $process_found = $false
    foreach ($process in $processes){
        [Int32]$process_pid = $process.ProcessId
        [String]$process_cmd = $process.commandline
        #Are other instances of this script already running?
        if (($process_cmd -match $script_name) -And ($process_pid -ne $PID)) {
            $process_found = $true
        }
    }
    if ($process_found) {
        Write-Log "Found running instance in PID: $process_pid" -Level debug
        return $true
    } else {
        Write-Log "Running instance not detected" -Level debug
        return $false
    }
}


function Get-Status {
    # Read the status out of the registry. If the key is missing that means
    # notInstalled
    #
    # Returns the error level number
    $script_running_status = Get-ScriptRunningStatus

    Write-Log "Getting status" -Level info
    $Error.Clear()
    try {
        $current_status = Get-ItemPropertyValue `
                            -Path $vmtools_base_reg `
                            -Name $vmtools_salt_minion_status_name
        Write-Log "Found status code: $current_status" -Level debug
    } catch {
        Write-Log "Key not set, not installed : $Error" -Level debug
        $current_status = $STATUS_CODES["notInstalled"]
    }

    # If status is 1 or 4 (installing or removing) but there isn't another
    # script running, then the status is installFailed or removeFailed
    $list_ing = @($STATUS_CODES["installing"], $STATUS_CODES["removing"])
    if (($list_ing -contains $current_status) -and !($script_running_status)) {
        switch ($current_status) {
            $STATUS_CODES["installing"] {
                Write-Log "Found failed install" -Level debug
                $current_status = $STATUS_CODES["installFailed"]
            }
            $STATUS_CODES["removing"] {
                Write-Log "Found failed remove" -Level debug
                $current_status = $STATUS_CODES["removeFailed"]
            }
        }
    }

    if ($STATUS_CODES.keys -contains $current_status) {
        $status_lookup = $STATUS_CODES[$current_status]
        Write-Log "Found status: $status_lookup" -Level debug
    } else {
        Write-Log "Unknown status code: $current_status" -Level debug
    }
    return $current_status
}


function Set-Status {
    # Set the numeric value of the status in the registry. notInstalled means to
    # remove the key
    #
    # Args:
    #     NewStatus (string):
    #         The status to set. Must be one of the following:
    #             - installed
    #             - installing
    #             - notInstalled
    #             - installFailed
    #             - removing
    #             - removeFailed
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet(
                "installed",
                "installing",
                "notInstalled",
                "installFailed",
                "removing",
                "removeFailed"
        )]
        [String] $NewStatus
    )

    Write-Log "Setting status: $NewStatus" -Level info
    $status_code = $STATUS_CODES[$NewStatus]
    # If it's notInstalled, just remove the propery name
    if ($status_code -eq $STATUS_CODES["notInstalled"]) {
        $Error.Clear()
        try
        {
            Remove-ItemProperty -Path $vmtools_base_reg `
                                -Name $vmtools_salt_minion_status_name
            $key = "$vmtools_base_reg\$vmtools_salt_minion_status_name"
            Write-Log "Removed reg key: $key" -Level debug
            Write-Log "Set status to $NewStatus" -Level debug
        } catch [System.Management.Automation.PSArgumentException] {
            Write-Log "Reg key not present: $key" -Level debug
            Write-Log "Status already set to: $NewStatus" -Level debug
        } catch {
            Write-Log "Error removing reg key: $Error" -Level error
            exit $STATUS_CODES["scriptFailed"]
        }
    } else {
        $Error.Clear()
        try {
            New-ItemProperty -Path $vmtools_base_reg `
                             -Name $vmtools_salt_minion_status_name `
                             -Value $status_code `
                             -Force | Out-Null
            Write-Log "Set status to $NewStatus" -Level debug
        } catch {
            Write-Log "Error writing status: $Error" -Level error
            exit $STATUS_CODES["scriptFailed"]
        }
    }
}


function Set-FailedStatus {
    # Sets the status if either add or remove fails, each sets a different
    # status if it fails
    switch ($Action.ToLower()) {
        "add" { Set-Status installFailed }
        "remove" { Set-Status removeFailed }
    }
}


function Get-WebFile{
    # Downloads a file from the web. Enables the TLS1.2 protocol. If the
    # download times out, wait 10 seconds and try again. Continues retrying
    # until the download retry count max is reached
    #
    # Used by:
    # - Get-SaltFromWeb
    #
    # Args:
    #     Url (string): The url for the file to download
    #     OutFile (string): The location to put the downloaded file
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Url,

        [Parameter(Mandatory=$true)]
        [String] $OutFile
    )
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.SecurityProtocolType]'Tls12'
    $url_name = $Url.SubString($Url.LastIndexOf('/'))

    $tries = 1
    $success = $false
    do {
        $Error.Clear()
        try {
            # Download the file
            $msg = "Downloading (try: $tries/$download_retry_count): $url_name"
            Write-Log $msg -Level debug
            Invoke-WebRequest -Uri $Url -OutFile $OutFile
        } catch {
            Write-Log "Error downloading: $Url" -Level warning
            Write-Log "Error message: $Error" -Level warning
        } finally {
            if ((Test-Path -Path "$OutFile") `
                -and `
                ((Get-Item "$OutFile").Length -gt 0kb
            )) {
                Write-Log "Finished downloading: $url_name" -Level debug
                $success = $true
            } else {
                $tries++
                if ($tries -gt $download_retry_count) {
                    Write-Log "Retry count exceeded" -Level error
                    Set-FailedStatus
                    exit $STATUS_CODES["scriptFailed"]
                }
                Write-Log "Trying again after 10 seconds" -Level warning
                Start-Sleep -Seconds 10
            }
        }
    } while (!($success))
}


function Get-HashFromFile {
    # Gets the hash for the file from the hash file which contains a list of
    # hashes and their files
    #
    # Used by:
    # - Get-SaltFromWeb
    #
    # Args:
    #     HashFile (string): The file containing the hashes
    #     FileName (string): The name of the file to search for in the hash file
    #
    # Returns:
    #     Returns the hash for the specified file
    # Errors:
    #     If there is an error, set the failed status and exit with an error
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $HashFile,

        [Parameter(Mandatory=$true)]
        [String] $FileName
    )
    Write-Log "Loading hashfile: $HashFile" -Level debug
    $lines = Get-Content -Path $HashFile
    Write-Log "Searching for hash for: $FileName" -Level debug
    foreach ($line in $lines) {
        $file_hash, $file_name = $line -split "\s+"
        if ($FileName -eq $file_name) {
            Write-Log "Found hash: $file_hash" -Level debug
            return $file_hash
        }
    }
    Write-Log "No hash found for: $FileName" -Level error
    Set-FailedStatus
    exit $STATUS_CODES["scriptFailed"]
}


function Expand-ZipFile {
    # Extract a zip file
    #
    # Used by:
    # - Install-SaltMinion
    #
    # Args:
    #     ZipFile (string): The file to extract
    #     Destination (string): The location to extract to
    #
    # Error:
    #     Sets the failed status and exits with an error
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ZipFile,

        [Parameter(Mandatory = $true)]
        [string] $Destination
    )

    if (!(Test-Path -Path $Destination)) {
        Write-Log "Creating missing directory: $Destination" -Level debug
        New-Item -ItemType directory -Path $Destination
    }
    Write-Log "Unzipping '$ZipFile' to '$Destination'" -Level debug
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        # PowerShell 5 introduced Expand-Archive
        try{
            Expand-Archive -Path $ZipFile -DestinationPath $Destination -Force
        } catch {
            Write-Log "Failed to unzip $ZipFile : $Error" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        }
    } else {
        # This method will work with older versions of powershell, but it is
        # slow
        $objShell = New-Object -Com Shell.Application
        $objZip = $objShell.NameSpace($ZipFile)
        $Error.Clear()
        try{
            foreach ($item in $objZip.Items()) {
                $objShell.Namespace($Destination).CopyHere($item, 0x14)
            }
        } catch {
            Write-Log "Failed to unzip $ZipFile : $Error" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        }
    }
    Write-Log "Finished unzipping '$ZipFile' to '$Destination'" -Level debug
}


function Add-SystemPathValue{
    # Add a new entry to the system path environment variable. Only adds the new
    # path if it does not already exist.
    #
    # Used by:
    # - Install-SaltMinion
    #
    # Args:
    #     Path (string): The target path to add
    #
    # Warning:
    #     Logs a warning if the target path does not exist
    #
    # Error:
    #     Sets the failed status and exits with an error
    [Cmdletbinding()]
    param (
        [parameter(Mandatory=$True)]
        [String]$Path
    )

    $key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"

    # Make sure the target folder exists
    Write-Log "Ensuring target path exists" -Level debug
    if (!(Test-Path $Path)) {
        Write-Log "Target path does not exist: $Path" -Level warning
    }

    Write-Log "Getting current system path" -Level debug
    $current_path = (Get-ItemProperty -Path $key -Name Path).Path
    $new_path_list = [System.Collections.ArrayList]::new()

    Write-Log "Verifying the target path is not already present" -Level debug
    foreach ($item in $current_path.Split(";")) {
        $regex_path = $Path.Replace("\", "\\")
        # Bail if we find the new path in the current path
        if ($item -imatch "^$regex_path(\\)?$") {
            Write-Log "Target path already exists: $Path" -Level warning
            return
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }

    # Add the new path to the array
    Write-Log "Adding target path: $Path" -Level debug
    $new_path_list.Add($Path) | Out-Null

    $new_path = $new_path_list -join ";"
    $Error.Clear()
    try{
        Write-Log "Updating system path" -Level debug
        Set-ItemProperty -Path $key -Name Path -Value $new_path
    } catch {
        Write-Log "Failed to add $Path the system path" -Level error
        Write-Log "Tried to write: $new_path" -Level error
        Write-Log "Error message: $Error" -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }
}


function Remove-SystemPathValue {
    # Removes the specified target path from the system path environment
    # variable
    #
    # Used by:
    # - Remove-SaltMinion
    #
    # Args
    #     Path (string): The target path to remove
    #
    # Error:
    #     Set failed status and exit with error code
    [Cmdletbinding()]
    param (
        [parameter(Mandatory=$True)]
        [String]$Path
    )

    Write-Log "Removing from system path: $Path" -Level info

    $key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"

    Write-Log "Getting current system path" -Level debug
    $current_path = (Get-ItemProperty -Path $key -Name Path).Path
    $new_path_list = [System.Collections.ArrayList]::new()

    Write-Log "Searching for $Path" -Level debug
    foreach ($item in $current_path.Split(";")) {
        $regex_path = $Path.Replace("\", "\\")
        # Bail if we find the new path in the current path
        if ($item -imatch "^$regex_path(\\)?$") {
            Write-Log "Removing target path: $Path" -Level debug
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }

    $new_path = $new_path_list -join ";"
    $Error.Clear()
    try {
        Write-Log "Updating system path" -Level debug
        Set-ItemProperty -Path $key -Name Path -Value $new_path
    } catch {
        $msg = "Failed to remove $Path from the system path: $new_path"
        Write-Log $msg -Level error
        Write-Log "Tried to write: $new_path" -Level error
        Write-Log "Error message: $Error" -level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }
}


function Remove-FileOrFolder {
    # Removes a file or a folder recursively from the system. Takes ownership of
    # the file or directory before removing
    #
    # Used by:
    # - Remove-SaltMinion
    # - Reset-SaltMinion
    #
    # Args:
    #     Path (string): The file or folder to remove
    #
    # Error:
    #     Sets failed status and exits with error code 1
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )
    Write-Log "Removing: $Path" -Level info
    $tries = 1
    $max_tries = 5
    $success = $false
    Write-Log "Taking ownership: $Path" -Level debug
    try {
        & takeown /a /r /d Y /f $Path *> $null
        # Pause here to avoid a race condition
        Start-Sleep -Seconds 1
    } catch {
        Write-Log "Directory does not exist" -Level debug
    }
    if (Test-Path -Path $Path) {
        while (!($success)) {
            $Error.Clear()
            try {
                # Remove the file/dir
                $msg = "Removing (try: $tries/$max_tries): $Path"
                Write-Log $msg -Level debug
                Remove-Item -Path $Path -Force -Recurse
            } catch {
                Write-Log "Error removing: $Path" -Level warning
                Write-Log "Error message: $Error" -Level warning
            } finally {
                if (!(Test-Path -Path $Path)) {
                    Write-Log "Finished removing $Path" -Level debug
                    $success = $true
                } else {
                    $tries++
                    if ($tries -gt $max_tries) {
                        Write-Log "Retry count exceeded" -Level error
                        Set-FailedStatus
                        exit $STATUS_CODES["scriptFailed"]
                    }
                    Write-Log "Trying again after 5 seconds" -Level warning
                    Start-Sleep -Seconds 5
                }
            }
        }
    } else {
        Write-Log "Path not found: $Path" -Level warning
    }
}


function Get-GuestVars {
    # Get guestvars data using vmtoolsd.exe
    # They can be set on the host using vmrun.exe
    # vmrun writeVariable "d:\VMWare\Windows Server 2019\Windows Server 2019.vmx" guestVar vmware./components.salt_minion.args "master=192.168.0.12 id=test_id"
    #
    # Used by:
    # - Get-ConfigGuestVars
    #
    # Args:
    #     GuestVarsPath (string):
    #         The option to get from the guestvars repository. Likely one of the
    #         following:
    #         - Action: guestinfo.vmware.components.salt_minion
    #         - Minion Config: guestinfo.vmware.components.salt_minion.args
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $GuestVarsPath
    )

    $arguments = "--cmd `"info-get $GuestVarsPath`""

    Write-Log "Getting value for $GuestVarsPath" -Level debug
    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    Write-Log "Running $vmtoolsd_bin $arguments" -Level debug
    $ProcessInfo.FileName = $vmtoolsd_bin
    $ProcessInfo.Arguments = $arguments
    $ProcessInfo.RedirectStandardError = $true
    $ProcessInfo.RedirectStandardOutput = $true
    $ProcessInfo.UseShellExecute = $false
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $ProcessInfo
    $Process.Start() | Out-Null
    $Process.WaitForExit()
    $stdout = $Process.StandardOutput.ReadToEnd()
    $stderr = $Process.StandardError.ReadToEnd()
    $exitcode = $Process.ExitCode

    if (($exitcode -eq 0) -and !($stdout.Trim() -eq "")) {
        $msg = "Value found for $GuestVarsPath : $($stdout.Trim())"
        Write-Log $msg -Level debug
        return $stdout.Trim()
    } else {
        $msg = "No value found for $GuestVarsPath : $stderr"
        Write-Log $msg -Level debug
    }
}


function _parse_config {
    # Parse config options that are in the format key=value. These can be passed
    # on the cli, guestvars, or tools.conf
    #
    # Used by:
    # - Get-ConfigCLI
    # - Get-ConfigGuestVars
    # - Get-ConfigToolsConf
    #
    # Args:
    #     KeyValues (string[])
    #         A list of string values in the key=value format
    #
    # Returns:
    #     A hash table containing the config options and their values
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String[]] $KeyValues
    )

    $config_options = @{}
    foreach ($key_value in $KeyValues.Split()) {
        if ($key_value -like "*=*") {
            Write-Log "Found config: $key_value" -Level debug
            $key, $value = $key_value -split "="
            if ($value) {
                $config_options[$key.ToLower()] = $value.ToLower()
            } else {
                Write-Log "No config value specified: $key_value" -Level warning
            }
        } else {
            Write-Log "Invalid config format ignored: $key_value" -Level warning
        }
    }
    $count = $config_options.Count
    Write-Log "Found $count config options" -Level debug
    return $config_options
}


function Get-ConfigCLI {
    # Get salt-minion configuration options from arguments passed on the
    # command line. These key/value pairs are already in the ConfigOptions
    # variable populated by the powershell cli parser. They should be a space
    # delimited list of options in the key=value format.
    #
    # Used by:
    # - Get-MinionConfig
    #
    # Return hashtable
    Write-Log "Checking for CLI config options" -Level debug
    if ($ConfigOptions) {
        return _parse_config $ConfigOptions
    } else {
        Write-Log "Minion config not passed on CLI" -Level warning
    }
}


function Get-ConfigGuestVars {
    # Get salt-minion configuration options defined in the guestvars. That
    # should be a space delimited list of options in the key=value format.
    #
    # Used by:
    # - Get-MinionConfig
    #
    # Return hashtable
    Write-Log "Checking for GuestVars config options" -Level debug
    $config_options = Get-GuestVars -GuestVarsPath $guestvars_salt_args
    if ($config_options) {
        return _parse_config $config_options
    } else {
        Write-Log "Minion config not defined in guestvars" -Level warning
    }
}


function Read-IniContent {
    # Create a hash table with values from an ini file. Each section will
    # contain a sub hash table with key/value pairs
    #
    # Used by:
    # - Get-ConfigToolsConf
    #
    # Args:
    #     FilePath (string): The location of the ini file to read
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $FilePath
    )

    if (!(Test-Path -Path $FilePath)) {
        Write-Log "File not found: $FilePath" -Level warning
        return
    }

    $ini = @{}

    switch -regex -file $FilePath {
        # [Section]
        "^(?![#,;])\[(.+)\]$" {
            $section = $matches[1]
            $ini[$section] = @{}
        }
        # key=value
        "^(?![#,;])(.+?)\s*=(.*)$" {
            $key,$value = $matches[1..2]
            $ini[$section][$key] = $value
        }
    }
    return $ini
}


function Get-ConfigToolsConf {
    # Get salt-minion configuration options defined in tools.conf. That should
    # be all keys/value pairs under the [salt_minion] section of the tools.conf
    # ini file.
    #
    # Used by:
    # - Get-MinionConfig
    #
    # Return hashtable
    $config_options = Read-IniContent -FilePath $vmtools_conf_file
    Write-Log "Checking for tools.conf config options" -Level debug
    if ($config_options) {
        $count = $config_options[$guestvars_section].Count
        Write-Log "Found $count config options" -Level debug
        return $config_options[$guestvars_section]
    } else {
        Write-Log "Minion config not defined in tools.conf" -Level warning
    }
}


function Get-MinionConfig {
    # Get the minion config values to be place in the minion config file. The
    # Order of priority is as follows:
    # - Get config from tools.conf (defined by VMtools - older method)
    # - Get config from GuestVars (defined by VMtools), overwrites matching
    #   tools.conf
    # - Get config from the CLI (options passed to the script), overwrites
    #   matching guestVars
    # - No config found, use salt minion defaults (master: salt, id: hostname)
    #
    # Used by:
    # - Add-MinionConfig
    #
    # Returns a hash table of options or null if no options found
    Write-Log "Getting minion config" -Level info
    $config_options = @{}
    # Get tools.conf config first
    $tc_config = Get-ConfigToolsConf
    if ($tc_config) {
        foreach ($row in $tc_config.GetEnumerator()) {
            if ($row.Value) {
                $config_options[$row.Name] = $row.Value
            }
        }
    }
    # Get guestVars config, conflicting values will be overwritten by guestvars
    $gv_config = Get-ConfigGuestVars
    if ($gv_config) {
        foreach ($row in $gv_config.GetEnumerator()) {
            if ($row.Value) {
                $config_options[$row.Name] = $row.Value
            }
        }
    }
    # Get cli config, conflicting values will be overwritten by cli
    $cli_config = Get-ConfigCLI
    if ($cli_config) {
        foreach ($row in $cli_config.GetEnumerator()) {
            if ($row.Value) {
                $config_options[$row.Name] = $row.Value
            }
        }
    }
    return $config_options
}


function Get-IsSymlink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )
    $fd_path = Get-Item -Path $Path
    return [bool]($fd_path.Attributes -band [IO.FileAttributes]::ReparsePoint)
}


function Get-IsSecureOwner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )

    $acl = Get-Acl($Path)
    $owner = (($acl | Select-Object Owner).Owner).ToLower()
    if (($owner.EndsWith("system")) -or ($owner.EndsWith("administrators"))) {
        return $true
    }
    return $false
}


function Set-Security {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path,

        [Parameter(Mandatory=$false)]
        [String] $Owner = "Administrators"
    )

    Write-Log "Setting Security: $Path" -Level info

    Write-Log "Getting ACL: $Path" -Level debug
    $file_acl = Get-Acl -Path $Path

    Write-Log "Setting Sddl" -Level debug
    $Sddl = 'D:PAI(A;OICI;0x1200a9;;;WD)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
    $file_acl.SetSecurityDescriptorSddlForm($Sddl)

    Write-Log "Setting Owner" -Level debug
    $file_acl.SetOwner([System.Security.Principal.NTAccount]"$Owner")

    Write-Log "Writing New ACL" -Level debug
    Set-Acl -Path $Path -AclObject $file_acl
}


function New-SecureDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $Path
    )
    if (Test-Path -Path $Path) {
        if (Get-IsSymlink -Path $Path) {
            Write-Log "Found symlink: $Path" -Level warning
            Write-Log "Renaming symlink (.insecure): $Path" -Level warning
            if (Test-Path -Path "$Path.insecure") {
                Write-Log "Insecure backup directory already exists." error
                Write-Log "Please double check the existing directory" error
                Write-Log "If you are not sure why it exists we recommend" error
                Write-Log "that you remove all directories named $Path" error
                Write-Host "Insecure directory exists. Terminating Script"
                exit $STATUS_CODES["scriptFailed"]
            }
            # We can't rename a symlink, we have to delete and recreate it
            $target = (Get-Item $Path | Select-Object -ExpandProperty Target)
            [System.IO.Directory]::Delete($Path, $true) | Out-Null
            New-Item -ItemType SymbolicLink `
                     -Path "$Path.insecure" `
                     -Target $target | Out-Null
        }
    }
    if (Test-Path -Path $Path) {
        if (!(Get-IsSecureOwner -Path $Path)) {
            Write-Log "Found insecure owner: $Path" -Level warning
            Write-Log "Renaming directory (.insecure): $Path" -Level warning
            if (Test-Path -Path "$Path.insecure") {
                Write-Log "Insecure backup directory already exists." error
                Write-Log "Please double check the existing directory" error
                Write-Log "If you are not sure why it exists we recommend" error
                Write-Log "that you remove all directories named $Path" error
                Write-Host "Insecure directory exists. Terminating Script"
                exit $STATUS_CODES["scriptFailed"]
            }
            Move-Item -Path $Path `
                      -Destination "$Path.insecure" `
                      -Force | Out-Null
        }
    }
    if (Test-Path -Path $Path) {
        if((Get-ChildItem -Path $Path | Measure-Object).Count -ne 0) {
            Write-Log "Found non-empty directory: $Path" -Level warning
            Write-Log "Renaming file/folder (.insecure): $Path" -Level warning
            if (Test-Path -Path "$Path.insecure") {
                Write-Log "Insecure backup directory already exists." error
                Write-Log "Please double check the existing directory" error
                Write-Log "If you are not sure why it exists we recommend" error
                Write-Log "that you remove all directories named $Path" error
                Write-Host "Insecure directory exists. Terminating Script"
                exit $STATUS_CODES["scriptFailed"]
            }
            Move-Item -Path $Path `
                      -Destination "$Path.insecure" `
                      -Force | Out-Null
        }
    }
    if (!(Test-Path -Path $Path)) {
        Write-Log "Creating directory: $Path" -Level debug
        New-Item -Path $Path -Type Directory | Out-Null
    }

    Set-Security -Path $Path
}


function Add-MinionConfig {
    # Write minion config options to the minion config file

    # Make sure the config directory exists
    New-SecureDirectory -Path $base_salt_config_location
    New-SecureDirectory -Path $salt_root_dir
    New-SecureDirectory -Path $salt_config_dir

    # Get the minion config
    $config_options = Get-MinionConfig

    if (!($config_options)) {
        Write-Log "No minion config found. Defaults will be used" -Level warning
    }

    # Add file_roots to point to ProgramData
    $config_options["file_roots"] = $salt_root_dir
    $new_content = [System.Collections.ArrayList]::new()
    foreach ($row in $config_options.GetEnumerator()) {
        $new_content.Add("$($row.Name): $($row.Value)") | Out-Null
    }
    $config_content = $new_content -join "`r`n"
    $Error.Clear()
    try {
        Write-Log "Writing minion config" -Level info
        Set-Content -Path $salt_config_file -Value $config_content
        Write-Log "Finished writing minion config" -Level debug
    } catch {
        $msg = "Failed to write minion config: $config_content : $Error"
        Write-Log $msg -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }
}


function Start-MinionService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $ServiceName = "salt-minion"
    )
    # Start the minion service
    Write-Log "Starting the $ServiceName service" -Level info
    Start-Service -Name $ServiceName *> $null

    Write-Log "Checking the status of the $ServiceName service" -Level debug
    if ((Get-Service -Name $ServiceName).Status -eq "Running") {
        Write-Log "Service started successfully" -Level debug
    } else {
        Write-Log "Failed to start the $ServiceName service" -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }
}


function Stop-MinionService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $ServiceName = "salt-minion"
    )
    # Stop the salt-minion service
    Write-Log "Stopping the $ServiceName service" -Level info
    Stop-Service -Name $ServiceName *> $null

    Write-Log "Checking the status of the $ServiceName service" -Level debug
    if ((Get-Service -Name $ServiceName).Status -eq "Stopped") {
        Write-Log "Service stopped successfully" -Level debug
    } else {
        Write-Log "Failed to stop the $ServiceName service" -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }
}


function Get-RandomizedMinionId {
    # Generate a randomized minion id
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $Prefix = "minion",

        [Parameter(Mandatory=$false)]
        [String] $Length = 5
    )
    $chars = (0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A)
    $rand_string = (-join ($chars | Get-Random -Count $Length | % {[char]$_}))
    return -join ($Prefix, "_", $rand_string)
}


############################### MAIN FUNCTIONS #################################


function Confirm-Dependencies {
    # Check that the required dependencies for this script are present on the
    # system
    #
    # Return:
    #     Bool: False if missing dependencies, otherwise True
    $deps_present = $true
    Write-Log "Checking dependencies" -Level info

    # VMtools files
    # Files required by this script
    $salt_dep_files = @{}
    $salt_dep_files["vmtoolsd.exe"] = $vmtools_base_dir

    foreach ($file in $salt_dep_files.Keys) {
        Write-Log "Looking for $file in $($salt_dep_files[$file])" -Level debug
        if(!(Test-Path("$($salt_dep_files[$file])\$file"))) {
            $msg = "Unable to find $file in $($salt_dep_files[$file])"
            Write-Log $msg -Level error
            $deps_present = $false
        }
    }

    Write-Log "All dependencies found" -Level debug
    return $deps_present
}


function Find-StandardSaltInstallation {
    # Find an existing standard salt installation
    #
    # Return:
    #     Bool: True if standard installation found, otherwise False

    # Standard locations
    $locations = [System.Collections.ArrayList]::new()
    $locations.Add("C:\salt") | Out-Null
    $locations.Add("$salt_dir") | Out-Null

    # Check registry for new style locations
    try{
        $reg_path = "HKLM:\SOFTWARE\Salt Project\salt"
        $reg_key = Get-ItemProperty $reg_path
        $dir_path = Get-ItemPropertyValue -Path $reg_path -Name "install_dir"
        $locations.Add($dir_path) | Out-Null
    } catch { }

    # Check for python.exe in locations
    Write-Log "Looking for Standard Installation" -Level info
    $exists = $false
    foreach ($path in $locations) {
        if (Test-Path -Path "$path\bin\python.exe" ) {
            Write-Log "Standard Installation detected: $path" -Level error
            $exists = $true
        }
    }
    if (!($exists)) {
        Write-Log "Standard Installation not detected" -Level debug
    }
    return $exists
}


function Get-SaltFromWeb {
    # Download the salt tiamat zip file from the web and verify the hash
    #
    # Error:
    #     Set the status and exit with an error

    # Make sure the download directory exists
    if ( !( Test-Path -Path $base_salt_install_location) ) {
        Write-Log "Creating directory: $base_salt_install_location" -Level debug
        New-Item -Path $base_salt_install_location `
                 -ItemType Directory | Out-Null
    }

    # Download the salt file
    Write-Log "Downloading salt" -Level info
    $salt_file = "$base_salt_install_location\$salt_web_file_name"
    Get-WebFile -Url $salt_web_file_url -OutFile $salt_file

    # Download the hash file
    Write-Log "Downloading hash file" -Level info
    $hash_file = "$base_salt_install_location\$salt_hash_name"
    Get-WebFile -Url $salt_hash_url -OutFile $hash_file

    # Get the hash for the salt file
    $file_hash = (Get-FileHash -Path $salt_file -Algorithm SHA512).Hash
    $expected_hash = Get-HashFromFile -HashFile $hash_file `
                                      -FileName $salt_web_file_name

    Write-Log "Verifying hash" -Level info
    if ($file_hash -like $expected_hash) {
        Write-Log "Hash verified" -Level debug
    } else {
        Write-Log "Failed to verify hash:" -Level error
        Write-Log "  - $file_hash" -Level error
        Write-Log "  - $expected_hash" -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }
}


function New-SaltCallScript {
    # Create the salt-call.bat script
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
    # The location to create the script
        [String] $Path
    )
    $content = @(
    ":: Copyright (c) 2021 VMware, Inc. All rights reserved.",
    "",
    ":: Script for starting the Salt-Minion",
    ":: Accepts all parameters that Salt-Minion Accepts",
    "@ echo off",
    "",
    ":: Define Variables",
    "Set SaltBin=%~dp0\salt\salt.exe",
    "",
    "net session >nul 2>&1",
    "if %errorLevel%==0 (",
    "    :: Launch Script",
    "    `"%SaltBin%`" call %*",
    ") else (",
    "    echo ***** This script must be run as Administrator *****",
    ")"
    )
    $file_content = $content -join "`r`n"
    Set-Content -Path $Path -Value $file_content
}


function New-SaltMinionScript {
    # Create the salt-minion.bat script
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        # The location to create the script
        [String] $Path
    )
    $content = @(
    ":: Copyright (c) 2021 VMware, Inc. All rights reserved.",
    "",
    ":: Script for starting the Salt-Minion"
    ":: Accepts all parameters that Salt-Minion Accepts",
    "@ echo off",
    "",
    ":: Define Variables",
    "Set SaltBin=%~dp0\salt\salt.exe",
    "",
    "net session >nul 2>&1",
    'if %errorLevel%==0 (',
    "    :: Launch Script",
    "    `"%SaltBin%`" minion %*",
    ") else (",
    "    echo ***** This script must be run as Administrator *****",
    ")"
    )
    $file_content = $content -join "`r`n"
    Set-Content -Path $Path -Value $file_content
}


function Install-SaltMinion {
    # Installs the tiamat build of the salt minion. Performs the following:
    # - Expands the zipfile into C:\Program Files\Salt Project
    # - Copies the helper scripts into C:\ProgramFiles\Salt Project\Salt
    # - Registers the salt-minion service
    # - Adds the new location to the system path
    #
    # Error:
    #     Sets the failed status and exits with an error code

    # 1. Unzip into Program Files
    Write-Log "Unzipping salt (this may take a few minutes)" -Level info
    Expand-ZipFile -ZipFile "$base_salt_install_location\$salt_web_file_name" `
                   -Destination $base_salt_install_location

    # 2. Copy the scripts into Program Files
    Write-Log "Copying scripts" -Level info
    try {
        Write-Log "Creating $salt_dir\salt-call.bat" -Level debug
        New-SaltCallScript -Path "$salt_dir\salt-call.bat"
    } catch {
        Write-Log "Failed creating $salt_dir\salt-call.bat" -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }
    try {
        Write-Log "Creating $salt_dir\salt-minion.bat" -Level debug
        New-SaltMinionScript -Path "$salt_dir\salt-minion.bat"
    } catch {
        Write-Log "Failed creating $salt_dir\salt-minion.bat" -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }

    # 3. Register the service
    Write-Log "Installing salt-minion service" -Level info
    & $ssm_bin install salt-minion "$salt_bin" `
                "minion -c """"$salt_config_dir""""" *> $null
    & $ssm_bin set salt-minion Description Salt Minion from VMtools *> $null
    & $ssm_bin set salt-minion Start SERVICE_AUTO_START *> $null
    & $ssm_bin set salt-minion AppStopMethodConsole 24000 *> $null
    & $ssm_bin set salt-minion AppStopMethodWindow 2000 *> $null
    & $ssm_bin set salt-minion AppRestartDelay 60000 *> $null
    if (!(Get-Service salt-minion -ErrorAction SilentlyContinue).Status) {
        Write-Log "Failed to install salt-minion service" -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    } else {
        Write-Log "Finished installing salt-minion service" -Level debug
    }

    # 4. Modify the system path
    Write-Log "Adding salt to the path" -Level info
    Add-SystemPathValue -Path $salt_dir
}


function Remove-SaltMinion {
    # Uninstall the salt minion. Performs the following steps:
    # - Stop the salt-minion service
    # - Remove the salt-minion service
    # - Remove the directories in Program Files and ProgramData
    # - Remove the registry entries
    # - Remove the entry from the system path
    #
    # Error:
    #     Sets the failed status and exits with error code 1

    # Does the service exist
    $service = Get-Service -Name salt-minion -ErrorAction SilentlyContinue

    if ($service -eq $null) {
        Write-Log "salt-minion service not found" -Level warning
    } else {

        # Stop the minion service
        Stop-MinionService

        # Delete the service
        Write-Log "Uninstalling salt-minion service" -Level info
        $service = Get-WmiObject -Class Win32_Service `
                                 -Filter "Name='salt-minion'"
        $service.delete() *> $null
        if ((Get-Service salt-minion -ErrorAction SilentlyContinue).Status) {
            Write-Log "Failed to uninstall salt-minion service" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        } else {
            Write-Log "Finished uninstalling salt-minion service" -Level debug
        }
    }

    # 3. Remove the files
    # Do this in a for loop for logging
    foreach ($item in $file_dirs_to_remove) {
        Remove-FileOrFolder -Path $item
    }

    # 4. Remove entry from the path
    Remove-SystemPathValue -Path $salt_dir
}


function Reset-SaltMinion {
    # Resets the salt-minion environment in preperation for imaging. Performs
    # the following steps:
    # - Remove minion_id file
    # - Randomize the minion id in the minion config
    # - Remove the minion public and private keys

    Write-Log "Resetting salt minion" -Level info

    Remove-FileOrFolder "$salt_config_file\minion_id"

    # Comment out id: in the minion config
    $new_content = [System.Collections.ArrayList]::new()
    if (Test-Path -Path "$salt_config_file") {
        Write-Log "Searching minion config file for id" -Level debug
        foreach ($line in Get-Content $salt_config_file) {
            if ($line -match "^id:.*$") {
                Write-Log "Commenting out the id" -Level debug
                $new_content.Add("#" + $line) | Out-Null
                $random_id = Get-RandomizedMinionId -Prefix $line.Split("")[1]
                $new_content.Add("id: $random_id") | Out-Null
            } else {
                $new_content.Add($line) | Out-Null
            }
        }
        $config_content = $new_content -join "`r`n"
        Write-Log "Writing new minion config"
        $Error.Clear()
        try {
            Set-Content -Path $salt_config_file -Value $config_content
        } catch {
            Write-Log "Failed to write new minion config : $Error" -Level error
            exit $STATUS_CODES["scriptFailed"]
        }
    }

    # Remove minion keys (minion.pem and minion.pub"
    Remove-FileOrFolder -Path "$salt_pki_dir\minion.pem"
    Remove-FileOrFolder -Path "$salt_pki_dir\minion.pub"

    Write-Log "Salt minion reset successfully" -Level info
}


function Install {
    Write-Log "Installing salt minion" -Level info
    Set-Status installing
    Get-SaltFromWeb
    Install-SaltMinion
    Add-MinionConfig
    Start-MinionService
    Set-Status installed
    Write-Log "Salt minion installed successfully" -Level info
}


function Remove {
    Write-Log "Removing salt minion" -Level info
    Set-Status removing
    Remove-SaltMinion
    Set-Status notInstalled
    Write-Log "Salt minion removed successfully" -Level info
}


################################### MAIN #######################################

# Allow importing for testing
if (($Action) -and ($Action.ToLower() -eq "test")) {
    exit $STATUS_CODES["scriptSuccess"]
}

try {
    # Let's confirm dependencies
    if (!(Confirm-Dependencies)) {
        Write-Host "Missing script dependencies"
        $exit_code = $STATUS_CODES["scriptFailed"]
        exit $exit_code
    }

    # Let's make sure there's not already a standard salt installation on the
    # system
    if (Find-StandardSaltInstallation) {
        Write-Host "Found an existing salt installation on the system."
        $exit_code = $STATUS_CODES["scriptFailed"]
        exit $exit_code
    }

    # Check for Action. If not specified on the command line, get it from
    # guestVars
    if ($Install) { $Action = "add" }
    if ($Status) { $Action = "status" }
    if ($Depend) { $Action = "depend" }
    if ($Clear) { $Action = "clear" }
    if ($Remove) { $Action = "remove" }
    if (!($Action)) {
        $Action = Get-GuestVars -GuestVarsPath $guestvars_salt
        Write-Log "Action from GuestVars: $Action" -Level debug
    }

    # Validate the action
    if ("add", "status", "depend", "clear", "remove" -notcontains $Action) {
        Write-Log "Invalid action: $Action" -Level error
        Write-Host "Invalid action: $Action" -ForgroundColor Red
        $exit_code = $STATUS_CODES["scriptFailed"]
        exit $exit_code
    }

    if ($Action) {
        switch ($Action.ToLower()) {
            "depend" {
                # If we've gotten this far, dependencies have been confirmed
                Write-Host "Found all dependencies"
                $exit_code = $STATUS_CODES["scriptSuccess"]
                exit $exit_code
            }
            "add" {
                # If status is installed, installing, or removing, bail out
                $current_status = Get-Status
                if ($STATUS_CODES.keys -notcontains $current_status) {
                    $msg = "Unknown status code: $current_status"
                    Write-Host $msg -Level error
                    $exit_code = $STATUS_CODES["scriptFailed"]
                    exit $exit_code
                }
                switch ($current_status) {
                    $STATUS_CODES["installed"] {
                        Write-Host "Already installed"
                        $exit_code = $STATUS_CODES["scriptSuccess"]
                        exit $exit_code
                    }
                    $STATUS_CODES["installing"] {
                        Write-Host "Installation in progress"
                        $exit_code = $STATUS_CODES["scriptSuccess"]
                        exit $exit_code
                    }
                    $STATUS_CODES["removing"] {
                        Write-Host "Removal in progress"
                        $exit_code = $STATUS_CODES["scriptSuccess"]
                        exit $exit_code
                    }
                }
                Install
                Write-Host "Salt minion installed successfully"
                $exit_code = $STATUS_CODES["scriptSuccess"]
                exit $exit_code
            }
            "remove" {
                # If status is installing, notInstalled, or removing, bail out
                $current_status = Get-Status
                if ($STATUS_CODES.keys -notcontains $current_status) {
                    $msg = "Unknown status code: $current_status"
                    Write-Host $msg -Level error
                    $exit_code = $STATUS_CODES["scriptFailed"]
                    exit $exit_code
                }
                switch ($current_status) {
                    $STATUS_CODES["installing"] {
                        Write-Host "Installation in progress"
                        $exit_code = $STATUS_CODES["scriptSuccess"]
                        exit $exit_code
                    }
                    $STATUS_CODES["notInstalled"] {
                        Write-Host "Already uninstalled"
                        $exit_code = $STATUS_CODES["scriptSuccess"]
                        exit $exit_code
                    }
                    $STATUS["removing"] {
                        Write-Host "Removal in progress"
                        $exit_code = $STATUS_CODES["scriptSuccess"]
                        exit $exit_code
                    }
                }
                Remove
                Write-Host "Salt minion removed successfully"
                $exit_code = $STATUS_CODES["scriptSuccess"]
                exit $exit_code
            }
            "clear" {
                # If not installed (0), bail out
                $current_status = Get-Status
                if ($STATUS_CODES.keys -notcontains $current_status) {
                    $msg = "Unknown status code: $current_status"
                    Write-Host $msg -Level error
                    $exit_code = $STATUS_CODES["scriptFailed"]
                    exit $exit_code
                }
                if ($current_status -ne $STATUS_CODES["installed"]) {
                    Write-Host "Not installed. Reset will not continue"
                    $exit_code = $STATUS_CODES["scriptSuccess"]
                    exit $exit_code
                }
                Reset-SaltMinion
                Write-Host "Salt minion reset successfully"
                $exit_code = $STATUS_CODES["scriptSuccess"]
                exit $exit_code
            }
            "status" {
                $exit_code = Get-Status
                if ($STATUS_CODES.keys -notcontains $exit_code) {
                    Write-Host "Unknown status code: $exit_code " -Level error
                    $exit_code = $STATUS_CODES["scriptFailed"]
                    exit $exit_code
                }
                Write-Host "Found status: $($STATUS_CODES[$exit_code])"
                exit $exit_code
            }
            default {
                $action_list = "install, remove, depend, clear, status"
                $msg = "Invalid action: $Action - Must be one of [$action_list]"
                Write-Host $msg
                $exit_code = $STATUS_CODES["scriptFailed"]
                exit $exit_code
            }
        }
    } else {
        # No action specified
        Write-Log "No action specified" -Level error
        $exit_code = $STATUS_CODES["scriptFailed"]
        exit $exit_code
    }
} finally {
    if (!($exit_code) -and ($exit_code -ne $STATUS_CODES["scriptSuccess"])) {
        Write-Host "Script Terminated..."
        exit $STATUS_CODES["scriptTerminated"]
    }
}
