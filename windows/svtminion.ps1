# Copyright (c) 2021 VMware, Inc. All rights reserved.

<#
.SYNOPSIS
VMtools script for managing the salt minion on a Windows guest

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


# Salt VMware Tools Integration script for Windows
# for useage run this script with the -h option:
#    powershell -file svtminion.ps1 -h
[CmdletBinding(DefaultParameterSetName = "Install")]
param(

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Alias("i")]
    # Download, install, and start the salt-minion service.
    [Switch] $Install,

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Alias("v")]
    # The version of salt minion to install. Default is 3003.3-1.
    [String] $Version="3003.3-1",

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
    [Switch] $Clear,

    [Parameter(Mandatory=$false, ParameterSetName="Clear")]
    [Alias("p")]
    # The prefix to apply to the randomized minion id. The randomized minion id
    # will be the previx, an underscore, and 5 random digits. The default is
    # "minion". Therfore, the default randomized name will be something like
    # "minion_dkE9l".
    [String] $Prefix = "minion",

    [Parameter(Mandatory=$false, ParameterSetName="Status")]
    [Alias("s")]
    # Get the status of the salt minion installation. This returns a numeric
    # value that corresponds as follows:
    # 0 - installed
    # 1 - installing
    # 2 - notInstalled
    # 3 - installFailed
    # 4 - removing
    # 5 - removeFailed
    [Switch] $Status,

    [Parameter(Mandatory=$false, ParameterSetName="Depend")]
    [Alias("d")]
    # Ensure the required dependencies are available. Exits with an error code
    # if any dependencies are missing.
    [Switch] $Depend,

    [Parameter(Mandatory=$false, ParameterSetName="Install")]
    [Parameter(ParameterSetName="Clear")]
    [Parameter(ParameterSetName="Status")]
    [Parameter(ParameterSetName="Depend")]
    [Parameter(ParameterSetName="Remove")]
    [Alias("l")]
    [ValidateSet("silent", "error", "warning", "info", "debug", IgnoreCase=$true)]
    [String]
    # Sets the log level to display and log. Default is error. Silent suppresses
    # all logging output
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
    $Help

)


################################ REQUIREMENTS ##################################
# Make sure the script is run as Administrator
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
if (!($Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))) {
    Write-Host "This script must run as Administrator" -ForegroundColor Red
    exit 126
}


################################# LOGGING ######################################
$LOG_LEVELS = @{"silent" = 0; "error" = 1; "warning" = 2; "info" = 3; "debug" = 4}
$log_level_value = $LOG_LEVELS[$LogLevel.ToLower()]

################################# SETTINGS #####################################
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$download_retry_count = 5
$current_date = Get-Date -Format "yyyy-MM-dd"
$script_name = $MyInvocation.MyCommand.Name
$script_log_dir = "$env:ProgramData\VMware\logs"

################################# VARIABLES ####################################
# Repository locations and names
$salt_name = "salt"
$salt_version = $Version
$base_url = "https://repo.saltproject.io/salt/vmware-tools-onedir"
$salt_web_file_name = "$salt_name-$salt_version-windows-amd64.zip"
$salt_web_file_url = "$base_url/$salt_version/$salt_web_file_name"
$salt_hash_name = "$salt_name-$salt_version" + "_SHA512"
$salt_hash_url = "$base_url/$salt_version/$salt_hash_name"

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

$Error.Clear()
try{
    $reg_key = Get-ItemProperty $vmtools_base_reg
} catch {
    Write-Host "Unable to find valid VMtools installation : $Error" -ForeGroundColor Red
    exit 126
}
if (!($reg_key.PSObject.Properties.Name -contains "InstallPath")) {
    Write-Host "Unable to find valid VMtools installation" -ForeGroundColor Red
    exit 126
}

## VMware file and directory locations
$vmtools_base_dir = Get-ItemPropertyValue -Path $vmtools_base_reg -Name "InstallPath"
$vmtools_conf_dir = "$env:ProgramData\VMware\VMware Tools"
$vmtools_conf_file = "$vmtools_conf_dir\tools.conf"
$vmtoolsd_bin = "$vmtools_base_dir\vmtoolsd.exe"

