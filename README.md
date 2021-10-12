# salt-vm-tools

VMTools salt integration script to install/remove/check status for a Salt minion
(`salt-minion`) in a VMware controlled Virtual Machine environment.

This script operates as a BASH script in Linux environments and a PowerShell
script in Windows environments.

The Salt minion is a [Tiamat](https://gitlab.com/saltstack/pop/tiamat) based
Python 3 Salt minion leveraging [PyInstaller's](https://www.pyinstaller.org/)
onedir option internally. The Salt minion is fully self-contained and requires
no additional dependencies.

The script can install, remove, and check the status of an installed salt-minion
either by direct command line option or via VMware's use of Guest Variables,
commonly referred to as guestVars.

## Configuration Options

You can pass configuration to this script in 3 ways; tools.conf, guestVars, and
the command line. Each option has an order of precedence. The lowest being
tools.conf, followed by guestVars, with the highest precedence being the command
line. Each option is discussed below.

### tools.conf (lowest preference)

The `tools.conf` file contains configuration for vmtools in an `.ini` format.
This tool looks for the `salt_minion` section and uses all configuration defined
under that section. This file is stored at:

| OS  | Location |
| --- | -------- |
| Linux | `/etc/vmware-tools/tools.conf` |
| Windows | `C:\ProgramData\VMware\VMware Tools\tools.conf` |

Below is a sample of the `salt_minion` section as it may be defined in
`tools.conf`:

    [salt_minion]
    master=192.168.0.118
    conf_file=/etc/salt/minion
    id=dev_minion

**Note:** Only minion config options are available in `tools.conf`. The desired
script action cannot be obtained from `tools.conf`.

### guestVars (medium preference)

VMware guestVars can contain the action this script performs as well as the
minion config options for this script. The config values here will override any
preferences defined in `tools.conf` with the same name.

The guestVars paths are as follows:

| Option | guestVars Location |
| ------ | ------------------ |
| Action | `vmware.components.salt_minion` |
| Config | `vmware.components.salt_minion.args` |

These values are set on the host OS using the `vmrun` binary. For example:

    # To set the Action
    vmrun writeVariable "<path/to/vmx/file>" guestVar vmware.components.salt_minion "install"

    # To set the Config Options
    vmrun writeVariable "<path/to/vmx/file>" guestVar vmware.components.salt_minion.args "master=192.168.0.120"

They can be read on the guest OS using the `vmtoolsd` binary. For example

    # To read the Config Options
    [root@fedora]# vmtoolsd --cmd "info-get guestinfo.vmware.components.salt_minion.args"
    master=192.168.0.120

### Command Line (highest preference)

Any input passed to the script on the command line will take precedence over the
action and config in guestVars and anything configured in `tools.conf`.

Linux example:

    [root@fedora]# svtminion.sh --install master=192.168.0.122

Windows example (note the single dash):

    # Powershell
    PS> svtminion.ps1 -install master=192.168.0.122

    # cmd
    C:\>powershell -file svtminion.ps1 -install master=192.168.0.122

**Note:** Higher preference configuration options will supersede lower
preference values.  For example: in the configuration preference examples
outlined above, the final value for master is `192.168.0.122`. Commane line
option for master overrides the `tools.conf` value of `192.168.0.118` and the
guestVars value of `192.168.0.120` because the command line arguments have the
highest precedence.

**Note:*** On Windows, if the minion ID is not passed, the guest host name will
be used. On Linux, however, there is no guarantee that a host name will be set.
Therefore, a minion ID is automatically generated for the salt-minion. In either
case the minion ID can be specified in any of the 3 config options. For example:

    id=myminion

**Note:** At all times preference is given to actions presented on the command
line over those available from guestVars.

For example, if the follwing is passed on the command line:

    [root@fedora]# svtminion.sh --install

And the following is defined in guestVars:

    [root@fedora]# vmtoolsd --cmd "info-get guestinfo.vmware.components.salt_minion"
    remove

Preference will be given to the command line argument and the salt-minion will
be installed.


## Linux Environment:

On Linux systems the install script is a bash script with the following
pre-requisites:

- systemctl
- curl
- sha512sum
- vmtoolsd
- grep
- awk
- sed
- cut

`svtminion.sh --help` shows the command line options

    Usage for the script svtminion.sh

        usage: ./svtminion.sh  [-c|--clear] [-d|--depend] [-h|--help] [-i|--install]
                     [-l|--loglevel] [-m|--saltversion] [-r|--remove]
                     [-s|--status] [-v|--version]

          -c, --clear     clear previous minion identifer and keys,
                             and set specified identifer if present
          -d, --depend    check dependencies required to run this script exist
          -h, --help      this message
          -i, --install   install and activate the salt-minion
                             parameters key=value can also be passed on the CLI
          -l, --loglevel  set log level for logging, silent error warning debug info
                             default loglevel is warning
          -m, --saltversion salt-minion version to installi, default[latest]
          -r, --remove    deactivate and remove the salt-minion
          -s, --status    return status for this script
          -v, --version   version of this script

          salt-minion vmtools integration script
              example: ./svtminion.sh --status


Windows Environment:
--------------------

On Windows systems the install scripts is a powershell script. You can get help
for this script by running `svtminion.ps1 -h` or `Get-Help svtminion.ps1`:

    NAME
        C:\src\salt-vm-tools\windows\svtminion.ps1

    SYNOPSIS
        VMtools script for managing the salt minion on a Windows guest

    SYNTAX
        C:\src\salt-vm-tools\windows\svtminion.ps1 [-Install] [-Version <String>] [[-ConfigOptions] <String[]>] [-LogLevel <String>] [-Help] [<CommonParameters>]
        C:\src\salt-vm-tools\windows\svtminion.ps1 [-Remove] [-LogLevel <String>] [-Help] [<CommonParameters>]
        C:\src\salt-vm-tools\windows\svtminion.ps1 [-Clear] [-Prefix <String>] [-LogLevel <String>] [-Help] [<CommonParameters>]
        C:\src\salt-vm-tools\windows\svtminion.ps1 [-Status] [-LogLevel <String>] [-Help] [<CommonParameters>]
        C:\src\salt-vm-tools\windows\svtminion.ps1 [-Depend] [-LogLevel <String>] [-Help] [<CommonParameters>]
        C:\src\salt-vm-tools\windows\svtminion.ps1 [-Help] [<CommonParameters>]

    DESCRIPTION
        This script manages the salt minion on a Windows guest. The minion is a tiamat
        build hosted on https://repo.saltproject.io/salt/vmware-tools-onedir. You can
        install the minion, remove it, check script dependencies, get the script status,
        and reset the minion.

        When this script is run without any parameters the options will be obtained from
        guestVars if present. If not they will be obtained from tools.conf. This
        includes the action (install, remove, etc) and the minion config options
        (master=192.168.10.10, etc.). The order of precedence is CLI options, then
        guestVars, and finally tools.conf.

    PARAMETERS
        -Install [<SwitchParameter>]
            Download, install, and start the salt-minion service.

        -Version <String>
            The version of salt minion to install. Default is 3003.3-1.

        -ConfigOptions <String[]>
            Any number of minion config options specified by the name of the config
            option as found in salt documentation. All options will be lower-cased and
            written to the minion config as passed. All values are in the key=value.
            format. eg: master=localhost

        -Remove [<SwitchParameter>]
            Stop and uninstall the salt-minion service.

        -Clear [<SwitchParameter>]
            Reset the salt-minion. Randomize the minion id and remove the minion keys.

        -Prefix <String>
            The prefix to apply to the randomized minion id. The randomized minion id
            will be the previx, an underscore, and 5 random digits. The default is
            "minion". Therfore, the default randomized name will be something like
            "minion_dkE9l".

        -Status [<SwitchParameter>]
            Get the status of the salt minion installation. This returns a numeric
            value that corresponds as follows:
            0 - installed
            1 - installing
            2 - notInstalled
            3 - installFailed
            4 - removing
            5 - removeFailed

        -Depend [<SwitchParameter>]
            Ensure the required dependencies are available. Exits with an error code
            if any dependencies are missing.

        -LogLevel <String>
            Sets the log level to display and log. Default is error. Silent suppresses
            all logging output

        -Help [<SwitchParameter>]
            Displays help for this script.

        <CommonParameters>
            This cmdlet supports the common parameters: Verbose, Debug,
            ErrorAction, ErrorVariable, WarningAction, WarningVariable,
            OutBuffer, PipelineVariable, and OutVariable. For more information, see
            about_CommonParameters (https:/go.microsoft.com/fwlink/?LinkID=113216).

        -------------------------- EXAMPLE 1 --------------------------
        PS>svtminion.ps1 -install
        PS>svtminion.ps1 -install -version 3004-1 master=192.168.10.10 id=vmware_minion

        -------------------------- EXAMPLE 2 --------------------------
        PS>svtminion.ps1 -clear -prefix new_minion

        -------------------------- EXAMPLE 3 --------------------------
        PS>svtminion.ps1 -status

        -------------------------- EXAMPLE 4 --------------------------
        PS>svtminion.ps1 -depend

        -------------------------- EXAMPLE 5 --------------------------
        PS>svtminion.ps1 -remove -loglevel debug

    REMARKS
        To see the examples, type: "get-help C:\src\salt-vm-tools\windows\svtminion.ps1 -examples".
        For more information, type: "get-help C:\src\salt-vm-tools\windows\svtminion.ps1 -detailed".
        For technical information, type: "get-help C:\src\salt-vm-tools\windows\svtminion.ps1 -full".
