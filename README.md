# salt-vm-tools

The VMTools salt integration script installs, removes, or checks the status of
a Salt minion (`salt-minion`) in a VMware controlled Virtual Machine environment.

This script operates as a BASH script in Linux environments and a PowerShell
script in Windows environments.

The Salt minion is a Onedir architecture based Python 3 Salt minion leveraging
relenv (https://github.com/saltstack/relenv) onedir option internally.
The Salt minion is fully self-contained and requires no additional dependencies.

The script can install, remove, and check the status of an installed Salt minion
either using a direct command line option or via VMware's use of Guest Variables,
commonly referred to as guestVars.

In every two-step installation example, you would be well-served to **verify against the SHA256
sum** of the downloaded `svtminion.sh` file.

## _sha256sums

The SHA256 sum of the `svtminion.sh` file, per release, is:


If you're looking for a *one-liner* to install Salt Minion, please read below.

There are also .sha256 files for verifying against in the repo for the main branch.  You can also
get the correct sha256 sum for the tagged release from
https://github.com/saltstack/salt-vmtools/releases/latest/download/svtminion.sh.sha256 and
https://github.com/saltstack/salt-vmtools/releases/latest/download/svtminion.ps1.sha256


## Configuration options

You can pass configuration to this script in 3 ways: guestVars, tools.conf and
the command line. Each option has an order of precedence. The lowest being
guestVars, followed by tools.conf, with the highest precedence being the command
line. Each option is explained in the following sections.

### guestVars (lowest preference)

VMware guestVars can contain the action this script performs as well as the
minion config options to be set by this script. The config values here will
override any config options defined in `tools.conf` with the same name.

The guestVars paths are as follows:

| Option | guestVars Location                   |
| ------ |--------------------------------------|
| Action | `vmware.components.salt_minion`      |
| Config | `vmware.components.salt_minion.args` |

If set, the `Action` option will return a single word that is the action this
script will perform. If set, the `Config` option will return a space delimited
list of minion config options. For example: `master=198.51.100.1 id=my_minion
multiprocessing=false`

These values are set on the host OS using the `vmrun` binary. For example:

    # To set the Action to install the salt-minion
    vmrun writeVariable "<path/to/vmx/file>" guestVar vmware.components.salt_minion "present"

    # To set the Action to remove the salt-minion
    vmrun writeVariable "<path/to/vmx/file>" guestVar vmware.components.salt_minion "absent"

    # To set the Config Options
    vmrun writeVariable "<path/to/vmx/file>" guestVar vmware.components.salt_minion.args "master=203.0.113.1"

They can be read on the guest OS using the `vmtoolsd` binary. For example:

    # To read the Config Options
    [root@fedora]# vmtoolsd --cmd "info-get guestinfo.vmware.components.salt_minion.args"
    master=203.0.113.1

### tools.conf (medium preference)

The `tools.conf` file contains the configurations for vmtools in an `.ini` format.
This tool looks for the `salt_minion` section and uses the configurations defined
under that section. This file is stored at:

| OS      | Location                                        |
|---------|-------------------------------------------------|
| Linux   | `/etc/vmware-tools/tools.conf`                  |
| Windows | `C:\ProgramData\VMware\VMware Tools\tools.conf` |

Below is an example of the `salt_minion` section as it may be defined in
`tools.conf`:

    [salt_minion]
    master=203.0.113.1
    conf_file=/etc/salt/minion
    id=dev_minion

**Note:** Only minion config options are available in `tools.conf`. The desired
script action cannot be obtained from `tools.conf`.

### Command Line (highest preference)

Any input passed to the script on the command line will take precedence over:

- 2024.12.04: ``e7f4d7b242bd495c63e7b3240631411fbe65ac966ff2c1ef93399ceda9b5719f``
- The action and config options set in guestVars
- Anything configured in `tools.conf` with the same name.

Linux example:

    [root@fedora]# svtminion.sh --install master=198.51.100.1

Windows example (note the single dash):

    # Powershell
    PS> svtminion.ps1 -install master=198.51.100.1

    # cmd
    C:\>powershell -file svtminion.ps1 -install master=198.51.100.1

**Note:** Higher preference configuration options will supersede lower
preference values.  For example, in the configuration preference examples
outlined above, the final value for master is `198.51.100.1`. Command line
option for master overrides the `tools.conf` value of `203.0.113.1` and the
guestVars value of `203.0.113.1` because the command line arguments have the
highest precedence.

**Note:*** On Windows, if the minion ID is not passed, the guest host name will
be used. However, on Linux there is no guarantee that a host name will be set.
Therefore, a minion ID is automatically generated for the Salt minion. In either
case, the minion ID can be specified in any of the 3 config options. For example:

    id=myminion

**Note:** At all times preference is given to actions presented on the command
line over those available from guestVars.

For example, if the following is passed on the command line:

    [root@fedora]# svtminion.sh --install

And the following is defined in guestVars:

    [root@fedora]# vmtoolsd --cmd "info-get guestinfo.vmware.components.salt_minion"
    remove

Preference is given to the command line argument and the Salt minion package will
be installed.


## Logging

This script creates a log file at the following location:

| OS      | Location          |
|---------|-------------------|
| Linux   | `/var/log`        |
| Windows | `C:\Windows\temp` |

The content of the log file depends on the `LogLevel` passed on the command
line. The default value is `warning`. Valid options are:

| Log Level | Description                                              |
| --------- |----------------------------------------------------------|
| `silent`  | Suppresses displayed output but logs errors and warnings |
| `error`   | Displays and logs only errors                            |
| `warning` | Displays and logs errors and warnings                    |
| `info`    | Displays and logs errors, warnings, and info messages    |
| `debug`   | Displays and logs all messages                           |

The names of Log files are based on the action that the script is performing. The
`action` can be defined on the command line or by setting a value in guestVars.
Any logging that is unrelated to an action uses the keyword `default`. Valid
actions are as follows:

- `clear`
- `depend`
- `install`
- `reconfig`
- `remove`
- `start`
- `status`
- `stop`

For example, running the script without a defined action results in a log
file with the following name:

    # Linux
    bash>svtminion.sh --version --loglevel debug

    /etc/log/vmware-svtminion.sh-default-YYYYMMDDhhmmss.log

    # Windows
    PS>.\svtminion.ps1 -LogLevel debug

    or

    cmd>powershell -file .\svtminion.ps1 -LogLevel debug

    C:\Windows\temp\vmware-svtminion-default-YYYYMMDDhhmmss.log

Only the 10 most recent log files for each action are maintained. Excess log
files are removed. Log files are not removed when the salt-minion service is uninstalled.


## Linux Environment:

On Linux systems, the install script is a bash script with the following
pre-requisites:

- systemctl
- curl
- sha512sum
- vmtoolsd
- grep
- awk
- sed
- cut
- wget
- find

`svtminion.sh --help` shows the command line options

    Usage for the script svtminion.sh

        usage: ./svtminion.sh  [-c|--clear] [-d|--depend] [-h|--help] [-i|--install]
                     [-j|--source] [-l|--loglevel] [-m|--minionversion]
                     [-n|--reconfig] [-q|--stop] [-p|--start]
                     [-r|--remove] [-s|--status] [-u|--upgrade]
                     [-v|--version]

          -c, --clear     clear previous minion identifer and keys,
                             and set specified identifer if present
          -d, --depend    check dependencies required to run this script exist
          -h, --help      this message
          -i, --install   install and activate the salt-minion
                             parameters key=value can also be passed on the CLI
          -j, --source   specify location to install Salt Minion from
                             default is repo.saltproject.io location
                         for example: url location
                             http://my_web_server.com/my_salt_onedir
                             https://my_web_server.com/my_salt_onedir
                             file://my_path/my_salt_onedir
                            //my_path/my_salt_onedir
                         if specific version of Salt Minion specified, -m
                         then its appended to source, default[latest]
          -l, --loglevel  set log level for logging, silent error warning debug info
                             default loglevel is warning
          -m, --minionversion salt-minion version to install, default[latest]
          -n, --reconfig    salt-minion restarts after re-reading updated configuration
          -q, --stop      stop salt-minion
          -p, --start     start salt-minion (effectively restart salt-minion)
          -r, --remove    deactivate and remove the salt-minion
          -s, --status    return status for this script
          -u, --upgrade   upgrade when installing, used with --install
          -v, --version   version of this script

          salt-minion vmtools integration script
              example: ./svtminion.sh --status

Note: on Linux, the script does not support use of hostname as in file://<hostname>/path1/path2


Windows Environment:
--------------------

On Windows systems, the install script is a powershell script. The only
prerequisite for Windows is the `vmtoolsd.exe` binary, which is used to query
guestVars data. You can get help for this script by running `svtminion.ps1 -h`
or `Get-Help svtminion.ps1`:

    NAME
        .\svtminion.ps1

    SYNOPSIS
        VMware Tools script for managing the Salt minion on a Windows guest.

    SYNTAX
        .\svtminion.ps1 [-Install] [-Upgrade] [-MinionVersion <String>] [-Source <String>]
        [[-ConfigOptions] <String[]>] [-LogLevel <String>] [-Stop] [-Start] [-Help] [-Version] [<CommonParameters>]

        .\svtminion.ps1 [-Reconfig] [[-ConfigOptions] <String[]>] [-LogLevel <String>]
        [-Stop] [-Start] [-Help] [-Version] [<CommonParameters>]

        .\svtminion.ps1 [-Remove] [-LogLevel <String>] [-Stop] [-Start] [-Help] [-Version]
        [<CommonParameters>]

        .\svtminion.ps1 [-Clear] [-LogLevel <String>] [-Stop] [-Start] [-Help] [-Version]
        [<CommonParameters>]

        .\svtminion.ps1 [-Status] [-LogLevel <String>] [-Stop] [-Start] [-Help] [-Version]
        [<CommonParameters>]

        .\svtminion.ps1 [-Depend] [-LogLevel <String>] [-Stop] [-Start] [-Help] [-Version]
        [<CommonParameters>]

    DESCRIPTION
        This script provides comprehensive management of the Salt minion on a Windows
        guest. The minion is a OneDir build available at:

        https://packages.broadcom.com/artifactory/saltproject-generic/onedir

        With this script, you can install, remove, check dependencies, retrieve
        installation status, and reset the Salt minion configuration.

        When run without parameters, the script checks for an action in `guestVars`. If
        no action is found, it exits with a `scriptFailed` (126) code.

        If an action is passed via the CLI or found in `guestVars`, the script gathers
        minion configuration options (e.g., `master=198.51.100.1`) from `guestVars`.
        Additional configuration options are obtained from `tools.conf`, which overrides
        any conflicting options from `guestVars`. CLI options take the highest
        precedence, followed by `tools.conf`, and finally `guestVars`.

        The script returns the following exit codes to indicate its status:
        - 0 - `scriptSuccess`
        - 126 - `scriptFailed`
        - 130 - `scriptTerminated`

        If the `-Status` option is passed, the exit code signals the Salt minionâ€™s
        installation status as follows:
        - 100 - Installed (and running)
        - 101 - Installing
        - 102 - Not installed
        - 103 - Installation failed
        - 104 - Removing
        - 105 - Removal failed
        - 106 - External installation detected
        - 107 - Installed but stopped

        NOTE: This script must be executed with Administrator privileges.

    PARAMETERS
        -Install [<SwitchParameter>]
            The Install action downloads, installs, and starts the salt-minion
            service.

            It exits with the `scriptFailed` exit code (126) under any of the
            following conditions:
            - Existing Standard Salt Installation detected
            - Unknown status found
            - Installation in progress
            - Removal in progress
            - Installation failed
            - Missing script dependencies

            It exits with the `scriptSuccess` exit code (0) under the following
            conditions:
            - Installed successfully
            - Already installed

        -Upgrade [<SwitchParameter>]
            The Upgrade parameter upgrades an existing Salt installation in place,
            leaving the minion configuration unchanged. guestVars and CLI values
            are ignored during the upgrade. Use this option to switch between
            different Salt versions.

            Pass the Upgrade parameter with the Install action to upgrade to the
            specified version. If Upgrade is not passed and Salt is already installed,
            the script will exit with a `scriptSuccess` code (0) and a message
            indicating that the minion is already installed.

        -MinionVersion <String>
            The MinionVersion parameter specifies the version of the Salt minion to
            install. Use "latest" to install the most recent version available
            (default is "latest"). Alternatively, you can specify a major version
            number to install the latest release within that version series. For
            example, to install the latest release in the 3006 series, pass "3006".

        -Source <String>
            The Source parameter specifies the URL or path to a repository containing
            directories named after different Salt versions. Each directory should
            include a zip file corresponding to the version indicated by the directory
            name.

            The directory structure should follow a layout similar to the default
            repository:

            https://packages.broadcom.com/artifactory/saltproject-generic/onedir

            The Source parameter supports common protocols such as HTTP, HTTPS, FTP,
            UNC paths, and local file paths.

        -Reconfig [<SwitchParameter>]
            The Reconfig action updates the Salt minion configuration using settings
            provided via the command-line, `guestVars`, or `tools.conf`. After
            updating, the minion will be restarted to apply the new configuration.

            The following exit codes may occur:
            - 102 - Salt minion not installed
            - 106 - External installation of the Salt minion detected

        -ConfigOptions <String[]>
            This parameter accepts any number of minion configuration options,
            specified as key/value pairs in the format `key=value`, as documented in
            the Salt documentation. For example: master=localhost.

            All keys will be automatically converted to lowercase and written to the
            minion configuration.

        -Remove [<SwitchParameter>]
            The Remove action stops and uninstalls the salt-minion service. It exits
            with the `scriptFailed` exit code (126) under the following conditions:
            - Unknown status found
            - Installation in progress
            - Removal in progress
            - Installation failed
            - Missing script dependencies

            It exits with the `scriptSuccess` exit code (0) under the following
            conditions:
            - Successfully removed
            - Already removed

        -Clear [<SwitchParameter>]
            The Clear action resets the salt-minion by randomizing its minion ID and
            removing the minion keys. The new minion ID will be the old minion ID
            followed by an underscore and five random digits.

            Exits with the `scriptFailed` exit code (126) under the following
            conditions:
            - Unknown status found
            - Missing script dependencies

            Exits with the `scriptSuccess` exit code (0) under the following
            conditions:
            - Successfully cleared
            - Minion was not installed

        -Status [<SwitchParameter>]
            The Status action retrieves the current status of the Salt minion
            installation. The exit code will correspond to one of the following status
            codes:

            100 - Installed (and running)
            101 - Installing
            102 - Not installed
            103 - Installation failed
            104 - Removing
            105 - Removal failed
            106 - External installation detected
            107 - Installed but stopped

            Exits with the `scriptFailed` exit code (126) under the following
            conditions:
            - Unknown status found
            - Missing script dependencies

        -Depend [<SwitchParameter>]
            The Depend action checks that all required dependencies are available.

            It exits with the `scriptFailed` exit code (126) if any dependencies are
            missing.

            It exits with the `scriptSuccess` exit code (0) if all dependencies are
            present.

        -LogLevel <String>
            Sets the log level for display and logging. The default is "warning". The
            "silent" level suppresses all logging output. Available options are:

            - silent
            - error
            - warning
            - info
            - debug

            Logs are stored in `C:\Windows\temp` and named according to the action the
            script is performing, along with a timestamp. For example:
            `vmware-svtminion-<action>-<timestamp>.log`

        -Stop [<SwitchParameter>]
            Stops the salt-minion service.

            The following exit codes may occur:
            102 - Salt minion not installed
            106 - External installation of the Salt minion detected

        -Start [<SwitchParameter>]
            Starts or restarts the salt-minion service.

            The following exit codes may occur:
            102 - Salt minion not installed
            106 - External install of the Salt minion found

        -Help [<SwitchParameter>]
            Displays help information for this script.

        -Version [<SwitchParameter>]
            Displays the current version of this script.

        <CommonParameters>
            This cmdlet supports the common parameters: Verbose, Debug,
            ErrorAction, ErrorVariable, WarningAction, WarningVariable,
            OutBuffer, PipelineVariable, and OutVariable. For more information, see
            about_CommonParameters (https:/go.microsoft.com/fwlink/?LinkID=113216).

        -------------------------- EXAMPLE 1 --------------------------
        PS>svtminion.ps1 -Install

        -------------------------- EXAMPLE 2 --------------------------
        PS>svtminion.ps1 -Install -MinionVersion 3006.2 master=192.168.10.10 id=dev_box

        -------------------------- EXAMPLE 3 --------------------------
        PS>svtminion.ps1 -Install -Source https://my.domain.com/vmtools/salt

        -------------------------- EXAMPLE 4 --------------------------
        PS>svtminion.ps1 -Install -MinionVersion 3006.8 -Upgrade

        -------------------------- EXAMPLE 5 --------------------------
        PS>svtminion.ps1 -Clear

        -------------------------- EXAMPLE 6 --------------------------
        PS>svtminion.ps1 -Status

        -------------------------- EXAMPLE 7 --------------------------
        PS>svtminion.ps1 -Depend

        -------------------------- EXAMPLE 8 --------------------------
        PS>svtminion.ps1 -Remove -LogLevel debug

    REMARKS
        To see the examples, type: "get-help .\svtminion.ps1 -examples".
        For more information, type: "get-help .\svtminion.ps1 -detailed".
        For technical information, type: "get-help .\svtminion.ps1 -full".
