# Guide: Migrating NVIDIA Proprietary Driver to RPM Fusion (akmods) on CentOS Stream 10

This document summarizes the steps taken to replace the manually installed NVIDIA proprietary `.run` driver with the packaged **RPM Fusion (akmods)** driver stack on a headless **Lenovo ThinkStation P330 Tiny** running CentOS Stream 10 / RHEL 10. This setup ensures that future kernel updates will automatically compile the driver without breaking graphics acceleration or container frameworks (CDI).

---

## Phase 1: Clean Up the Manual Driver
To prevent file system and driver conflicts, the manual installer must be completely removed.

```bash
# Uninstall using the original installer file
sudo bash NVIDIA-Linux-x86_64-580.178.04.run --uninstall

# Alternative generic uninstaller tool if the file is missing
sudo nvidia-uninstall
```

---

## Phase 2: Setup Repositories & Fix Version Conflicts
We enabled the proper repositories for CentOS Stream 10 and configured precise repository-level exclusions to stop the official Red Hat Extensions repository from pushing mismatching versions (like `610.xx` or `595.xx`).

### 1. Enable EPEL 10 and RPM Fusion
```bash
# Enable CodeReady Linux Builder (CRB) dependency
sudo dnf config-manager --set-enabled crb

# Install EPEL 10 and RPM Fusion repositories
sudo dnf install epel-release
sudo dnf install https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-10.noarch.rpm \
https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-10.noarch.rpm
```

### 2. Configure Global and Repo-Specific Exclusions
To keep the RPM Fusion `580xx` legacy stream safe while preserving future updates, we isolated the exclusions.

Open `/etc/dnf/dnf.conf` and block the generic enterprise metadata wrapper:
```ini
[main]
...
exclude=nvidia-driver-common*
```

Next, open the specific Red Hat repository configuration file (typically `/etc/yum.repos.d/redhat.repo`), locate the Extensions block, and append the package exclusions:
```ini
[rhel-10-for-x86_64-extensions-rpms]
...
enabled=1
excludepkgs=nvidia-persistenced*,nvidia-modprobe*
```

---

## Phase 3: Install and Compile the Driver Stack
The NVIDIA Quadro P620 utilizes the **Pascal architecture**, which is natively supported by the RPM Fusion `580xx` branch.

```bash
# Clear old package cache metadata
sudo dnf clean all

# Install the correct driver modules, utilities, and libraries
sudo dnf install akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda xorg-x11-drv-nvidia-580xx-power

# Force akmods to compile the kernel object for the active kernel version
sudo akmods --force --kernels $(uname -r)

# Flush any trapped driver modules from the boot image
sudo dracut --force --verbose
```

---

## Phase 4: Configure Headless Hardware-Accelerated RDP
Because this ThinkStation runs completely headlessly, GNOME Remote Desktop and its window manager (`mutter`) fall back to software rendering (`swrast`) unless explicitly directed to map against NVIDIA's Generic Buffer Management (GBM) and EGL pipeline under Wayland.

### 1. Force GDM to Allow Wayland on NVIDIA Drivers
```bash
# Bypass the udev script that disables Wayland when an NVIDIA driver is detected
sudo ln -s /dev/null /etc/udev/rules.d/61-gdm.rules
```
Ensure that `WaylandEnable=false` is **commented out** or removed inside `/etc/gdm/custom.conf`.

### 2. Configure System Variables and DRM Pipeline
Open `/etc/environment` and append the direct driver linkage parameters:
```text
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
MUTTER_DEBUG_ENABLE_VIRTUAL_KMS=1
EGL_PLATFORM=wayland
CLUTTER_BACKEND=wayland
```

### 3. Apply Boot Arguments and System Configuration Cleanups
```bash
# Add direct rendering nodes permissions rule for virtual seats
echo 'SUBSYSTEM=="drm", GROUP="video", MODE="0660"' | sudo tee /etc/udev/rules.d/99-drm.rules
sudo udevadm control --reload-rules && sudo udevadm trigger

# Remove lingering corrupted boot configuration lines (e.g., grub_users) causing systemd-logind errors
sudo sed -i '/^grub_/d' /boot/loader/entries/*.conf

# Regenerate initramfs images to seal the configuration, then reboot
sudo dracut --force --verbose
sudo reboot
```

---

## Verification & Key Outcomes
* **`nvidia-fallback.service` is skipped:** Confirms that the open-source Nouveau driver is successfully blacklisted and the proprietary driver loads cleanly.
* **`nvidia-cdi-refresh.service` passes successfully:** Containers using CDI can natively discover your graphics capabilities.
* **`nvidia-smi` Process Tracking:** While GNOME's "About" panel cosmically reports "Software Rendering" due to virtual display mapping, running `nvidia-smi` confirms that `gnome-shell`, `gnome-remote-desktop-daemon`, and heavy 3D application runtimes like **`rviz2`** are actively utilizing GPU VRAM resources with zero CPU performance overhead.