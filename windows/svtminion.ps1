# Copyright (c) 2021 VMware, Inc. All rights reserved.

<#
.SYNOPSIS
VMware Tools script for managing the Salt minion on a Windows guest

.DESCRIPTION
This script manages the Salt minion on a Windows guest. The minion is a tiamat
build hosted on https://repo.saltproject.io/salt/vmware-tools-onedir. You can
install the minion, remove it, check script dependencies, get the Salt minion
installation status, and reset the Salt minion configuration.

When this script is run without any parameters, the action is obtained from
guestVars (if present). If no action is found, the script will exit with a
scriptFailed exit code.

If an action is passed on the CLI or found in guestVars, minion config options
(master=198.51.100.1, etc.) are queried from guestVars. Config options are then
obtained from tools.conf. Config options obtained from tools.conf will overwrite
any config options obtained from guestVars with the same name. Config options
passed on the CLI will overwrite any config options obtained from either of the
previous two methods. The order of precedence is CLI options first, then
tools.conf, and finally guestVars.

This script returns exit codes to signal its success or failure. The exit codes
are as follows:

0 - scriptSuccess
126 - scriptFailed
130 - scriptTerminated

If the Status option is passed, then the exit code will signal the status of the
Salt minion installation. Status exit codes are as follows:

100 - installed
101 - installing
102 - notInstalled
103 - installFailed
104 - removing
105 - removeFailed

NOTE: This script must be run with Administrator privileges

.EXAMPLE
PS>svtminion.ps1 -Install
PS>svtminion.ps1 -Install -MinionVersion 3004-1 master=192.168.10.10 id=dev_box

.EXAMPLE
PS>svtminion.ps1 -Clear

.EXAMPLE
PS>svtminion.ps1 -Status

.EXAMPLE
PS>svtminion.ps1 -Depend

.EXAMPLE
PS>svtminion.ps1 -Remove -LogLevel debug

#>

    [CmdletBinding(DefaultParameterSetName = "Install")]
param(

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Alias("i")]
    # Downloads, installs, and starts the salt-minion service. Exits with
    # scriptFailed exit (126) code under the following conditions:
    # - Existing Standard Salt Installation detected
    # - Unknown status found
    # - Installation in progress
    # - Removal in progress
    # - Installation failed
    # - Missing script dependencies
    #
    # Exits with scriptSuccess exit code (0) under the following conditions:
    # - Installed successfully
    # - Already installed
    [Switch] $Install,

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Alias("m")]
    # The version of Salt minion to install. Default is "latest".
    [String] $MinionVersion="latest",

    [Parameter(Mandatory=$false, ParameterSetName="Install",
            Position=0, ValueFromRemainingArguments=$true)]
    # Any number of minion config options specified by the name of the config
    # option as found in Salt documentation. All options will be lowercased and
    # written to the minion config as passed. All values are in the key=value
    # format. For example: master=localhost
    [String[]] $ConfigOptions,

    [Parameter(Mandatory=$false, ParameterSetName="Remove")]
    [Alias("r")]
    # Stops and uninstalls the salt-minion service. Exits with scriptFailed exit
    # code (126) under the following conditions:
    # - Unknown status found
    # - Installation in progress
    # - Removal in progress
    # - Installation failed
    # - Missing script dependencies
    #
    # Exits with scriptSuccess exit code (0) under the following conditions:
    # - Removed successfully
    # - Already removed
    [Switch] $Remove,

    [Parameter(Mandatory=$false, ParameterSetName="Clear")]
    [Alias("c")]
    # Resets the salt-minion by randomizing the minion ID and removing the
    # minion keys. The randomized minion ID will be the old minion ID, an
    # underscore, and 5 random digits.
    #
    # Exits with scriptFailed exit code (126) under the following conditions:
    # - Unknown status found
    # - Missing script dependencies
    #
    # Exits with scriptSuccess exit code (0) under the following conditions:
    # - Cleared successfully
    # - Not installed
    [Switch] $Clear,

    [Parameter(Mandatory=$false, ParameterSetName="Status")]
    [Alias("s")]
    # Gets the status of the Salt minion installation. This command returns an
    # exit code that corresponds to one of the following:
    # 100 - installed
    # 101 - installing
    # 102 - notInstalled
    # 103 - installFailed
    # 104 - removing
    # 105 - removeFailed
    #
    # Exits with scriptFailed exit code (126) under the following conditions:
    # - Unknown status found
    # - Missing script dependencies
    [Switch] $Status,

    [Parameter(Mandatory=$false, ParameterSetName="Depend")]
    [Alias("d")]
    # Ensures the required dependencies are available. Exits with a scriptFailed
    # exit code (126) if any dependencies are missing. Exits with a
    # scriptSuccess exit code (0) if all dependencies are present.
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
    # suppresses all logging output. Available options are:
    # - silent
    # - error
    # - warning
    # - info
    # - debug
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
$Script:ErrorActionPreference = "Stop"
$Script:ProgressPreference = "SilentlyContinue"
$Script:log_cleared = $false
$download_retry_count = 5
$script_date = Get-Date -Format "yyyyMMddHHmmss"
$script_name = $MyInvocation.MyCommand.Name
$script_log_dir = "$env:SystemRoot\Temp"
# log file name: vmware-svtminion-{0}-20211019152012.log
$script_log_base_name = "vmware-$($script_name.Split(".")[0])-{0}"
$script_log_name = "$script_log_base_name-$script_date.log"
$script_log_file_count = 5
$action_list = @("install", "remove", "depend", "clear", "status")

