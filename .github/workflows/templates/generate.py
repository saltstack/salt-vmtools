#!/usr/bin/env python3
import datetime
import json
import os
import pathlib
import sys

os.chdir(os.path.abspath(os.path.dirname(__file__)))

##    "ubuntu-2204",
##    "photon-5",
LINUX_DISTROS = [
    "rockylinux-9",
]

WINDOWS = [
    "windows-2022",
]

SALT_VERSIONS = [
    "3006",
    "3006-15",
    "3007",
    "3007-7",
    "3008",
    "3008-1",
]

VERSION_DISPLAY_NAMES = {
    "3006": "v3006",
    "3006-15": "v3006.15",
    "3007": "v3007",
    "3007-7": "v3007.7",
    "3008": "v3008",
    "3008-1": "v3008.1",
}


def get_version_pairs():
    # Derive (major, exact) pairs from SALT_VERSIONS' dash convention, e.g.
    # "3006-15" -> ("3006", "3006.15"). This is the single source of truth
    # test suites read to know which exact version to test per major.
    pairs = []
    for entry in SALT_VERSIONS:
        if "-" in entry:
            major, minor = entry.split("-", 1)
            pairs.append((major, f"{major}.{minor}"))
    return pairs


def get_major_order():
    # Ordered list of distinct majors, in the order first seen in
    # SALT_VERSIONS.
    seen = []
    for entry in SALT_VERSIONS:
        major = entry.split("-", 1)[0]
        if major not in seen:
            seen.append(major)
    return seen


def get_upgrade_steps():
    # One (from_exact, to_major, to_exact) tuple per adjacent major pair,
    # e.g. ("3006.15", "3007", "3007.7"). Used to derive one CI job per
    # upgrade step, and for test suites to look up their assigned step.
    exact_by_major = dict(get_version_pairs())
    majors = get_major_order()
    steps = []
    for prev_major, next_major in zip(majors, majors[1:]):
        if prev_major in exact_by_major and next_major in exact_by_major:
            steps.append(
                (exact_by_major[prev_major], next_major, exact_by_major[next_major])
            )
    return steps


def print_version_pairs():
    for major, exact in get_version_pairs():
        print(f"{major} {exact}")


def print_upgrade_steps():
    for from_exact, to_major, to_exact in get_upgrade_steps():
        print(f"{from_exact} {to_major} {to_exact}")


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
##    "photon-5": "Photon OS 5",
DISTRO_DISPLAY_NAMES = {
    "rockylinux-9": "Rocky Linux 9",
    "windows-2022": "Windows 2022",
}

##    "ubuntu-2204": "systemd-ubuntu-22.04",
##    "photon-5": "systemd-photon-5",
CONTAINER_SLUG_NAMES = {
    "rockylinux-9": "systemd-rockylinux-9",
    "windows-2022": "windows-2022",
}

TIMEOUT_DEFAULT = 20
TIMEOUT_OVERRIDES = {}
VERSION_ONLY_OVERRIDES = []

# Test jobs run on every push, on manual (workflow_dispatch) and scheduled
# (weekly cron, see templates/ci.yml) runs, and on PRs where the
# collect-changed-files job found relevant files changed.
RUN_TESTS_IF = (
    "\n    if: github.event_name == 'push' || "
    "github.event_name == 'workflow_dispatch' || "
    "github.event_name == 'schedule' || "
    "needs.collect-changed-files.outputs.run-tests == 'true'"
)
RUN_ALWAYS_IF = (
    "\n    if: github.event_name == 'push' || "
    "github.event_name == 'workflow_dispatch' || "
    "github.event_name == 'schedule'"
)

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
        ifcheck = RUN_TESTS_IF
        uses = "./.github/workflows/test-windows.yml"
        instances = []
        timeout_minutes = (
            TIMEOUT_OVERRIDES[distro]
            if distro in TIMEOUT_OVERRIDES
            else TIMEOUT_DEFAULT
        )

        for salt_version in SALT_VERSIONS:
           instances.append(salt_version)
        for _, to_major, _ in get_upgrade_steps():
           instances.append(f"upgrade-{to_major}")

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
        ifcheck = RUN_TESTS_IF
        uses = "./.github/workflows/test-linux.yml"
        instances = []
        timeout_minutes = (
            TIMEOUT_OVERRIDES[distro]
            if distro in TIMEOUT_OVERRIDES
            else TIMEOUT_DEFAULT
        )
        if distro in VERSION_ONLY_OVERRIDES:
            ifcheck = RUN_ALWAYS_IF

        for salt_version in SALT_VERSIONS:
           instances.append(salt_version)
        for _, to_major, _ in get_upgrade_steps():
           instances.append(f"upgrade-{to_major}")

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
    if "--print-versions" in sys.argv:
        print_version_pairs()
    elif "--print-upgrade-steps" in sys.argv:
        print_upgrade_steps()
    else:
        generate_test_jobs()
