# GoReleaser Example: Multi-Platform Docker Images with Attestations

This repository demonstrates how to use [GoReleaser](https://goreleaser.com) to build and release multi-platform Docker images with full SLSA provenance and SBOM (Software Bill of Materials) attestations for a simple Go application. The example application is a lightweight web server that listens on port 8080 and responds with "Hello World!" along with the current timestamp.

The primary goal is to provide a clear, reproducible setup for creating multi-architecture Docker images (supporting `amd64`, `386`, `arm/v6`, `arm64`, and `riscv64`) with attestations, leveraging GoReleaser and GitHub Actions. This addresses the limited documentation available for GoReleaser users building multi-platform Docker images with security-focused attestations.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Multi-Platform Builds with GoReleaser](#multi-platform-builds-with-goreleaser)
- [GitHub Actions Workflows](#github-actions-workflows)
- [Building Locally](#building-locally)
- [Releasing](#releasing)
- [Dockerfile](#dockerfile)
- [Attestations](#attestations)
- [Using Syft with Generated Archives and SBOMs](#using-syft-with-generated-archives-and-sboms)
  - [Prerequisites for Syft and yq](#prerequisites-for-syft-and-yq)
  - [Verify the SBOM](#verify-the-sbom)
  - [Analyze the SBOM](#analyze-the-sbom)
  - [Cleanup](#cleanup)
- [Running the Image](#running-the-image)
- [Multi-Platform Considerations](#multi-platform-considerations)
- [Troubleshooting](#troubleshooting)
- [Extending to Other Registries](#extending-to-other-registries)
- [Additional Resources](#additional-resources)

## Features

- **Multi-Platform Builds**: Supports binaries and Docker images for multiple architectures (`amd64`, `386`, `arm/v6`, `arm64`, `riscv64`) across Linux, Windows, and macOS.
- **Docker Images**: Builds platform-specific images and combines them into multi-arch manifests using Docker Buildx.
- **Attestations**: Generates SLSA provenance and SBOM attestations for each architecture-specific image, ensuring supply chain security.
- **GitHub Actions Workflows**: Automates building, releasing, and creating multi-arch manifests with attestations preserved.
- **Verification**: Supports validation of images, attestations, and SBOMs using `docker buildx imagetools` and Syft.

## Prerequisites

- **Go**: Version 1.25 or later.
- **GoReleaser**: Install via `go install github.com/goreleaser/goreleaser@latest`.
- **Docker**: Installed with Buildx and QEMU for multi-platform support.
- **GitHub Repository**: With Actions enabled and a GitHub token with `write:packages` and `write:attestations` permissions for GHCR (GitHub Container Registry).
- **Syft**: For SBOM generation and validation (`curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin`).
- **Grype**: For scanning SBOMs for vulnerabilities (`curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin`).
- **yq** (optional): Go-based JSON/YAML processor for inspecting SBOMs (`go install github.com/mikefarah/yq/v4@latest`).

## Project Structure

- **`main.go`**: Simple Go web server listening on port 8080.
- **`Dockerfile`**: Multi-stage Dockerfile using Alpine as the base image, copying the GoReleaser-built binary and adding Open Container Initiative (OCI) labels.
- **`.goreleaser.yaml`**: Configures multi-platform builds, archives, Docker images, SBOMs, and attestations.
- **`build.yaml`**: GitHub Actions workflow for building binaries, images, SBOMs, and attestations.
- **`create-manifests.yaml`**: GitHub Actions workflow for creating and pushing multi-arch manifests.
- **`release.yaml`**: Orchestrates the build and manifest creation workflows on tag pushes or manual dispatch.

## Multi-Platform Builds with GoReleaser

The `.goreleaser.yaml` configuration is the core of the multi-platform build process:

- **Builds**:
  - Targets multiple OS (`linux`, `windows`, `darwin`) and architectures (`amd64`, `386`, `arm`, `arm64`, `riscv64`).
  - Uses `CGO_ENABLED=0` for static binaries.
  - Sets `ldflags` to embed version, commit, and date metadata.
  - Customizes archive names to match `uname` conventions (e.g., `goreleaser-example_linux_amd64_0.1.0`).
- **Docker Images**:
  - Defines separate `dockers` entries for each architecture (`amd64`, `386`, `arm/v6`, `arm64`, `riscv64`).
  - Uses `image_templates` to generate tags like `ghcr.io/nicholas-fedor/goreleaser-example:<arch>-0.1.0` and `<arch>-latest`.
  - Specifies `build_flag_templates` with `--platform` for each architecture (e.g., `--platform=linux/amd64`).
  - Includes OCI labels for metadata (e.g., version, source, licenses).
- **Attestations**:
  - Enables SLSA provenance with `--attest=type=provenance,mode=max` for maximum detail.
  - Generates SBOMs with `--attest=type=sbom` using Syft.
  - Configured per architecture to ensure attestations are associated with each image.
- **SBOMs and Checksums**:
  - Generates SBOMs for archives (`sboms.artifacts: archive`).
  - Creates a `checksums.txt` file for release integrity.

## GitHub Actions Workflows

The release process is automated through three GitHub Actions workflows:

1. **release.yaml**:
   - Triggers on tag pushes (e.g., `v0.1.0`) or manual dispatch.
   - Calls `build.yaml` to build artifacts and `create-manifests.yaml` to create multi-arch manifests.
   - Requires permissions: `contents:write`, `packages:write`, `attestations:write`, `id-token:write`.

2. **build.yaml**:
   - **Setup**: Configures Go, QEMU, Docker Buildx, and the containerd snapshotter for multi-platform support.
   - **Syft Installation**: Installs Syft for SBOM generation.
   - **Authentication**: Logs in to GHCR using the GitHub token.
   - **GoReleaser**: Runs `goreleaser release --clean` to build binaries, images, SBOMs, and attestations.
   - **Artifacts**: Uploads SBOMs and generates provenance attestations for the checksum file.
   - **Cleanup**: Removes the `dist` directory to avoid leftover artifacts.

3. **create-manifests.yaml**:
   - **Authentication**: Logs in to GHCR (Docker Hub support is commented out).
   - **Cleanup**: Removes existing manifests to prevent conflicts.
   - **Inspection**: Inspects architecture-specific manifests to extract digests.
   - **Manifest Creation**: Combines architecture-specific images (e.g., `amd64-0.1.0`, `i386-0.1.0`) into multi-arch manifests (`:0.1.0`, `:latest`) using `docker buildx imagetools create`.
   - **Pushing**: The `docker buildx imagetools create -t` command pushes the manifests directly to the registry, preserving attestations.
   - **Attestation Handling**: Uses digests to reference images, ensuring provenance and SBOMs remain associated.

## Building Locally

To build binaries and images locally (without pushing):

1. Clone the repository:

   ```bash
   git clone https://github.com/nicholas-fedor/goreleaser-example.git
   cd goreleaser-example
   ```

2. Run GoReleaser in snapshot mode:

   ```bash
   goreleaser build --snapshot --clean
   goreleaser release --snapshot --skip-publish --clean
   ```

3. Outputs are in `./dist` (binaries, archives, checksums, SBOMs). Docker images are tagged as `ghcr.io/nicholas-fedor/goreleaser-example:<arch>-snapshot`.

4. Test the application:

   ```bash
   ./dist/goreleaser-example_linux_amd64/goreleaser-example
   ```

   Open `http://localhost:8080` in a browser.

   For Windows, use the Windows binary:

   ```powershell
   .\dist\goreleaser-example_windows_amd64\goreleaser-example.exe
   ```

## Releasing

To create a release:

1. Tag a semantic version:

   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

2. The `release.yaml` workflow triggers, running `build.yaml` and `create-manifests.yaml`.

3. Verify the release on GHCR:

   ```bash
   docker manifest inspect ghcr.io/nicholas-fedor/goreleaser-example:0.1.0
   ```

## Dockerfile

The `Dockerfile` is optimized for minimal size and multi-platform support:

- **Base Image**: Uses `alpine:3.22.1` pinned to a specific digest for reproducibility.
- **Builder Stage**: Installs `ca-certificates` and `tzdata` for secure connections and timezone support.
- **Final Stage**: Starts from `scratch` for a minimal image, copying certificates, timezone data, and the GoReleaser-built binary.
- **OCI Labels**: Includes metadata like source, version, and licenses.
- **Entrypoint**: Runs the `goreleaser-example` binary, exposing port 8080.

## Attestations

Attestations are critical for supply chain security:

- **Provenance**: Generated with `--attest=type=provenance,mode=max`, providing detailed SLSA metadata about the build process.
- **SBOM**: Generated with `--attest=type=sbom` using Syft, listing software components.
- **Multi-Platform**: Each architecture-specific image (e.g., `amd64-0.1.0`) includes its own attestations, preserved in the multi-arch manifest.

Note: The attestations are not cryptographically signed in this setup. Therefore, tools like Cosign cannot be used for signature verification. Instead, use Docker commands to view and inspect the attestations.

View attestations:

- Using Docker:

  ```bash
  docker buildx imagetools inspect ghcr.io/nicholas-fedor/goreleaser-example:amd64-0.1.0 --format '{{ json .SBOM }}'
  docker buildx imagetools inspect ghcr.io/nicholas-fedor/goreleaser-example:amd64-0.1.0 --format '{{ json .Provenance }}'
  ```

## Using Syft with Generated Archives and SBOMs

The SBOMs generated by GoReleaser (using Syft) for archives (e.g., `goreleaser-example_windows_amd64_0.1.0.zip.sbom.json`) can be verified and analyzed locally to ensure accuracy and check for vulnerabilities. Below are steps to use Syft with the generated archive and SBOM on a Windows system, using `yq` (a Go-based JSON/YAML processor) for inspecting JSON SBOMs.

### Prerequisites for Syft and yq

- Ensure Syft and Grype are installed (as noted in [Prerequisites](#prerequisites)).
- Install `yq`:

  ```powershell
  go install github.com/mikefarah/yq/v4@latest
  ```

  Ensure `$env:GOPATH\bin` (or `$env:USERPROFILE\go\bin` on Windows) is in your PATH:

  ```powershell
  $env:PATH += ";$env:USERPROFILE\go\bin"
  ```

- Download the archive and SBOM from the GitHub release (e.g., for Windows):

  ```powershell
  Invoke-WebRequest -Uri "https://github.com/nicholas-fedor/goreleaser-example/releases/download/v0.1.0/goreleaser-example_windows_amd64_0.1.0.zip" -OutFile "goreleaser-example_windows_amd64_0.1.0.zip"
  Invoke-WebRequest -Uri "https://github.com/nicholas-fedor/goreleaser-example/releases/download/v0.1.0/goreleaser-example_windows_amd64_0.1.0.zip.sbom.json" -OutFile "goreleaser-example_windows_amd64_0.1.0.zip.sbom.json"
  ```

### Verify the SBOM

1. **Check SBOM Format**:
   Validate that the SBOM (`goreleaser-example_windows_amd64_0.1.0.zip.sbom.json`) is in a valid format (e.g., SPDX JSON):

   ```powershell
   syft convert goreleaser-example_windows_amd64_0.1.0.zip.sbom.json -o spdx-json
   ```

   If no errors occur, the SBOM is valid. If it’s in CycloneDX format, use `-o cyclonedx-json` instead.

2. **Cross-Check with Archive**:
   Generate a reference SBOM from the archive to ensure the provided SBOM matches the artifact:

   ```powershell
   syft scan file:goreleaser-example_windows_amd64_0.1.0.zip -o spdx-json > reference-sbom.json
   ```

   If the SBOM is for the binary inside the ZIP, unzip it first:

   ```powershell
   Expand-Archive -Path goreleaser-example_windows_amd64_0.1.0.zip -DestinationPath .\extracted
   syft scan file:.\extracted\goreleaser-example.exe -o spdx-json > reference-sbom.json
   ```

   Compare the SBOMs:

   ```powershell
   fc goreleaser-example_windows_amd64_0.1.0.zip.sbom.json reference-sbom.json
   ```

   Minor differences (e.g., timestamps) are normal, but the component list should align.

### Analyze the SBOM

1. **Inspect Components**:
   Review the SBOM to see dependencies, versions, and licenses using `yq`:

   ```powershell
   yq '.packages[] | {"name": .name, "version": .versionInfo, "license": .licenseConcluded}' goreleaser-example_windows_amd64_0.1.0.zip.sbom.json
   ```

   Alternatively, use PowerShell’s JSON parser if `yq` is unavailable:

   ```powershell
   Get-Content goreleaser-example_windows_amd64_0.1.0.zip.sbom.json | ConvertFrom-Json | Select-Object -ExpandProperty packages
   ```

2. **Scan for Vulnerabilities**:
   Use Grype to check the SBOM for known vulnerabilities:

   ```powershell
   grype sbom:goreleaser-example_windows_amd64_0.1.0.zip.sbom.json
   ```

   To focus on critical issues:

   ```powershell
   grype sbom:goreleaser-example_windows_amd64_0.1.0.zip.sbom.json --only-fixed --severity high
   ```

   Save results:

   ```powershell
   grype sbom:goreleaser-example_windows_amd64_0.1.0.zip.sbom.json -o json > vulnerabilities.json
   ```

3. **Check Licenses**:
   If license information is missing or incomplete, regenerate the SBOM with license scanning:

   ```powershell
   syft scan file:.\extracted\goreleaser-example.exe -o spdx-json --config license > license-sbom.json
   ```

   Review licenses with `yq`:

   ```powershell
   yq '.packages[] | .licenseConcluded' goreleaser-example_windows_amd64_0.1.0.zip.sbom.json
   ```

### Cleanup

After analysis, remove the downloaded and generated files:

```powershell
Remove-Item -Path goreleaser-example_windows_amd64_0.1.0.zip -Force -ErrorAction SilentlyContinue
Remove-Item -Path goreleaser-example_windows_amd64_0.1.0.zip.sbom.json -Force -ErrorAction SilentlyContinue
Remove-Item -Path reference-sbom.json -Force -ErrorAction SilentlyContinue
Remove-Item -Path vulnerabilities.json -Force -ErrorAction SilentlyContinue
Remove-Item -Path extracted -Recurse -Force -ErrorAction SilentlyContinue
```

## Running the Image

Pull and run the multi-arch image:

```bash
docker pull ghcr.io/nicholas-fedor/goreleaser-example:0.1.0
docker run -p 8080:8080 ghcr.io/nicholas-fedor/goreleaser-example:0.1.0
```

Access `http://localhost:8080` to see the "Hello World!" response.

## Multi-Platform Considerations

- **Architecture Support**: The workflow supports `amd64`, `386`, `arm/v6`, `arm64`, and `riscv64`, configured in `.goreleaser.yaml` and matched in `create-manifests.yaml` with `ARCH_TAGS` and `PLATFORMS`.
- **QEMU Emulation**: Enabled in `build.yaml` via `docker/setup-qemu-action` to support cross-platform builds.
- **Buildx**: Configured with `docker/setup-buildx-action` to handle multi-arch image builds.
- **Digest Extraction**: The `create-manifests.yaml` workflow extracts image digests (excluding attestation manifests) to create multi-arch manifests, ensuring compatibility with all architectures.

## Troubleshooting

- **Build Failures**: Check `build.yaml` logs for GoReleaser or Buildx errors. Ensure QEMU and Buildx are correctly set up.
- **Manifest Issues**: Verify architecture-specific images are pushed (`ghcr.io/nicholas-fedor/goreleaser-example:<arch>-0.1.0`). Check `create-manifests.yaml` logs for digest extraction errors.
- **Attestation Errors**: Confirm `--attest=type=provenance,mode=max` and `--attest=type=sbom` are set in `.goreleaser.yaml`. Use `docker buildx imagetools inspect` to view. If attempting Cosign verification, note that attestations are unsigned, so commands like `cosign verify-attestation` will fail with errors about missing keys.
- **SBOM Issues**: If the SBOM is empty or incomplete, regenerate it with Syft using `--scope all-layers`:

  ```powershell
  syft scan file:.\extracted\goreleaser-example.exe -o spdx-json --scope all-layers > reference-sbom.json
  ```

- **Registry Access**: Ensure the GitHub token has `write:packages` permission for GHCR. For Docker Hub, add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets.
- **yq Issues**: If `yq` commands fail, ensure it’s in your PATH and supports JSON (version 4.x). Alternatively, use PowerShell’s `ConvertFrom-Json`.

## Extending to Other Registries

To support Docker Hub:

1. Uncomment Docker Hub lines in `.goreleaser.yaml` and `create-manifests.yaml`.
2. Add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets in GitHub Settings > Secrets and variables > Actions.
3. Update `REGISTRIES` in `create-manifests.yaml` to include `docker.io/nickfedor/goreleaser-example`.

## Additional Resources

- [GoReleaser Docker Customization](https://goreleaser.com/customization/docker/)
- [Docker Buildx Multi-Platform Builds](https://docs.docker.com/build/building/multi-platform/)
- [Docker Buildx Imagetools Create](https://docs.docker.com/reference/cli/docker/buildx/imagetools/create/)
- [SLSA Provenance](https://slsa.dev/provenance/v1)
- [Syft Documentation](https://github.com/anchore/syft)
- [Grype Documentation](https://github.com/anchore/grype)
- [yq Documentation](https://mikefarah.gitbook.io/yq/)