################################# VARIABLES ####################################
# Repository locations and names
$salt_name = "salt"
$base_url = "https://repo.saltproject.io/salt/vmware-tools-onedir"

# Salt file and directory locations
$base_salt_install_location = "$env:ProgramFiles\Salt Project"
$salt_dir = "$base_salt_install_location\$salt_name"
$salt_bin = "$salt_dir\salt\salt.exe"
$ssm_bin = "$salt_dir\ssm.exe"

$base_salt_config_location = "$env:ProgramData\Salt Project"
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

try{
    $reg_key = Get-ItemProperty $vmtools_base_reg
} catch {
    $msg = "Unable to find valid VMware Tools installation : $_"
    Write-Host $msg -ForeGroundColor Red
    exit $STATUS_CODES["scriptFailed"]
}
if (!($reg_key.PSObject.Properties.Name -contains "InstallPath")) {
    $msg = "Unable to find valid VMware Tools installation"
    Write-Host $msg -ForeGroundColor Red
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


function Clear-OldLogs {

    if ($Script:log_cleared) {
        return
    }

    $filter = "*$script_log_base_name*.log" -f $Action.ToLower()
    $files = Get-ChildItem $script_log_dir -Filter $filter | Sort-Object
    $total_files = $files.Count
    try {
        foreach ($file in $files) {
            if ($total_files -ge $script_log_file_count) {
                # Remove the file/dir/synlink/junction
                $file_obj = Get-Item -Path $file.FullName
                if ($file_obj -is [System.IO.DirectoryInfo]) {
                    [System.IO.Directory]::Delete(`
                        $file.FullName, $true) | Out-Null
                } else {
                    [System.IO.File]::Delete($file.FullName) | Out-Null
                }
                $total_files -= 1
            } else {
                break
            }
        }
    } finally {
        $Script:log_cleared = $true
    }
}


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
    $script_pid = $PID + " " * (5 - $PID.Length)

    if ( $LOG_LEVELS[$Level.ToLower()] -le $log_level_value ) {
        $date_time = Get-Date -Format "yyyy-MM-dd:HH:mm:ss.ffff"
        $timestamp = Get-Date -Format "HH:mm:ss.ffff"
        $log_message = "[$timestamp] [$level_text] $Message"
        $log_file_message = "[$date_time] [$script_pid] [$level_text] $Message"
        if (!(Test-Path($script_log_dir))) {
            Write-Host "[$timestamp] [INFO   ] : Creating log file directory"
            New-Item -Path $script_log_dir -Type Directory | Out-Null
        }
        if (!($action_list -contains $Action)) { $Action = "Default" }

        Clear-OldLogs

        $log_path = "$script_log_dir\$script_log_name" -f $Action
        Add-Content -Path $log_path.ToLower() -Value $log_file_message
        switch ($Level) {
            "ERROR" { $color = "Red" }
            "WARNING" { $color = "Yellow" }
            default { $color = "White"}
        }
        Write-Host $log_message -ForegroundColor $color
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
    foreach ($process in $processes) {
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
    try {
        $current_status = Get-ItemPropertyValue `
                            -Path $vmtools_base_reg `
                            -Name $vmtools_salt_minion_status_name
        Write-Log "Found status code: $current_status" -Level debug
    } catch {
        Write-Log "Key not set, not installed : $_" -Level debug
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
        try {
            Remove-ItemProperty -Path $vmtools_base_reg `
                                -Name $vmtools_salt_minion_status_name
            $key = "$vmtools_base_reg\$vmtools_salt_minion_status_name"
            Write-Log "Removed reg key: $key" -Level debug
            Write-Log "Set status to $NewStatus" -Level debug
        } catch [System.Management.Automation.PSArgumentException] {
            Write-Log "Reg key not present: $key" -Level debug
            Write-Log "Status already set to: $NewStatus" -Level debug
        } catch {
            Write-Log "Error removing reg key: $_" -Level error
            exit $STATUS_CODES["scriptFailed"]
        }
    } else {
        try {
            New-ItemProperty -Path $vmtools_base_reg `
                             -Name $vmtools_salt_minion_status_name `
                             -Value $status_code `
                             -Force | Out-Null
            Write-Log "Set status to $NewStatus" -Level debug
        } catch {
            Write-Log "Error writing status: $_" -Level error
            exit $STATUS_CODES["scriptFailed"]
        }
    }
}


function Set-FailedStatus {
    # Sets the status if either add or remove fails, each sets a different
    # status if it fails
    switch ($Action.ToLower()) {
        "install" { Set-Status installFailed }
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
    $parent_dir = Split-Path $OutFile
    if ( !( Test-Path $parent_dir )) {
        New-Item $parent_dir -Type Directory | Out-Null
    }
    $url_name = $Url.SubString($Url.LastIndexOf('/'))

    $tries = 1
    $success = $false
    while (!$success){
        try {
            # Download the file
            $msg = "Downloading (try: $tries/$download_retry_count): $url_name"
            Write-Log $msg -Level debug
            Invoke-WebRequest -Uri $Url -OutFile $OutFile
        } catch {
            Write-Log "Error downloading: $Url" -Level warning
            Write-Log "Error message: $_" -Level warning
        } finally {
            $tries++
            if ((Test-Path -Path "$OutFile") `
                -and `
                ((Get-Item "$OutFile").Length -gt 0kb
            )) {
                Write-Log "Finished downloading: $url_name" -Level debug
                $success = $true
            } else {
                if ($tries -gt $download_retry_count) {
                    Write-Log "Retry count exceeded" -Level error
                    Set-FailedStatus
                    exit $STATUS_CODES["scriptFailed"]
                }
                Write-Log "Trying again after 10 seconds" -Level warning
                Start-Sleep -Seconds 10
            }
        }
    }
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
    #     Sets the failed status and exits with a scriptFailed exit code
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
            Write-Log "Failed to unzip $ZipFile : $_" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        }
    } else {
        # This method will work with older versions of powershell, but it is
        # slow
        $objShell = New-Object -Com Shell.Application
        $objZip = $objShell.NameSpace($ZipFile)
        try{
            foreach ($item in $objZip.Items()) {
                $objShell.Namespace($Destination).CopyHere($item, 0x14)
            }
        } catch {
            Write-Log "Failed to unzip $ZipFile : $_" -Level error
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
    $regex_path = $Path.Replace("\", "\\")
    foreach ($item in $current_path.Split(";")) {
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
    try{
        Write-Log "Updating system path" -Level debug
        Set-ItemProperty -Path $key -Name Path -Value $new_path
    } catch {
        Write-Log "Failed to add $Path the system path" -Level warning
        Write-Log "Tried to write: $new_path" -Level warning
        Write-Log "Error message: $_" -Level warning
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
    $regex_path = $Path.Replace("\", "\\")
    $removed = 0
    foreach ($item in $current_path.Split(";")) {
        # Don't add if we find the new path
        if ($item -imatch "^$regex_path(\\)?$") {
            Write-Log "Removing target path: $Path" -Level debug
            $removed = 1
        } else {
            # Add the item to our new path array
            $new_path_list.Add($item) | Out-Null
        }
    }

    if ($removed) {
        $new_path = $new_path_list -join ";"
        try {
            Write-Log "Updating system path" -Level debug
            Set-ItemProperty -Path $key -Name Path -Value $new_path
        } catch {
            $msg = "Failed to remove $Path from the system path: $new_path"
            Write-Log $msg -Level warning
            Write-Log "Tried to write: $new_path" -Level warning
            Write-Log "Error message: $_" -level warning
        }
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )

    if (!(Test-Path -Path $Path)) {
        Write-Log "Path not found: $Path" -Level warning
        return
    }

    $tries = 1
    $max_tries = 5
    $success = $false
    while (!$success) {
        $msg = "Removing (try: $tries/$max_tries): $Path"
        Write-Log $msg -Level debug
        try {
            # Remove the file/dir/symlink/junction
            if ((Get-Item -Path $Path) -is [System.IO.DirectoryInfo]) {
                [System.IO.Directory]::Delete($Path, $true) | Out-Null
            } else {
                [System.IO.File]::Delete($Path) | Out-Null
            }
        } catch {
            Write-Log "Error removing: $Path" -Level warning
            Write-Log "Error message: $_" -Level warning
        } finally {
            $tries++
            if (!(Test-Path -Path $Path)) {
                Write-Log "Finished removing $Path" -Level debug
                $success = $true
            } else {
                if ($tries -gt $max_tries) {
                    Write-Log "Retry count exceeded" -Level error
                    Set-FailedStatus
                    exit $STATUS_CODES["scriptFailed"]
                }

                if ((Get-Item -Path $Path) -is [System.IO.DirectoryInfo]) {
                    Write-Log "Taking ownership: $Path" -Level debug
                    takeown /a /r /d Y /f $Path *> $null
                    if ($LASTEXITCODE) {
                        Write-Log "Directory does not exist" -Level debug
                    }
                }

                Write-Log "Trying again after 5 seconds" -Level warning
                Start-Sleep -Seconds 5
            }
        }
    }
}


function Get-GuestVars {
    # Get guestvars data using vmtoolsd.exe
    # They can be set on the host using vmrun.exe
    #
    # vmrun writeVariable "d:\VMWare\Windows Server 2019\Windows Server
    #       2019.vmx" guestVar /vmware.components.salt_minion.args
    #       "master=192.168.0.12 id=test_id"
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

    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
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
    $exitcode = $Process.ExitCode

    if ($exitcode -eq 0) {
        return $stdout.Trim()
    } else {
        return ""
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
        Write-Log "Minion config not passed on CLI" -Level debug
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
        Write-Log "Minion config not defined in guestvars" -Level debug
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
        return @{}
    }

    $ini = @{}

    switch -regex -file $FilePath {
        # [Section]
        "^(?![#,;])\[(.+)\]$" {
            $section = $matches[1]
            $ini[$section.Trim()] = @{}
        }
        # key=value
        "^(?![#,;])(.+?)\s*=(.*)$" {
            $key,$value = $matches[1..2]
            $ini[$section.Trim()][$key.Trim()] = $value.Trim()
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
    if ($config_options.ContainsKey($guestvars_section)) {
        $count = $config_options[$guestvars_section].Count
        Write-Log "Found $count config options" -Level debug
        return $config_options[$guestvars_section]
    } else {
        Write-Log "Minion config not defined in tools.conf" -Level debug
        return @{}
    }
}


function Get-MinionConfig {
    # Get the minion config values to be placed in the minion config file. The
    # Order of priority is as follows:
    # - Get config from GuestVars (defined by VMware Tools)
    # - Get config from tools.conf (defined by VMware Tools - older method),
    #   overwrites guestVars with the same name
    # - Get config from the CLI (options passed to the script), overwrites
    #   guestVars and tools.conf settings with the same name
    # - No config found, use salt minion defaults (master: salt, id: hostname)
    #
    # Used by:
    # - Add-MinionConfig
    #
    # Returns a hash table of options or null if no options found
    Write-Log "Getting minion config" -Level info
    $config_options = @{}
    # Get guestVars config, conflicting values will be overwritten by guestvars
    $gv_config = Get-ConfigGuestVars
    if ($gv_config) {
        foreach ($row in $gv_config.GetEnumerator()) {
            if ($row.Value) {
                $config_options[$row.Name] = $row.Value
            }
        }
    }
    # Get tools.conf config first
    $tc_config = Get-ConfigToolsConf
    if ($tc_config) {
        foreach ($row in $tc_config.GetEnumerator()) {
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


function Get-IsReparsePoint {
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

    $acl = Get-Acl -Path $Path
    $owner = (($acl | Select-Object Owner).Owner).ToLower()
    if ($owner -eq "nt authority\system") {
        return $true
    }
    if ($owner -eq "builtin\administrators") {
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
        [String] $Owner = "BUILTIN\Administrators"
    )

    Write-Log "Setting Security: $Path" -Level info

    Write-Log "Getting ACL: $Path" -Level debug
    $path_acl = Get-Acl -Path $Path

    Write-Log "Setting Sddl" -Level debug
    $Sddl = 'D:PAI(A;OICI;0x1200a9;;;WD)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'
    $path_acl.SetSecurityDescriptorSddlForm($Sddl)

    Write-Log "Setting Owner" -Level debug
    $path_acl.SetOwner([System.Security.Principal.NTAccount]"$Owner")

    Write-Log "Writing New ACL" -Level debug
    Set-Acl -Path $Path -AclObject $path_acl
}


function New-SecureDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $Path
    )
    if (Test-Path -Path $Path) {
        if (Get-IsReparsePoint -Path $Path) {
            Write-Log "Found reparse point: $Path" -Level warning
            Write-Log "Renaming reparse point (.insecure): $Path" -Level warning
            Move-item -Path $Path `
                    -Destination "$Path-$script_date.insecure" | Out-Null
            $msg = "Insecure reparse point renamed: $Path-$script_date.insecure"
            Write-Log $msg -Level debug
        }
    }

    if (Test-Path -Path $Path) {
        if (!(Get-IsSecureOwner -Path $Path)) {
            Write-Log "Found insecure owner: $Path" -Level warning
            Write-Log "Renaming file/dir (.insecure): $Path" -Level warning
            Move-Item -Path $Path `
                    -Destination "$Path-$script_date.insecure" | Out-Null
            $msg = "Insecure file/dir renamed: $Path-$script_date.insecure"
            Write-Log $msg -Level debug
        }
    }

    $tries = 1
    $max_tries = 5
    while ($true) {

        # Remove any existing file or directory if it exists
        if (Test-Path -Path $Path) {
            Write-Log "Removing existing file/directory: $Path" -Level debug
            Remove-FileOrFolder -Path $Path
        }

        $msg = "Creating secure directory (try: $tries/$max_tries): $Path"
        Write-Log $msg -Level debug
        try {
            New-Item -Path $Path -Type Directory | Out-Null
        } catch {
            if ($tries -le $max_tries) {
                $msg = "Failed to create directory: $Path. Trying again..."
                Write-Log $msg -Level warning
                $tries++
                continue
            } else {
                $msg = "Failed to create secure directory. Try limit exceeded."
                Write-Log $msg -Level error
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }

        Set-Security -Path $Path

        if((Get-ChildItem -Path $Path | Measure-Object).Count -ne 0) {
            # Someone is competing with us
            if ($tries -le $max_tries) {
                $msg = "Expected empty directory. Trying again..."
                Write-Log $msg -Level warning
                $tries += 1
                continue
            } else {
                $msg = "Expected empty directory. Try limit exceeded."
                Write-Log $msg -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
        Write-Log "Secure directory created successfully" -Level debug
        break
    }
}


function Add-MinionConfig {
    # Write minion config options to the minion config file

    # New-SecureDirectory will handle reparse points and ownership issues
    New-SecureDirectory -Path $base_salt_config_location

    # Child directories will inherit permissions from the parent
    if ( !( Test-Path -path $salt_root_dir)) {
        New-Item -Path $salt_root_dir -Type Directory | Out-Null
    }
    if ( !( Test-Path -path $salt_config_dir)) {
        New-Item -Path $salt_config_dir -Type Directory | Out-Null
    }

    # Get the minion config
    $config_options = Get-MinionConfig

    if ($config_options.Count -eq 0) {
        Write-Log "No minion config found. Defaults will be used" -Level debug
    }

    # Add file_roots to point to ProgramData
    $config_options["file_roots"] = $salt_root_dir
    $new_content = [System.Collections.ArrayList]::new()
    foreach ($row in $config_options.GetEnumerator()) {
        $new_content.Add("$($row.Name): $($row.Value)") | Out-Null
    }
    $config_content = $new_content -join "`r`n"
    try {
        Write-Log "Writing minion config" -Level info
        Set-Content -Path $salt_config_file -Value $config_content
        Write-Log "Finished writing minion config" -Level debug
    } catch {
        $msg = "Failed to write minion config: $config_content : $_"
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

    try {
        $service = Get-Service -Name $ServiceName
    } catch {
        switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
            "NoServiceFoundForGivenName" {
                # We'll hard fail here because the service is not present
                Write-Log "$ServiceName is not installed" -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
            Default {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
    }

    # Not sure this is needed as the Start-Service cmdlet seems to wait until
    # the service is started before returning
    $tries = 1
    $max_tries = 5
    while ($service.Status -ne "Running") {
        if ($service.Status -eq "Stopped") {
            # Start the minion service
            Write-Log "Starting the $ServiceName service" -Level info
            try {
                Start-Service -Name $ServiceName *> $null
            } catch {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
        $service.Refresh()
        if ($service.Status -eq "Running") {
            Write-Log "Service started successfully" -Level debug
        } else {
            if ($tries -le $max_tries) {
                $msg = "Service not started. Waiting 1 second to try again..."
                Write-Log $msg -Level debug
                $tries += 1
                Start-Sleep -Seconds 1
            } else {
                $msg = "Failed to start the $ServiceName service. "
                $msg += "Exceeded max tries"
                Write-Log $msg -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
    }
}


function Stop-MinionService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [String] $ServiceName = "salt-minion"
    )

    try {
        $service = Get-Service -Name $ServiceName
    } catch {
        switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
            "NoServiceFoundForGivenName" {
                # We'll return here because we don't need to stop a service that
                # isn't installed
                Write-Log "$ServiceName is not installed" -Level info
                return
            }
            Default {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
    }

    # Not sure this is needed as the Stop-Service cmdlet seems to wait until
    # the service is stopped before returning
    $tries = 1
    $max_tries = 5
    while ($service.Status -ne "Stopped") {
        if ($service.Status -eq "Running") {
            # Start the minion service
            Write-Log "Stop the $ServiceName service" -Level info
            try {
                Stop-Service -Name $ServiceName *> $null
            } catch {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
        $service.Refresh()
        if ($service.Status -eq "Stopped") {
            Write-Log "Service stopped successfully" -Level debug
        } else {
            if ($tries -le $max_tries) {
                $msg = "Service not stopped. Waiting 1 second to try again..."
                Write-Log $msg -Level debug
                $tries += 1
                Start-Sleep -Seconds 1
            } else {
                $msg = "Failed to stop the $ServiceName service. "
                $msg += "Exceeded max tries"
                Write-Log $msg -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
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

    # VMware Tools files
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

    return $deps_present
}


function Get-SaltVersion {
    # This function is needed for unit testing
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )
    $ver = . $path\bin\python.exe -E -s $path\bin\Scripts\salt-call --version
    return $ver.Trim("salt-call ")
}


function Find-StandardSaltInstallation {
    # Find an existing standard salt installation
    #
    # Return:
    #     Bool: True if standard installation found, otherwise False

    # Standard locations
    $locations = [System.Collections.ArrayList]::new()
    $locations.Add("C:\salt") | Out-Null

    $locations.Add("$env:ProgramFiles\Salt Project\Salt") | Out-Null

    # Check registry for new style locations
    try{
        $reg_path = "HKLM:\SOFTWARE\Salt Project\salt"
        $dir_path = Get-ItemPropertyValue -Path $reg_path -Name "install_dir"
        $locations.Add($dir_path) | Out-Null
    } catch { }

    # Check for python.exe in locations
    Write-Log "Looking for Standard Installation" -Level info
    $exists = $false
    foreach ($path in $locations) {
        if (Test-Path -Path "$path\bin\python.exe" ) {
            $version = Get-SaltVersion -Path $path
            Write-Log "Standard Installation detected" -Level error
            Write-Log "Version: $version" -Level error
            Write-Log "Path: $path" -Level error
            $exists = $true
            break
        }
    }
    if (!($exists)) {
        Write-Log "Standard Installation not detected" -Level debug
    }
    return $exists
}


function Convert-PSObjectToHashtable {
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )
    if ($null -eq $InputObject) { return $null }

    $is_enum = $InputObject -is [System.Collections.IEnumerable]
    $not_string = $InputObject -isnot [string]
    if ($is_enum -and $not_string) {
        $collection = @(
            foreach ($object in $InputObject) {
                Convert-PSObjectToHashtable $object
            }
        )

        Write-Output -NoEnumerate $collection
    } elseif ($InputObject -is [PSObject]) {
        $hash = @{}

        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = Convert-PSObjectToHashtable $property.Value
        }

        $hash
    } else {
        $InputObject
    }
}


function Get-SaltPackageInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $MinionVersion
    )
    $response = Invoke-WebRequest -Uri "$base_url/repo.json" -UseBasicParsing
    $psobj = $response.Content | ConvertFrom-Json
    $hash = Convert-PSObjectToHashtable $psobj

    $salt_file_name = ""
    $salt_version = ""
    $salt_sha512 = ""
    $search_version = $MinionVersion.ToLower()
    if ($hash.Contains($search_version)) {
        foreach ($item in $hash.($search_version).Keys) {
            if ($item.EndsWith(".zip")) {
                $salt_file_name = $hash.($search_version).($item).name
                $salt_version = $hash.($search_version).($item).version
                $salt_sha512 = $hash.($search_version).($item).SHA512
            }
        }
    }

    if ($salt_file_name -and $salt_version -and $salt_sha512) {
        return @{
            url = @($base_url, $salt_version, $salt_file_name) -join "/";
            hash = $salt_sha512;
            file_name = $salt_file_name
        }
    } else {
        return @{}
    }
}


function Get-SaltFromWeb {
    # Download the salt tiamat zip file from the web and verify the hash
    #
    # Error:
    #     Sets the failed status and exits with a scriptFailed exit code

    # Make sure the download directory exists
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Url,

        [Parameter(Mandatory=$true)]
        [String] $Destination,

        [Parameter(Mandatory=$true)]
        [String] $Hash
    )

    # Download the salt file
    Write-Log "Downloading salt" -Level info
    Get-WebFile -Url $Url -OutFile $Destination

    # Get the hash for the salt file
    $file_hash = (Get-FileHash -Path $Destination -Algorithm SHA512).Hash

    Write-Log "Verifying hash" -Level info
    if ($file_hash -like $Hash) {
        Write-Log "Hash verified" -Level debug
    } else {
        Write-Log "Failed to verify hash:" -Level error
        Write-Log "  - $file_hash" -Level error
        Write-Log "  - $Hash" -Level error
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
    #     Sets the failed status and exits with a scriptFailed exit code

    # 1. Unzip into Program Files
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [String] $Path
    )
    Write-Log "Unzipping salt (this may take a few minutes)" -Level info
    Expand-ZipFile -ZipFile $Path -Destination $base_salt_install_location

    # 2. Copy the scripts into Program Files
    Write-Log "Copying scripts" -Level info
    try {
        Write-Log "Creating $salt_dir\salt-call.bat" -Level debug
        New-SaltCallScript -Path "$salt_dir\salt-call.bat"
    } catch {
        Write-Log "Failed to create $salt_dir\salt-call.bat" -Level error
        Write-Log $_ -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }
    try {
        Write-Log "Creating $salt_dir\salt-minion.bat" -Level debug
        New-SaltMinionScript -Path "$salt_dir\salt-minion.bat"
    } catch {
        Write-Log "Failed to create $salt_dir\salt-minion.bat" -Level error
        Write-Log $_ -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }

    # 3. Register the service
    Write-Log "Installing salt-minion service" -Level info
    & $ssm_bin install salt-minion "$salt_bin" `
                "minion -c """"$salt_config_dir""""" *> $null
    & $ssm_bin set salt-minion Description Salt Minion `
                from VMware Tools *> $null
    & $ssm_bin set salt-minion Start SERVICE_AUTO_START *> $null
    & $ssm_bin set salt-minion AppStopMethodConsole 24000 *> $null
    & $ssm_bin set salt-minion AppStopMethodWindow 2000 *> $null
    & $ssm_bin set salt-minion AppRestartDelay 60000 *> $null

    try {
        $service = Get-Service -Name salt-minion
        Write-Log "salt-minion service installed successfully" -Level debug
    } catch {
        switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
            "NoServiceFoundForGivenName" {
                $msg = "Failed to install salt-minion service"
                Write-Log $msg -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
            Default {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
        }
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
    #     Sets the failed status and exits with a scriptFailed exit code

    # Does the service exist

    try {
        # This command will throw an exception if the service is missing
        $service = Get-Service -Name salt-minion

        # Stop the minion service
        Stop-MinionService

        # Delete the service
        Write-Log "Uninstalling salt-minion service" -Level info
        $service = Get-WmiObject -Class Win32_Service `
                                 -Filter "Name='salt-minion'"
        $service.delete() *> $null

        try {
            # This command will throw an exception if the service is missing
            $service = Get-Service -Name salt-minion

            # If we were able to connect to the service, no exception thrown,
            # then we failed to remove the service
            Write-Log "Failed to uninstall salt-minion service" -Level error
            Set-FailedStatus
            exit $STATUS_CODES["scriptFailed"]
        } catch {
            # This would catch a missing service after the removal meaning the
            # service was removed successfully
            switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
                "NoServiceFoundForGivenName" {
                    $msg = "Finished uninstalling salt-minion service"
                    Write-Log $msg -Level debug
                }
                Default {
                    Write-Log $_ -Level error
                    Set-FailedStatus
                    exit $STATUS_CODES["scriptFailed"]
                }
            }
        }
    } catch {
        # This would catch a missing service before trying to Stop and Remove it
        # That would mean the service is already removed
        switch ($_.FullyQualifiedErrorId.Split(",")[0]) {
            "NoServiceFoundForGivenName" {
                # We'll return here because we don't need to remove a service
                # that isn't installed
                Write-Log "salt-minion service not found" -Level warning
            }
            Default {
                Write-Log $_ -Level error
                Set-FailedStatus
                exit $STATUS_CODES["scriptFailed"]
            }
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
        try {
            Set-Content -Path $salt_config_file -Value $config_content
        } catch {
            Write-Log "Failed to write new minion config : $_" -Level error
            exit $STATUS_CODES["scriptFailed"]
        }
    }

    # Remove minion keys (minion.pem and minion.pub"
    Remove-FileOrFolder -Path "$salt_pki_dir\minion.pem"
    Remove-FileOrFolder -Path "$salt_pki_dir\minion.pub"

    Write-Log "Salt minion reset successfully" -Level info
}


function Install {
    # Set status and update the log
    Write-Log "Installing salt minion" -Level info
    Set-Status installing

    # Make sure the base install location exists
    if ( !( Test-Path -Path $base_salt_install_location) ) {
        Write-Log "Creating directory: $base_salt_install_location" -Level debug
        New-Item -Path $base_salt_install_location -Type Directory | Out-Null
    }

    # Get URL from repo.json
    $info = Get-SaltPackageInfo -MinionVersion $MinionVersion

    if (!$info) {
        $msg = "Failed to get Package Info for Version: $MinionVersion"
        Write-Log $msg -Level error
        Set-FailedStatus
        exit $STATUS_CODES["scriptFailed"]
    }

    $zip_file = "$base_salt_install_location\$($info.file_name)"

    # Download Salt from the Web
    Get-SaltFromWeb -Url $info.url -Destination $zip_file -Hash $info.hash

    # Install the Salt Package
    Install-SaltMinion -Path $zip_file

    # Generate and update the minion config
    Add-MinionConfig

    # Start the Minion Service
    Start-MinionService

    # Update the Status and output the Log
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
function Main {
    # Check for Action. If not specified on the command line, get it from
    # guestVars
    if ($Install) { $Action = "install" }
    if ($Status) { $Action = "status" }
    if ($Depend) { $Action = "depend" }
    if ($Clear) { $Action = "clear" }
    if ($Remove) { $Action = "remove" }
    if (!$Action) {
        # We're not logging yet because we don't know the status
        $Action = Get-GuestVars -GuestVarsPath $guestvars_salt
        if (!$Action) {
            $msg = "No action found in guestVars or specified on CLI"
            Write-Log $msg -Level error
            Write-Host $msg -ForegroundColor Red
            Write-Host "Please specify an action" -ForegroundColor Yellow
            return $STATUS_CODES["scriptFailed"]
        }
        switch ($Action.ToLower()) {
            "present" { $Action = "install" }
            "absent" { $Action = "remove" }
        }
    }

    if (!($action_list -contains $Action.ToLower())) {
        $msg = "Invalid action: $Action - Must be one of [$action_list]"
        Write-Log $msg -Level error
        Write-Host $msg -ForegroundColor Red
        Write-Host "Please specify a valid action" -ForegroundColor Yellow
        return $STATUS_CODES["scriptFailed"]
    }

    # Let's confirm dependencies
    if (!(Confirm-Dependencies)) {
        Write-Log "Missing script dependencies" -Level error
        Write-Host "Missing script dependencies" -ForegroundColor Red
        return $STATUS_CODES["scriptFailed"]
    }

    # Perform the action
    switch ($Action.ToLower()) {
        "depend" {
            # If we've gotten this far, dependencies have been confirmed
            Write-Host "Found all dependencies"
            return $STATUS_CODES["scriptSuccess"]
        }
        "install" {
            # Let's make sure there's not already a standard salt installation
            # on the system
            if (Find-StandardSaltInstallation) {
                $msg = "Found an existing salt installation on the system."
                Write-Log $msg -Level error
                Write-Host $msg -ForegroundColor Red
                return $STATUS_CODES["scriptFailed"]
            }
            # If status is installed, installing, or removing, bail out
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                $msg = "Unknown status code: $current_status"
                Write-Log $msg -Level error
                Write-Host $msg -ForegroundColor Red
                return $STATUS_CODES["scriptFailed"]
            }
            switch ($current_status) {
                $STATUS_CODES["installed"] {
                    Write-Host "Already installed"
                    return $STATUS_CODES["scriptSuccess"]
                }
                $STATUS_CODES["installing"] {
                    Write-Host "Installation in progress"
                    return $STATUS_CODES["scriptFailed"]
                }
                $STATUS_CODES["removing"] {
                    Write-Host "Removal in progress"
                    return $STATUS_CODES["scriptFailed"]
                }
            }
            Install
            Write-Host "Salt minion installed successfully"
            return $STATUS_CODES["scriptSuccess"]
        }
        "remove" {
            # If status is installing, notInstalled, or removing, bail out
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                $msg = "Unknown status code: $current_status"
                Write-Host $msg -Level error
                return $STATUS_CODES["scriptFailed"]
            }
            switch ($current_status) {
                $STATUS_CODES["installing"] {
                    Write-Host "Installation in progress"
                    return $STATUS_CODES["scriptFailed"]
                }
                $STATUS_CODES["notInstalled"] {
                    Write-Host "Already uninstalled"
                    return $STATUS_CODES["scriptSuccess"]
                }
                $STATUS_CODES["removing"] {
                    Write-Host "Removal in progress"
                    return $STATUS_CODES["scriptFailed"]
                }
            }
            Remove
            Write-Host "Salt minion removed successfully"
            return $STATUS_CODES["scriptSuccess"]
        }
        "clear" {
            # If not installed (0), bail out
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                $msg = "Unknown status code: $current_status"
                Write-Host $msg -Level error
                return $STATUS_CODES["scriptFailed"]
            }
            if ($current_status -ne $STATUS_CODES["installed"]) {
                Write-Host "Not installed. Reset will not continue"
                return $STATUS_CODES["scriptSuccess"]
            }
            Reset-SaltMinion
            Write-Host "Salt minion reset successfully"
            return $STATUS_CODES["scriptSuccess"]
        }
        "status" {
            $exit_code = Get-Status
            if ($STATUS_CODES.keys -notcontains $exit_code) {
                Write-Host "Unknown status code: $exit_code"
                return $STATUS_CODES["scriptFailed"]
            }
            Write-Host "Found status: $($STATUS_CODES[$exit_code])"
            return $exit_code
        }
    }
}

# Allow importing for testing
if (($Action) -and ($Action.ToLower() -eq "test")) {
    exit $STATUS_CODES["scriptSuccess"]
}

try {
    $exit_code = Main
    exit $exit_code
} finally {
    if ($null -eq $exit_code) {
        Write-Host "Script Terminated..."
        exit $STATUS_CODES["scriptTerminated"]
    }
}
