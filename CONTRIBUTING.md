# Contributing Guidelines

## License Notice

The Salt VMTools project is open and encouraging to code contributions. Please be
advised that all code contributions will be licensed under the Apache 2.0 License.
We cannot accept contributions that already hold a License other than Apache 2.0
without explicit exception.

## Reporting Issues

The Salt VMTools issue tracker is used for feature requests and bug reports.

### Bugs

A bug is a *demonstrable problem* that is caused by the code in the repository.

Please read the following guidelines before you
[file an issue](https://github.com/saltstack/salt-vmtools/issues/new).

1. **Use the GitHub issue search** -- check if the issue has
   already been reported. If it has been, please comment on the existing issue.

1. **Check if the issue has been fixed** -- If you found a possible problem, or bug,
   please try to install using the vmtools script from the main branch. The
   issue you are having might have already been fixed and it's just not yet included
   in the release.

   ```
   curl -o svtminion.sh -L https://raw.githubusercontent.com/saltstack/salt-vmtools/main/linux/svtminon.sh
   curl -o svtminion.ps1 -L https://raw.githubusercontent.com/saltstack/salt-vmtools/main/linux/svtminon.ps1
   sudo bash svtminion.sh
   ```

1. **Isolate the demonstrable problem** -- make sure that the
   code in the project's repository is *definitely* responsible for the issue.

1. **Include a reproducible example** -- Provide the steps which
   led you to the problem.

Please try to be as detailed as possible in your report. What is your
environment? What steps will reproduce the issue? What operating system? What
would you expect to be the outcome? All these details will help people to
assess and fix any potential bugs.

**Including the version and system information will always help,** such as:

- Output of `salt --versions-report`
- Output of `svtminion.sh --version`
- System type
- Cloud/VM provider as appropriate

Valid bugs will worked on as quickly as resources can be reasonably allocated.

### Features

Feature additions and requests are welcomed. When requesting a feature it will
be placed under the `Feature` label.

If a new feature is desired, the fastest way to get it into Salt VMTools is
to contribute the code. Before starting on a new feature, an issue should be
filed for it. The one requesting the feature will be able to then discuss the
feature with the Salt VMTools maintainers and discover the best way to get
the feature included into the vmtools script and if the feature makes sense.

It is possible that the desired feature has already been completed.
Look for it in the [README](https://github.com/saltstack/salt-vmtools/blob/main/README.rst)
or exploring the wide list of options detailed at the top of the script. These
options are also available by running the `-h` help option for the script. It
is also common that the problem which would be solved by the new feature can be
easily solved another way, which is a great reason to ask first.

## Fixing Issues

Fixes for issues are very welcome!

Once you've fixed the issue you have in hand, create a
[pull request](https://help.github.com/articles/creating-a-pull-request/).

Salt VMTools maintainers will review your fix. If everything is OK and all
tests pass, you fix will be merged into Salt VMTools's code.

### Branches

There is only one main branch in the Salt VMTools repository:

- main

All fixes and features should be submitted to the `main` branch. The `releases`
directory only contains released versions of the vmtools script.

## Pull Requests

The Salt VMTools repo has several pull request checks that must pass before
a bug fix or feature implementation can be merged in.

### PR Tests

There are several build jobs that run on each Pull Request. Most of these are
CI jobs that set up different steps, such as setting up the job, cloning the
repo from the PR, etc.

#### Lint Check

The pull request test that matters the most, and the contributor is directly
responsible for fixing, is the Lint check. This check *must* be passing before
the contribution can be merged into the codebase.

If the lint check has failed on your pull request, you can view the errors by
clicking `Details` in the test run output. Then, click the `Violations` link on
the left side. There you will see a list of files that have errors. By clicking
on the file, you will see `!` icons on the affected line. Hovering over the `!`
icons will explain what the issue is.

To run the lint tests locally before submitting a pull request, use the
`tests/runtests.py` file. The `-L` option runs the lint check:

```
python tests/runtests.py -L
```

### GPG Verification

SaltStack has enabled [GPG Probot](https://probot.github.io/apps/gpg/) to
enforce GPG signatures for all commits included in a Pull Request.

In order for the GPG verification status check to pass, *every* contributor in
the pull request must:

- Set up a GPG key on local machine
- Sign all commits in the pull request with key
- Link key with GitHub account

This applies to all commits in the pull request.

GitHub hosts a number of
[help articles](https://help.github.com/articles/signing-commits-with-gpg/) for
creating a GPG key, using the GPG key with `git` locally, and linking the GPG
key to your GitHub account. Once these steps are completed, the commit signing
verification will look like the example in GitHub's
[GPG Signature Verification feature announcement](https://github.com/blog/2144-gpg-signature-verification).

## Release Information

### Release Cadence

There is no defined release schedule for the vmtools scripts at this time.
Typically, SaltStack's release team determines when it would be good to release
a new version.

Timing the release usually involves an analysis of the following:

- Updates for major feature releases in [Salt](https://github.com/saltstack/salt)
- Types of fixes submitted to `main` since the last release
- Length of time since the last vmtools release

### Release Process

The release process consists of the following steps:

1. Merge in any outstanding PRs that are ready.
1. Add new contributors to the [AUTHORS](https://github.com/saltstack/salt-vmtools/blob/main/AUTHORS.rst) file.
1. Update the [ChangeLog](https://github.com/saltstack/salt-vmtools/blob/main/ChangeLog).
1. Update the version number in the vmtools scripts. The version number is number-based major version with minor version, `<1.X>`.
   For example, version `1.7` is major version `1` and minior version `7`.
1. Place the new release into [Salt](https://github.com/saltstack/salt-tools/releases).

## Adding Support for Other Operating Systems

Only Linux and Windows operating systems are currently supported.


The vmtools scripts must be Bash for Linux or Powershell for Windows.
By design, the targeting for each operating system and version is very specific. Assumptions of
supported versions or variants should not be made, to avoid failed or broken installations.
