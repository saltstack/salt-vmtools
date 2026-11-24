#!/usr/bin/env bash
#
# Fetch published GA Salt onedir packages into tests/testarea for Linux
# integration tests, and ensure a tiny RC stub exists for GA-vs-RC resolution
# checks. Does not commit anything; downloaded GA tarballs are gitignored.
#
# Usage (from repo root):
#   bash tests/linux/fetch_testarea_onedirs.sh
#
# CI runs this before tests/linux/test-linux.sh.

set -o errexit
set -o pipefail
set -o nounset

_test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_repo_root="$(cd "${_test_dir}/../.." && pwd)"
_testarea="${_repo_root}/tests/testarea"
_base_url="https://packages.broadcom.com/artifactory/saltproject-generic/onedir"

# Published GA fixture versions used by tests/linux/test-linux.sh --source paths
_GA_VERSIONS=(
    "3006.8"
    "3006.9"
    "3007.1"
)
_RC_VERSION="3008.0rc1"

_map_salt_onedir_arch() {
    case "$1" in
        x86_64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

_raw_arch="$(uname -m)"
if ! _arch="$(_map_salt_onedir_arch "${_raw_arch}")"; then
    echo "ERROR: unsupported architecture '${_raw_arch}'" 1>&2
    exit 1
fi

_download() {
    local ver="$1"
    local pkg="salt-${ver}-onedir-linux-${_arch}.tar.xz"
    local dest_dir="${_testarea}/${ver}"
    local dest="${dest_dir}/${pkg}"
    local url="${_base_url}/${ver}/${pkg}"

    mkdir -p "${dest_dir}"
    if [[ -f "${dest}" ]] && [[ -s "${dest}" ]]; then
        # Skip if a real (non-stub) package is already present
        local sz
        sz=$(wc -c < "${dest}" | tr -d ' ')
        if [[ "${sz}" -gt 1024 ]]; then
            echo "OK: already present ${pkg} (${sz} bytes)"
            return 0
        fi
    fi

    echo "Fetching ${url}"
    local attempt=1
    local max_attempts=3
    while [[ "${attempt}" -le "${max_attempts}" ]]; do
        if command -v curl >/dev/null 2>&1; then
            if curl -fsSL --retry 2 --retry-delay 2 -o "${dest}.partial" "${url}"; then
                break
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -q -O "${dest}.partial" "${url}"; then
                break
            fi
        else
            echo "ERROR: need curl or wget to fetch onedir fixtures" 1>&2
            exit 1
        fi
        echo "WARN: download attempt ${attempt}/${max_attempts} failed for ${pkg}" 1>&2
        rm -f "${dest}.partial"
        if [[ "${attempt}" -eq "${max_attempts}" ]]; then
            echo "ERROR: failed to download ${url}" 1>&2
            exit 1
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    mv "${dest}.partial" "${dest}"
    echo "OK: downloaded ${pkg}"
}

_ensure_rc_stub() {
    local ver="${_RC_VERSION}"
    local pkg="salt-${ver}-onedir-linux-${_arch}.tar.xz"
    local dest_dir="${_testarea}/${ver}"
    local dest="${dest_dir}/${pkg}"

    mkdir -p "${dest_dir}"
    # Tiny placeholder for directory listing / version resolution only
    printf '%s\n' "${pkg}" > "${dest}"
    echo "OK: RC stub ${pkg}"
}

for _ver in "${_GA_VERSIONS[@]}"; do
    _download "${_ver}"
done
_ensure_rc_stub

echo "fetch_testarea_onedirs.sh: done (arch=${_arch})"
exit 0
