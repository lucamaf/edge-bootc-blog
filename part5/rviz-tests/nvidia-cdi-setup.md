# Setting up nvidia-container-toolkit + CDI on the P330 (Quadro P620)

This is the piece that was missing: `lenovo-p330-nvidia-fix.md` gets the NVIDIA driver itself working
for the desktop (Wayland, `nvidia-smi`, etc.), but nothing in that process installs
`nvidia-container-toolkit` or generates a CDI spec — which is what `run-rviz-test.sh`'s
`--device nvidia.com/gpu=all` actually depends on. Without this, that flag has nothing to resolve
against and podman will fail to start the container.

The driver here was installed via the raw `.run` installer, not RPM packages (`--no-dkms`, per the
fix doc). That's fine for this — `nvidia-ctk` discovers driver libraries generically via `ldconfig`
(which the `.run` installer does register with), not by querying the RPM database, so it doesn't
require the driver to have been installed as a package.

## 1. Install nvidia-container-toolkit

```bash
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
sudo dnf install -y nvidia-container-toolkit
```

## 2. Generate the CDI spec

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

Verify it picked up the GPU:
```bash
nvidia-ctk cdi list
```
Should list `nvidia.com/gpu=all` and a per-GPU entry (e.g. `nvidia.com/gpu=0`).

## 3. Smoke-test before touching rviz2

Confirm CDI resolution and driver library injection work end-to-end with something much smaller than
the full RoboStack build:

```bash
podman run --rm --device nvidia.com/gpu=all --security-opt label=disable \
  registry.access.redhat.com/ubi10/ubi nvidia-smi
```

If that prints the GPU (driver version, `Quadro P620`), CDI is working and `run-rviz-test.sh` should
have a real device to attach to. If it fails, that's a CDI/toolkit problem to resolve here, independent
of anything in the rviz2 container itself.

## Keep this in sync with the manual driver install

Because the driver was installed `--no-dkms` (see `lenovo-p330-nvidia-fix.md`'s own maintenance note),
a kernel update will break it until manually recompiled. When that happens, re-run
`sudo ./NVIDIA-Linux-x86_64-*.run --no-dkms --kernel-module-type=proprietary` as documented there —
and then **regenerate the CDI spec too** (step 2 above), since it references specific driver library
paths/versions that a reinstall can change:

```bash
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

A stale CDI spec after a driver reinstall is a likely source of confusing "works on the host,
not in the container" failures later.