#!/usr/bin/env python3
import datetime
import json
import os
import pathlib

os.chdir(os.path.abspath(os.path.dirname(__file__)))

##    "ubuntu-2204",
LINUX_DISTROS = [
    "photon-5",
    "rockylinux-9",
]

WINDOWS = [
    "windows-2022",
]

SALT_VERSIONS = [
    "3006",
    "3006-8",
    "3007",
    "3007-1",
]

VERSION_DISPLAY_NAMES = {
    "3006": "v3006",
    "3006-8": "v3006.8",
    "3007": "v3007",
    "3007-1": "v3007.1",
}


# TODO: Revert the commit relating to this section, once the Git-based builds
#       have been fixed for the distros listed below
#
#       Apparent failure is:
#
#           /usr/lib/python3.11/site-packages/setuptools/command/install.py:34:
#           SetuptoolsDeprecationWarning: setup.py install is deprecated.
#           Use build and pip and other standards-based tools.
#

LATEST_PKG_BLACKLIST = []

##    "ubuntu-2204": "Ubuntu 22.04",
DISTRO_DISPLAY_NAMES = {
    "photon-5": "Photon OS 5",
    "rockylinux-9": "Rocky Linux 9",
    "windows-2022": "Windows 2022",
}

##    "ubuntu-2204": "systemd-ubuntu-22.04",
CONTAINER_SLUG_NAMES = {
    "photon-5": "systemd-photon-5",
    "rockylinux-9": "systemd-rockylinux-9",
    "windows-2022": "windows-2022",
}

TIMEOUT_DEFAULT = 20
TIMEOUT_OVERRIDES = {}
VERSION_ONLY_OVERRIDES = []

TEMPLATE = """
  {distro}:
    name: {display_name}{ifcheck}
    uses: {uses}
    needs:
      - lint
      - generate-actions-workflow
    with:
      distro-slug: {distro}
      display-name: {display_name}
      container-slug: {container_name}
      timeout: {timeout_minutes}{runs_on}
      instances: '{instances}'
"""


def generate_test_jobs():
    test_jobs = ""
    needs = ["lint", "generate-actions-workflow"]

    test_jobs += "\n"
    for distro in WINDOWS:
        test_jobs += "\n"
        runs_on = f"\n      runs-on: {distro}"
        ifcheck = "\n    if: github.event_name == 'push' || needs.collect-changed-files.outputs.run-tests == 'true'"
        uses = "./.github/workflows/test-windows.yml"
        instances = []
        timeout_minutes = (
            TIMEOUT_OVERRIDES[distro]
            if distro in TIMEOUT_OVERRIDES
            else TIMEOUT_DEFAULT
        )

        for salt_version in SALT_VERSIONS:
           instances.append(salt_version)

        if instances:
            needs.append(distro)
            test_jobs += TEMPLATE.format(
                distro=distro,
                runs_on=runs_on,
                uses=uses,
                ifcheck=ifcheck,
                instances=json.dumps(instances),
                display_name=DISTRO_DISPLAY_NAMES[distro],
                container_name=CONTAINER_SLUG_NAMES[distro],
                timeout_minutes=timeout_minutes,
            )

    test_jobs += "\n"
    for distro in LINUX_DISTROS:
        test_jobs += "\n"
        runs_on = ""
        ifcheck = "\n    if: github.event_name == 'push' || needs.collect-changed-files.outputs.run-tests == 'true'"
        uses = "./.github/workflows/test-linux.yml"
        instances = []
        timeout_minutes = (
            TIMEOUT_OVERRIDES[distro]
            if distro in TIMEOUT_OVERRIDES
            else TIMEOUT_DEFAULT
        )
        if distro in VERSION_ONLY_OVERRIDES:
            ifcheck = "\n    if: github.event_name == 'push'"

        for salt_version in SALT_VERSIONS:
           instances.append(salt_version)

        if instances:
            needs.append(distro)
            test_jobs += TEMPLATE.format(
                distro=distro,
                runs_on=runs_on,
                uses=uses,
                ifcheck=ifcheck,
                instances=json.dumps(instances),
                display_name=DISTRO_DISPLAY_NAMES[distro],
                container_name=CONTAINER_SLUG_NAMES[distro],
                timeout_minutes=timeout_minutes,
            )

    ci_src_workflow = pathlib.Path("ci.yml").resolve()
    ci_tail_src_workflow = pathlib.Path("ci-tail.yml").resolve()
    ci_dst_workflow = pathlib.Path("../ci.yml").resolve()
    ci_workflow_contents = ci_src_workflow.read_text() + test_jobs + "\n"
    ci_workflow_contents += ci_tail_src_workflow.read_text().format(
        needs="\n".join([f"      - {need}" for need in needs]).lstrip()
    )
    ci_dst_workflow.write_text(ci_workflow_contents)


if __name__ == "__main__":
    generate_test_jobs()