## VMware guestVars file and directory locations
$guestvars_base = "guestinfo./vmware.components"
$guestvars_section = "salt_minion"
$guestvars_salt = "$guestvars_base.$guestvars_section"
$guestvars_salt_args = "$guestvars_salt.args"

$STATUS_CODES = @{
    "installed" = 0;
    "installing" = 1;
    "notInstalled" = 2;
    "installFailed" = 3;
    "removing" = 4;
    "removeFailed" = 5;
    0 = "installed";
    1 = "installing";
    2 = "notInstalled";
    3 = "installFailed"
    4 = "removing";
    5 = "removeFailed";
}


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
        Add-Content "$script_log_dir\vmware-$base_name-$current_date.log" $log_file_message
        switch ($Level) {
            "ERROR" { $color = "Red" }
            "WARNING" { $color = "Yellow" }
            default { $color = "White"}
        }
        if ($log_level_value -ge 1 ) {
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
    $processes = Get-WmiObject Win32_Process -Filter "Name='powershell.exe' AND CommandLine LIKE '%$script_name%'" | Select-Object CommandLine,ProcessId

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
        $true
    } else {
        Write-Log "Running instance not detected" -Level debug
        $false
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
        $current_status = Get-ItemPropertyValue -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
        Write-Log "Found status code: $current_status" -Level debug
    } catch {
        Write-Log "Key not set, not installed : $Error" -Level debug
        $current_status = 2
    }

    # If status is 1 or 4 (installing or removing) but there isn't another script
    # running, then the status is installFailed or removeFailed
    if ((1, 4 -contains $current_status) -and !($script_running_status)) {
        switch ($current_status) {
            1 {
                Write-Log "Found failed install" -Level debug
                $current_status = 3
            }
            4 {
                Write-Log "Found failed remove" -Level debug
                $current_status = 5
            }
        }
    }

    if ($STATUS_CODES.keys -contains $current_status) {
        $status_lookup = $STATUS_CODES[$current_status]
        Write-Log "Found status: $status_lookup" -Level debug
    } else {
        Write-Log "Unknown status code: $current_status" -Level debug
    }
    $current_status
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
        [ValidateSet("installed", "installing", "notInstalled", "installFailed", "removing", "removeFailed")]
        [String] $NewStatus
    )

    Write-Log "Setting status: $NewStatus" -Level info
    $status_code = $STATUS_CODES[$NewStatus]
    # If it's notInstalled, just remove the propery name
    if ($status_code -eq 2) {
        $Error.Clear()
        try{
            Remove-ItemProperty -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name
            Write-Log "Removed reg key: $vmtools_base_reg\$vmtools_salt_minion_status_name" -Level debug
            Write-Log "Set status to $NewStatus" -Level debug
        } catch {
            Write-Log "Error removing reg key: $Error" -Level error
            exit 126
        }
    } else {
        $Error.Clear()
        try {
            New-ItemProperty -Path $vmtools_base_reg -Name $vmtools_salt_minion_status_name -Value $status_code -Force | Out-Null
            Write-Log "Set status to $NewStatus" -Level debug
        } catch {
            Write-Log "Error writing status: $Error" -Level error
            exit 126
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
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls,Tls11,Tls12'
    $url_name = $Url.SubString($Url.LastIndexOf('/'))

    $tries = 1
    $success = $false
    do {
        $Error.Clear()
        try {
            # Download the file
            Write-Log "Downloading (try: $tries/$download_retry_count): $url_name" -Level debug
            Invoke-WebRequest -Uri $Url -OutFile $OutFile
        } catch {
            Write-Log "Error downloading: $Url" -Level warning
            Write-Log "Error message: $Error" -Level warning
        } finally {
            if ((Test-Path -Path "$OutFile") -and ((Get-Item "$OutFile").Length -gt 0kb)) {
                Write-Log "Finished downloading: $url_name" -Level debug
                $success = $true
            } else {
                $tries++
                if ($tries -gt $download_retry_count) {
                    Write-Log "Retry count exceeded" -Level error
                    Set-FailedStatus
                    exit 126
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
    foreach ($lines in $lines) {
        $file_hash, $file_name = $lines -split "\s+"
        if ($FileName -eq $file_name) {
            Write-Log "Found hash: $file_hash" -Level debug
            return $file_hash
        }
    }
    Write-Log "No hash found for: $FileName" -Level error
    Set-FailedStatus
    exit 126
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
            exit 126
        }
    } else {
        # This method will work with older versions of powershell, but it is slow
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
            exit 126
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

    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"

    # Make sure the target folder exists
    Write-Log "Ensuring target path exists" -Level debug
    if (!(Test-Path $Path)) {
        Write-Log "Target path does not exist: $Path" -Level warning
    }

    Write-Log "Getting current system path" -Level debug
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
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
        Set-ItemProperty -Path $path_reg_key -Name Path -Value $new_path
    } catch {
        Write-Log "Failed to add $Path the system path" -Level error
        Write-Log "Tried to write: $new_path" -Level error
        Write-Log "Error message: $Error" -Level error
        Set-FailedStatus
        exit 126
    }
}


function Remove-SystemPathValue {
    # Removes the specified target path from the system path environment variable
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

    $path_reg_key = "HKLM:\System\CurrentControlSet\Control\Session Manager\Environment"

    Write-Log "Getting current system path" -Level debug
    $current_path = (Get-ItemProperty -Path $path_reg_key -Name Path).Path
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
        Set-ItemProperty -Path $path_reg_key -Name Path -Value $new_path
    } catch {
        Write-Log "Failed to remove $Path from the system path: $new_path" -Level error
        Write-Log "Tried to write: $new_path" -Level error
        Write-Log "Error message: $Error" -level error
        Set-FailedStatus
        exit 126
    }
}


function Remove-FileOrFolder {
    # Removes a file or a folder recursively from the system. Takes ownership
    # of the file or directory before removing
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
                Write-Log "Removing (try: $tries/$max_tries): $Path" -Level debug
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
                        exit 126
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
    #         - guestinfo.vmware.components.salt_minion : The action for this script
    #         - guestinfo.vmware.components.salt_minion.args : Minion config options
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
        Write-Log "Value found for $GuestVarsPath : $($stdout.Trim())" -Level debug
        $stdout.Trim()
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
        _parse_config $ConfigOptions
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
        _parse_config $config_options
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

    $ini = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::OrdinalIgnoreCase)

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
    $ini
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
        $config_options[$guestvars_section]
    } else {
        Write-Log "Minion config not defined in tools.conf" -Level warning
    }
}


