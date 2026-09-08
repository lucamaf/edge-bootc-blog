# RViz2 GPU Visualization Test Container

A standalone application container for testing GPU-accelerated ROS2 visualization (`rviz2`) on an x86_64 RHEL10 host with an NVIDIA Quadro P620, showing the GUI via X11/XWayland passthrough into the container.

## Centos based alternative (Kilted)

A RPM-based alternative — `Containerfile.rviz-centos-kilted`
(`quay.io/luferrar/part5:rviz-kilted`) and its own GPU load test variant, `Containerfile.rviz-pointcloud-kilted`
(`quay.io/luferrar/part5:rviz-pointcloud-kilted`) — using ROS2's official RPM channel instead of conda.

The image uses **CentOS Stream 9**, not UBI9 — the official install guide's `crb
enable` step is written for CentOS Stream/RHEL-proper's CodeReady Builder repo naming.

Results:  
- the image is dramatically smaller (~6GB vs. `rviz-humble`'s 14GB)
- GPU rendering is confirmed working (`check-gpu.sh` / `nvidia-smi`)
- this Qt build *does* have a working `wayland` platform plugin (unlike RoboStack's, which has none at all) — but RViz2 still needs `xcb`/XWayland regardless, because `rviz-ogre-vendor`'s actual 3D render window creation is hardcoded to GLX/X11 integration independent of what platform Qt itself is running under 

See the "Test Results" section at the end for the *Pointcloud* GPU load test's findings on this image

## Fedora based alternative (Lyrical & official Copr RPMs)

Upstream-supported RPM channel: `Containerfile.rviz-fedora-lyrical` (`quay.io/luferrar/part5:rviz-lyrical`), Fedora 44 base, ROS2 "Lyrical" from the Fedora robotics-sig's own `hellaenergy/ros2` Copr .

Results:  
- the image is smaller still than Kilted (~2.5GB vs. ~6GB)
- it needs no EPEL/CodeReady Builder wrangling
- it needs two runtime dependencies added explicitly that `ros-lyrical-ros-desktop` doesn't pull in, `rviz2` fails at library-load time without them
- GPU rendering confirmed working:  `check-gpu.sh` shows the real GLX renderer (`Quadro P620/PCIe/SSE2`), and `nvidia-smi` on the host shows an actual `rviz2` GPU process while it's running
- no pure Wayland like the rest of tests: `QT_QPA_PLATFORM=wayland` fails with the identical `OgreGLXWindow.cpp`/`GLXWindow::create`/`Invalid parentWindowHandle` error. `xcb` (the default here) launches clean.

See the "Test Results" section at the end for the *Pointcloud* GPU load test's findings on this image

## RoboStack RHEL10 image

RHEL10 has no official ROS2 RPMs. 

This image based on `ubi10` and RoboStack sidesteps this entirely: it builds ROS2 (including `rviz2`) via conda-forge, with its own vendored Ogre build, independent of Fedora's packaging. `ros-humble-desktop` from
`-c conda-forge -c robostack-humble` includes `rviz2`.

### Why X11/XWayland, not Wayland

Wayland passthrough was the original plan, but RoboStack/conda-forge's Qt build for
`ros-humble-desktop` has no `wayland` platform plugin at all (`eglfs, minimal, minimalegl, offscreen, vnc, webgl, xcb`) with no `wayland` among them. 

`xcb` connects through **XWayland** instead. RHEL10 removes the standalone Xorg server, but keeps
XWayland specifically for X11 app compatibility — GNOME/Mutter starts it automatically the moment an
X11 client tries to connect. So this still works on a normal RHEL10 Wayland desktop; it just goes
through the compatibility layer rather than talking to Wayland natively.

## RVIZ test applications

### Prerequisites

- RHEL10 host with the NVIDIA driver working **and** `nvidia-container-toolkit` installed with a generated CDI spec, the driver alone is not enough (see `nvidia-cdi-setup.md`). 
- the container application does **not** install the NVIDIA driver itself; it's injected at
  runtime via `--device nvidia.com/gpu=all`, which has nothing to resolve against without that setup.
- A desktop session running on the host with `$DISPLAY` set (check with `echo $DISPLAY`) — this is
  XWayland's socket, present on a normal GNOME Wayland session, not a separate X11 session you need to
  set up.
- `podman` version to support CDI devices (`--device vendor.com/device=...`).

### Before running images

**1. Does this host have more than one GPU (e.g. NVIDIA + integrated Intel/AMD)?**
```bash
lspci | grep -Ei 'vga|3d controller'
```
If NVIDIA is the only entry, the default Mesa/GLVND dispatch should pick it automatically, no
changes needed. If there's also an integrated GPU, Mesa may pick the wrong one; run `check-gpu.sh`
after starting the container and if the renderer string isn't NVIDIA, force it explicitly by adding
`-e __GLX_VENDOR_LIBRARY_NAME=nvidia -e __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json` to the `podman run` invocation (adjust the path if the mounted vendor JSON lands elsewhere — check
with `ls /usr/share/glvnd/egl_vendor.d/` inside the container).

**2. Can your host user actually open the GPU device nodes without root?**
```bash
ls -la /dev/nvidia* /dev/dri/render*
groups
```
`--device nvidia.com/gpu=all` (CDI) bind-mounts these nodes into the container with their *host*
permissions unchanged — it doesn't grant access on its own. If they're group-owned by `render`/`video`
and your user isn't in that group, `run-rviz-test.sh`'s non-root `--user` will get permission denied
opening them, not a helpful error. Fix is group membership:
```bash
sudo usermod -aG render,video "$USER"   # then log out and back in
```

### Building images

```bash
podman build -t quay.io/luferrar/part5:rviz-humble -f Containerfile.rviz-humble .
```


### Running images

```bash
./run-rviz-test.sh                                            # launches rviz2 (default)
./run-rviz-test.sh quay.io/luferrar/part5:rviz-humble -- bash  # interactive shell
./run-rviz-test.sh quay.io/luferrar/part5:rviz-humble -- check-gpu.sh
```

Run this from a terminal *inside* the host's desktop session (not a bare SSH session with no display
available).

### Verifying the GPU is actually being used

GPU passthrough for GUI apps is easy to get "working" but silently falling back to software
rendering. Check both:

```bash
# Inside the container
./run-rviz-test.sh quay.io/luferrar/part5:rviz-humble -- check-gpu.sh
```
Look for `NVIDIA`/`Quadro P620` in the renderer string — `llvmpipe` means software rendering.

```bash
# On the HOST, while rviz2 is running in the container
nvidia-smi
```
Confirm a GPU process actually shows up, the more reliable of the two checks, since it reflects what
the driver itself sees rather than just what the app reports.

## GPU Load Test (gpu_pointcloud_test)

Standalone image specifically for generating a controllable, sustained GPU load: run this
alongside `cyclictest` on the isolated core instead of just watching RViz sit idle, to see whether
real GPU/rendering activity on the housekeeping cores actually disturbs RT timing.

It wraps [`../gpu_pointcloud_test/`](../gpu_pointcloud_test/) (see that package's own README for full
details), which loads a point cloud (synthetic by default), applies a deliberately GPU-heavy iterative
warp (CuPy, falling back to NumPy automatically if no GPU/CuPy is available), and republishes it as a
high-frequency `PointCloud2` for RViz. `gpu_iterations`, `num_points`, and `neighbor_sample` control
how heavy the load is.

Three version built based on RVIZ images we saw above:
- related to rvi-humble but built standalone from scratch (`Containerfile.rviz-pointcloud`): as `gpu_pointcloud_test` only needs `ros-humble-ros-base` + `rviz2`, not the full `ros-humble-desktop` metapackage
- rviz centos kilted variation (`Containerfile.rviz-pointcloud-kilted`)  
- rviz fedora lyrical variation (`Containerfile.rviz-pointcloud-lyrical`)  

### Building the images

Build context is the **parent** directory (`part5/`), not this one, since it needs to reach the
sibling `gpu_pointcloud_test/` package:

```bash
cd /path/to/part5
podman build -t quay.io/luferrar/part5:rviz-pointcloud -f rviz-tests/Containerfile.rviz-pointcloud .
```

### Running the images

Same launcher as the base image:

```bash
cd rviz-tests
./run-rviz-test.sh quay.io/luferrar/part5:rviz-pointcloud                     # node + RViz together
./run-rviz-test.sh quay.io/luferrar/part5:rviz-pointcloud -- check-gpu.sh     # renderer check
./run-rviz-test.sh quay.io/luferrar/part5:rviz-pointcloud -- \
    ros2 launch gpu_pointcloud_test gpu_pointcloud.launch.py gpu_iterations:=800 num_points:=2000000
