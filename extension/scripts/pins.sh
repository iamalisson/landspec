# Every third-party action and tool version landspec writes into a project, in one place.
# Actions are pinned to full commit SHAs: tags can be moved (aquasecurity/trivy-action, March 2026).
# Downloaded binaries are verified against their published SHA-256.
# shellcheck shell=bash disable=SC2034  # read by level.sh

PIN_CHECKOUT="actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1"
PIN_SETUP_NODE="actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0"
PIN_PNPM="pnpm/action-setup@73e46992e05b19abd31f2f3c20e0e7370d762115 # v6.1.1"
PIN_RUST_TOOLCHAIN="dtolnay/rust-toolchain@683b588c487a69d01f6c6ddf40f036ff682cc2c8 # master"
PIN_RUST_CACHE="Swatinem/rust-cache@d1527c8f67ef9af357290475d4af4b0fab8f12e0 # v2.9.3"
PIN_SETUP_UV="astral-sh/setup-uv@68559e99cc807c1eb7e9238fd43a15bba460eec2 # v10.3.3"
PIN_SETUP_PYTHON="actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0 # v7.1.0"
PIN_SETUP_GO="actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0"
PIN_ZIZMOR="zizmorcore/zizmor-action@45d7276c9ca790aabd705e31ca99c6185c3e76dd # v0.8.1"

GITLEAKS_VERSION="8.30.1"
GITLEAKS_SHA256="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb" # linux_x64 tarball
OSV_VERSION="2.7.0"
OSV_SHA256="160c6253e2922e9e0a6a9771c5c4c40a4b3c6090b34a3cdd5e80c96cc2e4218b"     # linux_amd64 binary
# Semgrep runs in CI from its official image, pinned by the OCI index digest of
# semgrep/semgrep:<SEMGREP_VERSION> (all architectures): bump both together. Read the digest with
# `docker buildx imagetools inspect semgrep/semgrep:<version>` (its "Digest:" line).
SEMGREP_VERSION="1.183.0"
SEMGREP_DIGEST="2e45517a85e13a9cca14a2a00df6bb48affd66b8ebfae1b0991cd57578362fb0"
# Checksum from the release's own trivy_<v>_checksums.txt: it catches a corrupted download, not a
# compromised release (trivy's distribution was attacked in March 2026). Bump only to releases
# that have been out for a few weeks.
TRIVY_VERSION="0.76.1"
TRIVY_SHA256="c7cbe3137fb8a48a17574bede3dd6beb16742d1e9772929940fc90082c39d9c0" # Linux-64bit tarball
# The AWS MCP proxy (.mcp.json, aws: on), run by uvx from PyPI. bin/check-tools.sh reads GitHub
# releases only, so bump this by hand, to a release that has been out a few weeks.
MCP_PROXY_VERSION="1.7.0"