function Get-MinionConfig {
    # Get the minion config values to be place in the minion config file. The
    # Order of priority is as follows:
    # - Get config from tools.conf (defined by VMtools - older method)
    # - Get config from GuestVars (defined by VMtools), overwrites matching tools.conf
    # - Get config from the CLI (options passed to the script), overwrites matching guestVars
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
    $config_options
}


function Add-MinionConfig {
    # Write minion config options to the minion config file

    # Make sure the config directory exists
    if (!(Test-Path($salt_config_dir))) {
        Write-Log "Creating config directory: $salt_config_dir" -Level debug
        New-Item -Path $salt_config_dir -ItemType Directory | Out-Null
    }
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
    $config_content = $new_content -join "`n"
    $Error.Clear()
    try {
        Write-Log "Writing minion config" -Level info
        Set-Content -Path $salt_config_file -Value $config_content
        Write-Log "Finished writing minion config" -Level debug
    } catch {
        Write-Log "Failed to write minion config: $config_content : $Error" -Level error
        Set-FailedStatus
        exit 126
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
        exit 126
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
        exit 126
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
    $rand_string = ( -join ($chars | Get-Random -Count $Length | % {[char]$_} ) )
    -join ($Prefix, "_", $rand_string)
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

    # Check for VMware registry location for storing status
    Write-Log "Looking for valid VMtools installation" -Level debug
    try {
        $reg_key = Get-ItemProperty $vmtools_base_reg
        if (!($reg_key.PSObject.Properties.Name -contains "InstallPath")) {
            Write-Log "Unable to find valid VMtools installation" -Level error
            $deps_present = $false
        }
    } catch {
        Write-Log "Unable to find $vmtools_base_reg" -Level error
        $deps_present = $false
    }

    # VMtools files
    # Files required by this script
    $salt_dep_files = @{}
    $salt_dep_files["vmtoolsd.exe"] = $vmtools_base_dir
    $salt_dep_files["salt-call.bat"] = $PSScriptRoot
    $salt_dep_files["salt-minion.bat"] = $PSScriptRoot

    foreach ($file in $salt_dep_files.Keys) {
        Write-Log "Looking for $file in $($salt_dep_files[$file])" -Level debug
        if(!(Test-Path("$($salt_dep_files[$file])\$file"))) {
            Write-Log "Unable to find $file in $($salt_dep_files[$file])" -Level error
            $deps_present = $false
        }
    }

    Write-Log "All dependencies found" -Level debug
    $deps_present
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
    $exists
}


function Get-SaltFromWeb {
    # Download the salt tiamat zip file from the web and verify the hash
    #
    # Error:
    #     Set the status and exit with an error

    # Make sure the download directory exists
    if ( !( Test-Path -Path $base_salt_install_location) ) {
        Write-Log "Creating directory: $base_salt_install_location" -Level debug
        New-Item -Path $base_salt_install_location -ItemType Directory | Out-Null
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
    $expected_hash = Get-HashFromFile -HashFile $hash_file -FileName $salt_web_file_name

    Write-Log "Verifying hash" -Level info
    if ($file_hash -like $expected_hash) {
        Write-Log "Hash verified" -Level debug
    } else {
        Write-Log "Failed to verify hash:" -Level error
        Write-Log "  - $file_hash" -Level error
        Write-Log "  - $expected_hash" -Level error
        Set-FailedStatus
        exit 126
    }
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
    Expand-ZipFile -ZipFile "$base_salt_install_location\$salt_web_file_name" -Destination $base_salt_install_location

    # 2. Copy the scripts into Program Files
    Write-Log "Copying scripts" -Level info
    try {
        Write-Log "Copying $PSScriptRoot\salt-call.bat" -Level debug
        Copy-Item -Path "$PSScriptRoot\salt-call.bat" -Destination "$salt_dir"
    } catch {
        Write-Log "Failed copying $PSScriptRoot\salt-call.bat" -Level error
        Set-FailedStatus
        exit 126
    }
    try {
        Write-Log "Copying $PSScriptRoot\salt-minion.bat" -Level debug
        Copy-Item -Path "$PSScriptRoot\salt-minion.bat" -Destination "$salt_dir"
    } catch {
        Write-Log "Failed copying $PSScriptRoot\salt-minion.bat" -Level error
        Set-FailedStatus
        exit 126
    }

    # 3. Register the service
    Write-Log "Installing salt-minion service" -Level info
    & $ssm_bin install salt-minion "$salt_bin" "minion -c """"$salt_config_dir""""" *> $null
    & $ssm_bin set salt-minion Description Salt Minion from VMtools *> $null
    & $ssm_bin set salt-minion Start SERVICE_AUTO_START *> $null
    & $ssm_bin set salt-minion AppStopMethodConsole 24000 *> $null
    & $ssm_bin set salt-minion AppStopMethodWindow 2000 *> $null
    & $ssm_bin set salt-minion AppRestartDelay 60000 *> $null
    if (!(Get-Service salt-minion -ErrorAction SilentlyContinue).Status) {
        Write-Log "Failed to install salt-minion service" -Level error
        Set-FailedStatus
        exit 126
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
        $service = Get-WmiObject -Class Win32_Service -Filter "Name='salt-minion'"
        $service.delete() *> $null
        if ((Get-Service salt-minion -ErrorAction SilentlyContinue).Status) {
            Write-Log "Failed to uninstall salt-minion service" -Level error
            Set-FailedStatus
            exit 126
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
        $random_id = Get-RandomizedMinionId
        foreach ($line in Get-Content $salt_config_file) {
            if ($line -match "^id:.*$") {
                Write-Log "Commenting out the id" -Level debug
                $new_content.Add("#" + $line) | Out-Null
                $new_content.Add("id: $random_id") | Out-Null
            } else {
                $new_content.Add($line) | Out-Null
            }
        }
        $config_content = $new_content -join "`n"
        Write-Log "Writing new minion config"
        $Error.Clear()
        try {
            Set-Content -Path $salt_config_file -Value $config_content
        } catch {
            Write-Log "Failed to write new minion config : $Error" -Level error
            exit 126
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
if (($Action) -and ($Action.ToLower() -eq "test")) { exit 0 }

# Check for help switch
if ($help) {
    # Get the full script name
    $this_script = & {$myInvocation.ScriptName}
    Get-Help $this_script -Detailed
    exit 0
}

# Let's confirm dependencies
if (!(Confirm-Dependencies)) {
    Write-Host "Missing script dependencies"
    exit 126
}

# Let's make sure there's not already a standard salt installation on the system
if (Find-StandardSaltInstallation) {
    Write-Host "Found an existing salt installation on the system."
    exit 126
}

# Check for Action. If not specified on the command line, get it from guestVars
if ($Install) { $Action = "add" }
if ($Status) { $Action = "status" }
if ($Depend) { $Action = "depend" }
if ($Clear) { $Action = "reset" }
if ($Remove) { $Action = "remove" }
if (!($Action)) {
    $Action = Get-GuestVars -GuestVarsPath $guestvars_salt
    Write-Log "Action from GuestVars: $Action" -Level debug
}

# Validate the action
if ("add", "status", "depend", "reset", "remove" -notcontains $Action) {
    Write-Log "Invalid action: $Action" -Level error
    Write-Host "Invalid action: $Action" -ForgroundColor Red
    exit 126
}

if ($Action) {
    switch ($Action.ToLower()) {
        "depend" {
            # If we've gotten this far, dependencies have been confirmed
            Write-Host "Found all dependencies"
            exit 0
        }
        "add" {
            # If status is installed(0), installing(1), or removing(4), bail out
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                Write-Host "Unknown status code: $current_status" -Level error
                exit 126
            }
            switch ($current_status) {
                0 { Write-Host "Already installed"; exit 0 }
                1 { Write-Host "Installation in progress"; exit 0 }
                4 { Write-Host "Removal in progress"; exit 0}
            }
            Install
            Write-Host "Salt minion installed successfully"
            exit 0
        }
        "remove" {
            # If status is installing(1), notInstalled(2), or removing(4), bail out
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                Write-Host "Unknown status code: $current_status" -Level error
                exit 126
            }
            switch ($current_status) {
                1 { Write-Host "Installation in progress"; exit 0 }
                2 { Write-Host "Already uninstalled"; exit 0 }
                4 { Write-Host "Removal in progress"; exit 0}
            }
            Remove
            Write-Host "Salt minion removed successfully"
            exit 0
        }
        "reset" {
            # If not installed (0), bail out
            $current_status = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                Write-Host "Unknown status code: $current_status" -Level error
                exit 126
            }
            if ($current_status -ne 0) {
                Write-Host "Not installed. Reset will not continue"
                exit 0
            }
            Reset-SaltMinion
            Write-Host "Salt minion reset successfully"
            exit 0
        }
        "status" {
            $status_code = Get-Status
            if ($STATUS_CODES.keys -notcontains $current_status) {
                Write-Host "Unknown status code: $current_status" -Level error
                exit 126
            }
            Write-Host "Found status: $($STATUS_CODES[$status_code])"
            exit $status_code
        }
        default {
            $action_list = "install, remove, depend, clear, status"
            Write-Host "Invalid action: $Action - Must be one of [$action_list]"
            exit 126
        }
    }
} else {
    # No action specified
    Write-Log "No action specified" -Level error
    exit 126
}
