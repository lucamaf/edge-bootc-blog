# RViz2 GPU Visualization Test Container

A standalone application container (not a bootc OS image, unlike the rest of `part5/`) for testing
GPU-accelerated ROS2 visualization (`rviz2`) on an x86_64 RHEL10 host with an NVIDIA Quadro P2200,
showing the GUI via Wayland passthrough into the container.

## Why RoboStack instead of RPMs

RHEL10 has no official ROS2 RPMs. The Fedora robotics-sig documents a
[Copr-based install for CentOS Stream 10](https://docs.fedoraproject.org/en-US/robotics-sig/ros2/) via
`hellaenergy/ros2` (ROS2 "Lyrical") / `hellaenergy/ros2-jazzy`, but that repo's own docs say plainly:

> The `rviz2` 3D visualizer is not available in this Copr due to upstream build issues with Ogre and
> Assimp on Fedora.

Confirmed directly against both Copr projects' package lists — no `rviz2`/`ogre`/`assimp` package
exists on any target, including CentOS Stream 10. Since this failure is in Fedora's own Ogre/Assimp
packaging (not RHEL10-specific), building from RPM sources hits the same wall.

RoboStack sidesteps this entirely: it builds ROS2 (including `rviz2`) via conda-forge, with its own
vendored Ogre build, independent of Fedora's packaging. `ros-humble-desktop` from
`-c conda-forge -c robostack-humble` includes `rviz2`.

## Prerequisites

- RHEL10 host with the NVIDIA driver, `nvidia-container-toolkit`, and a generated CDI spec already in
  place (this container assumes that's done — it does **not** install the NVIDIA driver itself; that's
  injected at runtime via `--device nvidia.com/gpu=all`).
- A Wayland desktop session running on the host (the launcher script needs a live
  `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` socket to bind-mount in).
- `podman` new enough to support CDI devices (`--device vendor.com/device=...`).

## Build

```bash
podman build -t quay.io/luferrar/rviz-tests:humble -f Containerfile .
```

First build takes a while — the `ros-humble-desktop` conda solve/install pulls a large package set.

## Run

```bash
./run-rviz-test.sh                                            # launches rviz2 (default)
./run-rviz-test.sh quay.io/luferrar/rviz-tests:humble -- bash  # interactive shell
./run-rviz-test.sh quay.io/luferrar/rviz-tests:humble -- check-gpu.sh
```

Run this from a terminal *inside* the host's Wayland session (not a bare SSH session without a
compositor available) — the script exits with an error if it can't find the Wayland socket.

## Verifying the GPU is actually being used

GPU passthrough for GUI apps is easy to get "working" but silently falling back to software
rendering, or having only XWayland (not the app itself) touch the GPU. Check both:

```bash
# Inside the container
./run-rviz-test.sh quay.io/luferrar/rviz-tests:humble -- check-gpu.sh
```
Look for `NVIDIA`/`Quadro P2200` in the renderer string — `llvmpipe` means software rendering.

```bash
# On the HOST, while rviz2 is running in the container
nvidia-smi
```
Confirm a GPU process actually shows up. This is the more reliable check: there's a known class of
issue where rviz2 under Wayland renders through XWayland compositing rather than a native GPU context,
in which case `nvidia-smi` may not show the app itself even though something is drawing.

## If Wayland passthrough gives you trouble

Wayland was chosen deliberately for this container, but native-Wayland GPU-accelerated Qt apps have
more rough edges than the X11/XWayland path. If `rviz2` fails to open a window or renders incorrectly,
fall back to X11 as a quick diagnostic:

```bash
xhost +local:podman   # on the host
podman run --rm -it \
    --device nvidia.com/gpu=all \
    -e NVIDIA_DRIVER_CAPABILITIES=all -e NVIDIA_VISIBLE_DEVICES=all \
    -e DISPLAY="$DISPLAY" -e QT_QPA_PLATFORM=xcb \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    -v /etc/passwd:/etc/passwd:ro \
    --user "$(id -u):$(id -g)" \
    --security-opt label=disable \
    quay.io/luferrar/rviz-tests:humble
```
If that works and Wayland doesn't, it isolates the problem to the Wayland plumbing rather than
GPU/driver/RoboStack itself.

## Files

- **Containerfile**: UBI10 base + RoboStack (`ros-humble-desktop`, includes `rviz2`) via micromamba
- **entrypoint.sh**: activates the `ros_env` micromamba environment, then execs the given command
- **check-gpu.sh**: prints the EGL/GLX renderer string to confirm NVIDIA vs. software rendering
- **run-rviz-test.sh**: host-side launcher — mounts the Wayland socket, passes the GPU via CDI, runs
  as the host's own UID (the image has no fixed user; `/etc/passwd` is bind-mounted read-only so the
  arbitrary UID still resolves to a name)