```

Watch the terminal at startup for `Compute backend: cupy (GPU)` — if it says `numpy (CPU)` instead,
CuPy didn't find the GPU; check with `nvidia-smi` the same way as the [GPU verification](#verifying-the-gpu-is-actually-being-used) above.

## Test Results

Findings from testing on `lenovo-p330` (Quadro P620), running RT kernel `6.12.0-211.51.1.el10_2.x86_64+rt` for both runs below. Same image, same host, same kernel for both; only the launch parameters
differed.

### Heavy defaults 

Based on default parameters (`num_points=1000000 gpu_iterations=400 neighbor_sample=3000`), it crashed after 20 frames. The Python side raised:

```
cupy_backends.cuda.api.driver.CUDADriverError: CUDA_ERROR_ILLEGAL_ADDRESS: an illegal memory access was encountered
```

from `_neighbor_stress`'s pairwise-distance computation (`diff = sub[:, None, :] - sub[None, :, :]`).
`journalctl -k` at the same moment (timestamps line up: last successful frame logged at 11:34:19, fault
at 11:34:22):

```
NVRM: Xid (PCI:0000:01:00): 13, Graphics SM Warp Exception on (GPC 0, TPC 0): Out Of Range Address
NVRM: Xid (PCI:0000:01:00): 13, Graphics Exception: ESR 0x504648=0x114000e 0x504650=0x20 0x504644=0xd3eff2 0x50464c=0x17f
NVRM: Xid (PCI:0000:01:00): 43, pid=28721, name=gpu_pointcloud_, channel 0x00000030
```

Xid 13 is the GPU hardware itself detecting an out-of-bounds memory access inside a running kernel —
a real fault, not just a driver-side wrapper error, and it matches the Python exception exactly. Xid 43
is the driver's recovery: it reset only that process's channel rather than the whole GPU — `nvidia-smi`
was fully responsive immediately afterward (GPU-Util, memory, temp all normal), so this was a
contained fault, not a GPU hang or system crash.

### Tuned defaults 

With tuned down parameters (`num_points=200000 gpu_iterations=80 neighbor_sample=800`) it ran cleanly for 2h53m straight, 4642 frames over a single continuous run.  
Steady-state (excluding the first frame, which shows the same one-time JIT-compile inflation as the heavy run's first frame: 2316ms vs. everything else): **avg 139ms/frame, min 114ms, max 142ms** , consistent, no jitter of note. 

### Takeaway

The tuned defaults (now the image's default `CMD`) ran clean for nearly 3 hours straight on this
hardware and this RT kernel, versus the heavy defaults faulting after 20 frames (~75 seconds of actual
compute). That's a solid basis for trusting the tuned settings for sustained use here.

### Test Results Kilted Centos-Based Image - Tuned Load

Same GPU load test as above, same tuned parameters (`num_points=200000 gpu_iterations=80 neighbor_sample=800`), same host, same RT kernel (`6.12.0-211.51.1.el10_2.x86_64+rt`), but on `Containerfile.rviz-pointcloud-kilted` instead of the conda-based `Containerfile.rviz-pointcloud`. 

GPU acceleration is working here too: `Compute backend: cupy (GPU)` at startup, a first-frame
JIT-compile warmup (2174ms, the same one-time-cost pattern seen on the conda image), then a steady
state around **176ms/frame** — about 27% slower per-frame compute than the conda image's 139ms at the
identical parameters.

It crashed after about 4.5 minutes (~1500 frames). Same fault signature as the earlier heavy-load crash on the conda image:

```
NVRM: Xid (PCI:0000:01:00): 13, Graphics SM Warp Exception on (GPC 0, TPC 0): Out Of Range Address
NVRM: Xid (PCI:0000:01:00): 13, Graphics SM Global Exception on (GPC 0, TPC 0): Physical Multiple Warp Errors
NVRM: Xid (PCI:0000:01:00): 13, Graphics Exception: ESR 0x504648=0x135000e 0x504650=0x24 0x504644=0xd3eff2 0x50464c=0x17f
NVRM: Xid (PCI:0000:01:00): 43, pid=54146, name=gpu_pointcloud_, channel 0x00000030
```

Same recovery behavior too — Xid 43 reset just that process's channel, `nvidia-smi` was fully healthy
immediately after (564MiB used, 20% util, normal temp), no other unusual host activity in the journal
around that time. A contained fault, not a GPU hang.

**Not yet root-caused.** Checked and ruled out: a direct `cupy.show_config()` comparison against the
conda image shows an *identical* CUDA Build/NVRTC version (12090 / 12.9) on both, so a less-tested pip-installed CUDA toolkit component version is not the explanation. What remains unconfirmed: CuPy's own version (13.6.0 here, older, forced by this image's Python 3.9), and whether the RT kernel is involved at all,
which remains exactly as untested as it was for the conda-based crash — both fired on the same kernel,
no standard-kernel comparison has been run.

### Test Results Lyrical Fedora-Based Image - Tuned Load

Same GPU load test, same tuned parameters (`num_points=200000 gpu_iterations=80 neighbor_sample=800`),
same host, same RT kernel (`6.12.0-211.51.1.el10_2.x86_64+rt`) — this time on `Containerfile.rviz-pointcloud-lyrical`, layered on the Fedora + official Copr RPMs image (`rviz-lyrical`). Launched via `run-gpu-pointcloud-lyrical.sh` rather than `ros2launch`, since this Copr has no `ros2launch` package.

GPU acceleration is working: `cupy (GPU)` backend at startup, a first-frame JIT-compile
warmup (2352ms, the same one-time-cost pattern seen on the other two images), then a clean steady
state — **avg 136.8ms/frame, min 133.4ms, max 138.0ms** over the 53 frames it managed before crashing.
That's actually the *best* per-frame number of the three images so far.

Identical fault signature to both earlier crashes:

```
NVRM: Xid (PCI:0000:01:00): 13, Graphics SM Warp Exception on (GPC 0, TPC 0): Out Of Range Address
NVRM: Xid (PCI:0000:01:00): 13, Graphics Exception: ESR 0x504648=0x11d000e 0x504650=0x20 0x504644=0xd3eff2 0x50464c=0x17f
NVRM: Xid (PCI:0000:01:00): 43, pid=70045, name=gpu_pointcloud_, channel 0x00000028
```

Same recovery behavior too — Xid 43 reset just that process's channel; `nvidia-smi` was healthy
immediately after (565MiB, 6% util, normal temp), and the container itself kept running (only the
backgrounded compute node process died — `rviz2`, running separately in the foreground, was unaffected
and stayed up). A contained fault, not a GPU hang, consistent with both prior crashes.

**Root-cause-analysis** This is now the *second* RPM-based image to crash under tuned load within minutes, while the conda-forge/RoboStack image ran the identical tuned settings clean for nearly 3 hours:

- **CUDA toolkit version skew.** `cupy.show_config()` run on all three images shows an *identical* CUDA
  Build/NVRTC version (12090 / 12.9) across conda, Kilted, and Fedora/Lyrical, and the conda and
  Fedora/Lyrical images even share the exact same CuPy version (14.2.0). So the pip-installed CUDA
  toolkit being a "less-tested" or different version than conda-forge's own build is directly
  contradicted by the data, not just unconfirmed.
- **Host desktop/GPU contention.** Checked `journalctl` in a window around all three Xid faults (this
  crash, the Kilted crash, and the original conda heavy-load crash) for `gnome-shell`,
  `gnome-remote-desktop`, `Xwayland`, or `mutter` activity that might indicate the desktop compositor
  competing for the P620's 2GB VRAM at the moment of each fault — nothing showed up in any of the three
  windows.

What's left unconfirmed, and would require actually building/running something new to check: whether Fedora 44's much newer Python (3.14.7, vs. conda's 3.12.14) or glibc (2.43 vs. 2.39) plays any role, and the RT-kernel question, which remains exactly as untested as before — all three crashes and the one long clean run happened on the same kernel.

## Conclusions

Three ROS2 distribution mechanisms were built and tested end to end on this host: 
1. RoboStack/conda-forge (`rviz-humble`)
2. official RPMs on CentOS Stream 9 (`rviz-kilted`)
3. Fedora + the robotics-sig's own Copr (`rviz-lyrical`). 

All three get GPU-accelerated `rviz2` rendering and, via `gpu_pointcloud_test`, GPU-accelerated compute. What separates them is what happened under sustained load:

| Image | Basis | Per-frame (tuned) | Sustained-load result |
|---|---|---|---|
| `rviz-pointcloud` | conda-forge/RoboStack | 139ms | Clean for 2h53m (4600+ frames), zero faults |
| `rviz-pointcloud-kilted` | Kilted RPMs, CentOS Stream 9 | 176ms | Xid 13/43 crash at ~4.5min |
| `rviz-pointcloud-lyrical` | Fedora + Copr RPMs | 137ms | Xid 13/43 crash at ~114s |

The RPM-based images are the better fit on paper — smaller (Fedora/Lyrical: 2.5GB vs. RoboStack's
14GB), no conda/micromamba layer, and Fedora/Lyrical in particular needs no EPEL/CodeReady Builder
wrangling at all. 

**For sustained/production-shaped GPU compute workloads on this hardware, use the conda-forge/RoboStack
image (`Containerfile.rviz-humble`) and its `gpu_pointcloud_test` variant
(`Containerfile.rviz-pointcloud`).** It's the only one of the three with hours of clean runtime behind it —
everything else here is evidence the other two *can* work, not that they reliably do.

That recommendation is scoped to the compute-heavy case specifically, not to `rviz2` visualization on
its own — nothing here suggests plain `rviz2` (no `gpu_pointcloud_test` alongside it) is unstable on any
of the three images; all the observed crashes happened inside `gpu_pointcloud_test`'s CuPy compute path,
never from `rviz2` rendering by itself. For a lightweight, short-lived, or purely-visualization use case
where image size and RHEL-friendliness matter more than proven long-run stability, the Fedora/Lyrical
image is a reasonable, much cleaner alternative.


## Files

- **Containerfile.rviz-humble**: UBI10 base + RoboStack (`ros-humble-desktop`, includes `rviz2`) via micromamba
- **entrypoint-humble.sh**: activates the `ros_env` micromamba environment, then execs the given command
- **check-gpu.sh**: prints the EGL/GLX renderer string to confirm NVIDIA vs. software rendering
- **run-rviz-test.sh**: host-side launcher — mounts the X11/XWayland socket, passes the GPU via CDI,
  runs as the host's own UID (the image has no fixed user; `/etc/passwd` is bind-mounted read-only so
  the arbitrary UID still resolves to a name)
- **Containerfile.rviz-pointcloud**: standalone (`ros-base` + `rviz2`) image for [`../gpu_pointcloud_test/`](../gpu_pointcloud_test/) — see [above](#gpu-load-test-gpu_pointcloud_test)
- **entrypoint-pointcloud.sh**: same activation pattern as `entrypoint-humble.sh`, plus overlaying the
  `gpu_pointcloud_test` colcon workspace
- **Containerfile.rviz-centos-kilted**: the RPM-based alternative (`rviz-kilted`) — see the "Centos
  based alternative (Kilted)" section above
- **entrypoint-kilted.sh**: sources `/opt/ros/kilted/setup.bash`, then execs the given command
- **Containerfile.rviz-pointcloud-kilted**: `gpu_pointcloud_test` layered on `rviz-kilted` instead of the
  conda-based image — see the "Test Results Kilted Centos-Based Image" section above
- **entrypoint-pointcloud-kilted.sh**: same pattern as `entrypoint-kilted.sh`, plus overlaying the
  `gpu_pointcloud_test` colcon workspace and the `nvidia-*` wheel library-path discovery it needs
- **Containerfile.rviz-fedora-lyrical**: the Fedora + official Copr RPMs alternative (`rviz-lyrical`) — see
  the "Fedora based alternative (Lyrical & official Copr RPMs)" section above
- **entrypoint-lyrical.sh**: sources `/opt/ros/lyrical/setup.bash`, then execs the given command
- **Containerfile.rviz-pointcloud-lyrical**: `gpu_pointcloud_test` layered on `rviz-lyrical` — see the
  "Test Results Lyrical Fedora-Based Image" section above
- **entrypoint-pointcloud-lyrical.sh**: same pattern as `entrypoint-lyrical.sh`, plus overlaying the
  `gpu_pointcloud_test` colcon workspace and the `nvidia-*` wheel library-path discovery it needs
- **run-gpu-pointcloud-lyrical.sh**: drives the node + `rviz2` directly via `ros2 run`, since this
  Copr has no `ros2launch` package to provide the `ros2 launch` verb `Containerfile.rviz-pointcloud`/
  `Containerfile.rviz-pointcloud-kilted` rely on — see the Containerfile's own comments
- **nvidia-cdi-setup.md**: how to install `nvidia-container-toolkit` and generate the CDI spec this
  container's GPU passthrough depends on
