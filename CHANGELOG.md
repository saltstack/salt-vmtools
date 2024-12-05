# v2024.12.05

## What's Changed
* Corrected paths to scripts and moved location tag occurs by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/15
* Added git user etc before tagging by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/16
* Correct type vmtools-salt.sh for svtminion.sh, and similar for ps1 by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/17
* Further corrections to cutting a release by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/18
* Fixing final workflow for updating README.md with sha256sums by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/19


**Full Changelog**: https://github.com/saltstack/salt-vmtools/compare/v2024.12.04...v2024.12.05

# v2024.12.04

**Full Changelog**: https://github.com/saltstack/salt-vmtools/compare/v2024.12.04...v2024.12.04

# v2024.12.04

**Full Changelog**: https://github.com/saltstack/salt-vmtools/compare/v2024.12.04...v2024.12.04

# v2024.12.04

**Full Changelog**: https://github.com/saltstack/salt-vmtools/compare/v2024.12.04...v2024.12.04

# v2024.12.04

**Full Changelog**: https://github.com/saltstack/salt-vmtools/compare/v2024.12.04...v2024.12.04

# v2024.12.04

## What's Changed
* Update pre-commit t  generate actions workflow by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/5
* Update Linux tests to work on GitHub by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/6
* Added linux pakcages for x86_64 for 3006.8, 3006.9 and 3007.1 by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/8
* Remove testing on Photon 5 and final cleanup by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/9
* Migrate tests from gitlab by @twangboy in https://github.com/saltstack/salt-vmtools/pull/7
* Updating GitHub actions to cut a release by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/10
* Updating cut-release for errors found during cut-release by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/11
* Migrated CHANGELOG to CHANGLOG.md by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/12
* Changed branch develop to main by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/13
* Changes pushes to repo to not use ssh by @dmurphy18 in https://github.com/saltstack/salt-vmtools/pull/14

## New Contributors
* @twangboy made their first contribution in https://github.com/saltstack/salt-vmtools/pull/7

**Full Changelog**: https://github.com/saltstack/salt-vmtools/compare/1.6...v2024.12.04

# Release 1.7

## What's Changed

- Added support to stop, start, reconfig and upgrade and installed salt-minion
- Updated tests to exercise stop, start, reconfig and upgrade functionality

# Release 1.6

## What's Changed

- Added support for salt user and group on Linux for Salt 3006 and later
- Create expected directories on Windows and fix mis-spelling on Windows

# Release 1.5

## What's Changed

- Support for Salt 3006 and later on Linux and Windows
- Return 106 'external install', if find existing non-onedir installation on Linux and Windows
- Updated the copyright and license in generated Linux systemd salt-minion.service file

# Release 1.4

## What's Changed

- Detect arch using pointer size instead of WMIC
- Fix path to log location on Windows
- Update copyright, copying permission and pre-commit
- Fix Windows Script not Starting

# Release 1.3

## What's Changed

- Added ability to install from private repository, locally or via the net

# Release 1.2

## What's Changed

- Windows   Detect arch using pointer size instead of WMIC
