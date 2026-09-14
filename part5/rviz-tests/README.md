# RViz2 GPU Visualization Test Container

A standalone application container for testing GPU-accelerated ROS2 visualization (`rviz2`) on an x86_64 RHEL10 host with an NVIDIA Quadro P620, showing the GUI via X11/XWayland passthrough into the container.

## Centos based alternative (Kilted)

A RPM-based alternative `Containerfile.rviz-centos-kilted` (`quay.io/luferrar/part5:rviz-kilted`) and its own GPU load test variant, `Containerfile.rviz-pointcloud-kilted` (`quay.io/luferrar/part5:rviz-pointcloud-kilted`) using ROS2's official RPM channel.  

The image uses **CentOS Stream 9**, the official install guide's `crb
enable` step is written for CentOS Stream/RHEL-proper's CodeReady Builder repo naming.

Results:  
- the image is dramatically smaller (~6GB vs. `rviz-humble`'s 14GB)
- GPU rendering is confirmed working (`check-gpu.sh` / `nvidia-smi`)
- this Qt build *does* have a working `wayland` platform plugin but RViz2 still needs `xcb`/XWayland regardless, because `rviz-ogre-vendor`'s actual 3D render window creation is hardcoded to GLX/X11 integration independent of what platform Qt itself is running under 

See the "Test Results" section at the end for the *Pointcloud* GPU load test's findings on this image

## Fedora based alternative (Lyrical official Copr RPMs)

Upstream-supported RPM channel: `Containerfile.rviz-fedora-lyrical` (`quay.io/luferrar/part5:rviz-lyrical`), Fedora 44 base, ROS2 "Lyrical" from the Fedora robotics-sig's own `hellaenergy/ros2` Copr.

Results:  
- the image is smaller still than Kilted (~2.5GB vs. ~6GB)
- it doesn't need EPEL/CodeReady Builder
- it needs two runtime dependencies added explicitly that `ros-lyrical-ros-desktop` doesn't pull in, `rviz2` fails at library-load time without them
- GPU rendering confirmed working:  `check-gpu.sh` shows the real GLX renderer (`Quadro P620/PCIe/SSE2`), and `nvidia-smi` on the host shows an actual `rviz2` GPU process while it's running
- no pure Wayland like the rest of tests: `QT_QPA_PLATFORM=wayland` fails with the identical `OgreGLXWindow.cpp`/`GLXWindow::create`/`Invalid parentWindowHandle` error. `xcb` (XWayland) launches clean.

See the "Test Results" section at the end for the *Pointcloud* GPU load test's findings on this image

## RoboStack RHEL10 image

RHEL10 has no official ROS2 RPMs.

This image is based on `ubi10` and with RoboStack it sidesteps the RPMs problem entirely: it builds ROS2 (including `rviz2`) via conda-forge, with its own vendored Ogre build; `ros-humble-desktop` from 
`-c conda-forge -c robostack-humble` includes `rviz2`.

### X11/XWayland or Wayland

Wayland passthrough was tried, but RoboStack/conda-forge's Qt build for `ros-humble-desktop` has no `wayland` platform plugin at all (`eglfs, minimal, minimalegl, offscreen, vnc, webgl, xcb`). 

`xcb` connects through **XWayland** instead.  
*RHEL10 removes the standalone Xorg server, but keeps XWayland specifically for X11 app compatibility. GNOME/Mutter starts it automatically the moment an X11 client tries to connect. So this still works on a normal RHEL10 Wayland desktop; it just goes through the compatibility layer rather than talking to Wayland natively.*

## RVIZ test applications

### Prerequisites

- RHEL10 host with the NVIDIA driver working **and** `nvidia-container-toolkit` installed with a generated CDI spec, the driver alone is not enough (see `nvidia-cdi-setup.md`).  
- the container application does **not** install any NVIDIA driver; it's injected at runtime via `--device nvidia.com/gpu=all`, which has nothing to resolve against without that setup.  
- A desktop session running on the host with `$DISPLAY` set (check with `echo $DISPLAY`, this is
  XWayland's socket), present on a normal GNOME Wayland session, not a separate X11 session you need to
  set up.
- `podman` version to support CDI devices (`--device vendor.com/device=...`).

### Before running test applications

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
permissions unchanged, it doesn't grant access on its own. If they're group-owned by `render`/`video`
and your user isn't in that group, `run-rviz-test.sh`'s non-root `--user` will get permission denied
opening them, not a helpful error. Fix is group membership:
```bash
sudo usermod -aG render,video "$USER"   # then log out and back in
```

### Building rviz test applications

```bash
podman build -t quay.io/luferrar/part5:rviz-humble -f Containerfile.rviz-humble .
podman build -t quay.io/luferrar/part5:rviz-kilted -f Containerfile.rviz-centos-kilted .
podman build -t quay.io/luferrar/part5:rviz-lyrical -f Containerfile.rviz-fedora-lyrical .
```


### Running rviz test applications

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
Look for `NVIDIA`/`Quadro P620` in the renderer string, `llvmpipe` means software rendering.

```bash
# On the HOST, while rviz2 is running in the container
nvidia-smi
```
Confirm a GPU process actually shows up, the more reliable of the two checks, since it reflects what
the driver itself sees rather than just what the app reports.

## GPU Load Test (gpu_pointcloud_test)

ROS2 application leveraging RViz, created for generating a controllable, sustained GPU load: run this alongside `cyclictest` on the isolated cores, to see whether real GPU/rendering activity on the housekeeping cores actually disturbs RT timing.

It wraps [`../gpu_pointcloud_test/`](../gpu_pointcloud_test/) (see that package's own README for full
details), which loads a point cloud (synthetic by default), applies a deliberately GPU-heavy iterative
warp (CuPy, falling back to NumPy automatically if no GPU/CuPy is available), and republishes it as a
high-frequency `PointCloud2` for RViz. `gpu_iterations`, `num_points`, and `neighbor_sample` control
how heavy the load is.

Three versions built based on the RVIZ images above, plus one built directly on an upstream image
instead of one of this directory's own:
- related to rviz-humble but built standalone from scratch (`Containerfile.rviz-pointcloud`): as `gpu_pointcloud_test` only needs `ros-humble-ros-base` + `rviz2`, not the full `ros-humble-desktop` metapackage
- rviz centos kilted variation (`Containerfile.rviz-pointcloud-kilted`)
- rviz fedora lyrical variation (`Containerfile.rviz-pointcloud-lyrical`)
- rviz moveit2 variation (`Containerfile.rviz-pointcloud-moveit2`), layered directly on
  [`moveit/moveit2:jazzy-release`](https://hub.docker.com/r/moveit/moveit2) (Ubuntu 24.04/Jazzy) instead
  of one of this directory's own base images

### Building pointcloud images

Build context is the **parent** directory (`part5/`), since it needs to reach the sibling `gpu_pointcloud_test/` package:  

```bash
cd /path/to/part5
podman build -t quay.io/luferrar/part5:rviz-pointcloud -f rviz-tests/Containerfile.rviz-pointcloud .  
podman build -t quay.io/luferrar/part5:rviz-pointcloud-kilted -f rviz-tests/Containerfile.rviz-pointcloud-kilted .  
podman build -t quay.io/luferrar/part5:rviz-pointcloud-lyrical -f rviz-tests/Containerfile.rviz-pointcloud-lyrical .  
podman build -t quay.io/luferrar/part5:rviz-pointcloud-moveit2 -f rviz-tests/Containerfile.rviz-pointcloud-moveit2 .  
```

### Running pointcloud application

Same launcher as the base image:  

```bash
cd rviz-tests
./run-rviz-test.sh quay.io/luferrar/part5:rviz-pointcloud                     # node + RViz, tuned defaults
./run-rviz-test.sh quay.io/luferrar/part5:rviz-pointcloud -- check-gpu.sh     # renderer check
```

*The plain launch above uses the image's tuned defaults (`num_points=200000 gpu_iterations=80 neighbor_sample=800`).*

Watch the terminal at startup for `Compute backend: cupy (GPU)`, if it says `numpy (CPU)` instead, CuPy didn't find the GPU; check with `nvidia-smi` the same way as the [GPU verification](#verifying-the-gpu-is-actually-being-used) above.


## Pointcloud Test Results

Findings from testing on `lenovo-p330` (Quadro P620), running RT kernel `6.12.0-211.51.1.el10_2.x86_64+rt` for both runs below. Same image, same host, same kernel for all; only the launch parameters differed.  

### Robostack RHEL10 - Heavy parameters

Based on Pointcloud default parameters (`num_points=1000000 gpu_iterations=400 neighbor_sample=3000`), it crashed after 20 frames. The Python side raised:

```
cupy_backends.cuda.api.driver.CUDADriverError: CUDA_ERROR_ILLEGAL_ADDRESS: an illegal memory access was encountered
```

from `_neighbor_stress`'s pairwise-distance computation (`diff = sub[:, None, :] - sub[None, :, :]`).
`journalctl -k` at the same moment:

```
NVRM: Xid (PCI:0000:01:00): 13, Graphics SM Warp Exception on (GPC 0, TPC 0): Out Of Range Address
NVRM: Xid (PCI:0000:01:00): 13, Graphics Exception: ESR 0x504648=0x114000e 0x504650=0x20 0x504644=0xd3eff2 0x50464c=0x17f
NVRM: Xid (PCI:0000:01:00): 43, pid=28721, name=gpu_pointcloud_, channel 0x00000030
```

Xid 13 is the GPU hardware itself detecting an out-of-bounds memory access inside a running kernel. Xid 43
is the driver's recovery: it reset only that process's channel rather than the whole GPU, `nvidia-smi` was fully responsive immediately afterward (GPU-Util, memory, temp all normal), so this was a contained fault, not a GPU hang or system crash.  

### Robostack RHEL 10 - Tuned parameters 

With tuned down parameters (`num_points=200000 gpu_iterations=80 neighbor_sample=800`) it ran cleanly for 2h53m straight, 4642 frames over a single continuous run.  
Steady-state (excluding the first frame, which shows the same one-time JIT-compile inflation as the heavy run's first frame: 2316ms vs. everything else): **avg 139ms/frame, min 114ms, max 142ms** , consistent, no jitter of note. 

### Kilted Centos - Tuned parameters

Pointcloud test application with the same tuned parameters as above (`num_points=200000 gpu_iterations=80 neighbor_sample=800`) running on `Containerfile.rviz-pointcloud-kilted`. 

GPU acceleration is working: `Compute backend: cupy (GPU)` at startup, a first-frame JIT-compile warmup (2174ms), then a steady state around **176ms/frame** about 27% slower per-frame compute than the Rbotostack image's 139ms at the identical parameters.

It crashed after about 4.5 minutes (~1500 frames). Same fault signature as before:  

```
NVRM: Xid (PCI:0000:01:00): 13, Graphics SM Warp Exception on (GPC 0, TPC 0): Out Of Range Address
NVRM: Xid (PCI:0000:01:00): 13, Graphics SM Global Exception on (GPC 0, TPC 0): Physical Multiple Warp Errors
NVRM: Xid (PCI:0000:01:00): 13, Graphics Exception: ESR 0x504648=0x135000e 0x504650=0x24 0x504644=0xd3eff2 0x50464c=0x17f
NVRM: Xid (PCI:0000:01:00): 43, pid=54146, name=gpu_pointcloud_, channel 0x00000030
```

Same recovery behavior too, Xid 43 reset just that process's channel, `nvidia-smi` was fully healthy
immediately after (564MiB used, 20% util, normal temp), no other unusual host activity in the journal
around that time. A contained fault, not a GPU hang.

### Lyrical Fedora - Tuned parameters

Same tuned parameters (`num_points=200000 gpu_iterations=80 neighbor_sample=800`), on `Containerfile.rviz-pointcloud-lyrical`, launched via `run-gpu-pointcloud-lyrical.sh` rather than `ros2launch`, since this Copr has no `ros2launch` package.  

GPU acceleration is working: `cupy (GPU)` backend at startup, a first-frame JIT-compile warmup (2352ms), then a clean steady state **avg 136.8ms/frame** over the 53 frames it managed before crashing.

Identical fault signature to both earlier crashes:

```
NVRM: Xid (PCI:0000:01:00): 13, Graphics SM Warp Exception on (GPC 0, TPC 0): Out Of Range Address
NVRM: Xid (PCI:0000:01:00): 13, Graphics Exception: ESR 0x504648=0x11d000e 0x504650=0x20 0x504644=0xd3eff2 0x50464c=0x17f
NVRM: Xid (PCI:0000:01:00): 43, pid=70045, name=gpu_pointcloud_, channel 0x00000028
```

Same recovery behavior too: a contained fault, not a GPU hang, consistent with both prior crashes.

### MoveIt2 Ubuntu - Tuned parameters

Same GPU load test, same tuned parameters (`num_points=200000 gpu_iterations=80 neighbor_sample=800`) on `Containerfile.rviz-pointcloud-moveit2`, layered directly on `moveit/moveit2:jazzy-release` (Ubuntu 24.04).  

GPU acceleration is working: `Compute backend: cupy (GPU)` at startup, a first-frame JIT-compile
warmup. 42 frames into running it crashed: **avg 126.9ms/frame**.

Identical fault signature to all prior crashes:

```
NVRM: Xid (PCI:0000:01:00): 13, Graphics SM Warp Exception on (GPC 0, TPC 0): Out Of Range Address
NVRM: Xid (PCI:0000:01:00): 13, Graphics Exception: ESR 0x504648=0x10e000e 0x504650=0x20 0x504644=0xd3eff2 0x50464c=0x17f
NVRM: Xid (PCI:0000:01:00): 43, pid=183945, name=gpu_pointcloud_, channel 0x00000050
```

Same recovery behavior too.

### MoveIt2 Ubuntu - Lighter parameters

Tested lighter parameters (`num_points=100000 gpu_iterations=40 neighbor_sample=400`, roughly half of
Tuned in each dimension) on this same image. Steady-state compute was correspondingly faster: **avg 34.1ms/frame** over 62 reporting windows (~3400 individual frames) before crashing again with the same signature.

### MoveIt2 Ubuntu - Lightest parameters

Ran the lightest parameter test with `num_points=20000 gpu_iterations=8 neighbor_sample=80`, roughly 10x lighter than Tuned in each dimension. Result: **clean for 91.7 minutes**, no crash, no sign of one coming, with
steady-state compute of **avg 6.40ms/frame** .
 
Launched with:  

```bash
cd rviz-tests
./run-rviz-test.sh quay.io/luferrar/part5:rviz-pointcloud-moveit2 --   ros2 launch gpu_pointcloud_test gpu_pointcloud.launch.py     num_points:=20000 gpu_iterations:=8 neighbor_sample:=80
```

What actually distinguishes the crashing runs from this clean one: `num_points` and `neighbor_sample` are both far smaller here (20,000 and 80) than in any crashing run (100,000+/400+), while every crashing run used `num_points` ≥100,000. That's consistent with a **threshold effect tied to per-operation array/kernel size**  e.g. a specific memory address range, block/grid configuration, or buffer size that only becomes reachable once a single kernel launch's data is large enough. This is a plausible next hypothesis, not a confirmed one; testing it properly would mean holding `num_points` at a crash-inducing value while further reducing
`gpu_iterations`/`neighbor_sample` (to isolate whether it's `num_points` specifically or the other two
parameters that matter).

## Root-cause-analysis of crashes

- **CUDA toolkit version**: identical CUDA Build/NVRTC version (12090 / 12.9) across Robostack, Centos/Kilted, Fedora/Lyrical, Moveit2 image. Robostack, Fedora/Lyrical and Moveit2 images even share the exact same CuPy version (14.2.0).
- **Host desktop/GPU contention**: checked `journalctl` in a window around all three Xid faults for `gnome-shell`, `gnome-remote-desktop`, `Xwayland`, or `mutter` activity that might indicate the desktop compositor competing for the P620's 2GB VRAM at the moment of each fault and **nothing** showed up in any of the three windows.
- **thermal/power throttling**: `nvidia-smi -q` showed "SW Power Cap: Not Active", "HW Slowdown: Not Active", 56°C against a 100°C threshold, nothing throttling)


## Conclusions & results

Four ROS2 distribution mechanisms were built and tested:  
1. RoboStack/conda-forge on RHEL10 (`rviz-humble`)
2. Official RPMs on CentOS Stream 9 (`rviz-centos-kilted`)
3. Fedora with the robotics-sig's own Copr (`rviz-fedora-lyrical`)
4. MoveIt2's official image, Ubuntu 24.04/Jazzy (`rviz-pointcloud-moveit2`)

All four get GPU-accelerated `rviz2` rendering and, via `gpu_pointcloud_test`, GPU-accelerated compute. Compute parameters for tuning are `num_points`/`gpu_iterations`/`neighbor_sample`; ms/frame is steady-state average, excluding the JIT-compile-inflated first frame every run shows:

| Image | Basis | Size | Params | Avg ms/frame | Sustained-load result |
|---|---|---|---|---|---|
| `rviz-pointcloud` | conda-forge/RoboStack | 13.5GB | 200000/80/800 (tuned) | 139ms | Clean zero faults |
| `rviz-pointcloud-kilted` | Kilted RPMs, CentOS Stream 9 | 8.9GB | 200000/80/800 (tuned) | 176ms | Crash at ~4.5min |
| `rviz-pointcloud-lyrical` | Fedora with Copr RPMs | 5.6GB | 200000/80/800 (tuned) | 137ms | Crash at ~114s |
| `rviz-pointcloud-moveit2` | MoveIt2 official image, Ubuntu/apt | 6.9GB | 200000/80/800 (tuned) | 126.9ms | Crash at ~85s |
| `rviz-pointcloud-moveit2` | MoveIt2 official image, Ubuntu/apt | 6.9GB | 100000/40/400 (light) | 34.1ms | Crash at ~129s |
| `rviz-pointcloud-moveit2` | MoveIt2 official image, Ubuntu/apt | 6.9GB | 20000/8/80 (lightest) | 6.40ms | Clean zero faults |
| `rviz-pointcloud-kilted` | Kilted RPMs, CentOS Stream 9 | 8.9GB | 20000/8/80 (lightest) | 6.50ms | Clean zero faults |
| `rviz-pointcloud` | conda-forge/RoboStack | 13.5GB | 20000/8/80 (lightest) | 5.49ms | Clean zero faults |

Here is the video recording of the test with the `rviz-pointcloud-moveit2` image:  
[![Rviz2](http://img.youtube.com/vi/DyzK77TJg8U/0.jpg)](http://www.youtube.com/watch?v=DyzK77TJg8U "Moveit2 test")

<!--
The non-conda images are the better fit on paper — smaller, no conda/micromamba layer, and each faster
per-frame than the conda image at the same tuned settings. At tuned settings specifically, that ranking
inverts under sustained load: all three non-conda builds crashed with the identical Xid 13/43 fault,
each one faster than the last.

The last three rows complete the comparison at this much-lighter load (1/10th tuned in each dimension):
the fault disappeared on every image tested at that load, not just the one it was first discovered on —
91.7 minutes clean on MoveIt2/Ubuntu, **~27 minutes clean on Kilted** (812 frames), and **~11 minutes
clean on conda-forge** (326 frames) — see the "Follow-up" sections above for the full progression: tuned
→ light → even lighter, and the cumulative-compute-volume reasoning that motivated trying successively
lighter loads, later falsified by the 91.7-minute result itself. The conda result isn't surprising —
conda-forge's build was already proven stable at much heavier (tuned) load for nearly 3 hours, so
staying clean at a 10x-lighter load is expected, included here mainly for a consistent three-way
comparison at the same settings, not as a new finding. The Kilted and conda runs were both only
*intended* as 5-minute confirmations (`timeout -k 10 300` wrapping the launcher), but that only kills the
`podman run` client process, not the detached container it starts — a real gotcha worth knowing about if
reusing this pattern. Both containers kept running unattended well past 5 minutes before being noticed
and stopped directly by container ID; the extra runtime is genuine, verified data (captured to a file
before stopping each time, not lost to `--rm` cleanup), not a mistake to discard. So this was never
strictly "conda-forge's build is stable, the others aren't" — it's that **conda-forge's specific build
stays stable at a load level (tuned) that the RPM/apt builds cannot sustain**, not that those builds are
unconditionally broken; at a light enough load, all three tested so far behave the same way. Lyrical
hasn't been tested at this load.

**For sustained/production-shaped GPU compute workloads on this hardware, use the conda-forge/RoboStack
image (`Containerfile.rviz-humble`) and its `gpu_pointcloud_test` variant
(`Containerfile.rviz-pointcloud`)** if you want tuned-level throughput with proven multi-hour stability —
it's the only image with that combination demonstrated. If a much lighter compute load is acceptable,
`rviz-pointcloud-moveit2` and `rviz-pointcloud-kilted` at the "even lighter" settings above are both
demonstrated, much smaller (6.9GB/8.9GB vs. 13.5GB) alternatives with clean runs behind them — genuinely
stable, just at a fraction of the throughput.

That recommendation is scoped to the compute-heavy case specifically, not to `rviz2` visualization on
its own — nothing here suggests plain `rviz2` (no `gpu_pointcloud_test` alongside it) is unstable on any
of the four images; all the observed crashes happened inside `gpu_pointcloud_test`'s CuPy compute path,
never from `rviz2` rendering by itself. For a lightweight, short-lived, or purely-visualization use case
where image size and packaging convenience matter more than proven long-run stability, any of the other
three is a reasonable alternative — Fedora/Lyrical for RHEL-family packaging, or MoveIt2/Ubuntu for the
least Containerfile complexity of the four (no EPEL/CRB wrangling, no from-source workarounds).
-->

## Files

- **Containerfile.rviz-humble**: UBI10 base + RoboStack (`ros-humble-desktop`, includes `rviz2`) via micromamba
- **entrypoint-humble.sh**: activates the `ros_env` micromamba environment, then execs the given command
- **check-gpu.sh**: prints the EGL/GLX renderer string to confirm NVIDIA vs. software rendering
- **run-rviz-test.sh**: host-side launcher, mounts the X11/XWayland socket, passes the GPU via CDI,
  runs as the host's own UID (the image has no fixed user; `/etc/passwd` is bind-mounted read-only so
  the arbitrary UID still resolves to a name)
- **Containerfile.rviz-pointcloud**: standalone (`ros-base` + `rviz2`) image for [`../gpu_pointcloud_test/`](../gpu_pointcloud_test/), see [above](#gpu-load-test-gpu_pointcloud_test)
- **entrypoint-pointcloud.sh**: same activation pattern as `entrypoint-humble.sh`, plus overlaying the
  `gpu_pointcloud_test` colcon workspace
- **Containerfile.rviz-centos-kilted**: the RPM-based alternative (`rviz-kilted`), see the "Centos
  based alternative (Kilted)" section above
- **entrypoint-kilted.sh**: sources `/opt/ros/kilted/setup.bash`, then execs the given command
- **Containerfile.rviz-pointcloud-kilted**: `gpu_pointcloud_test` layered on `rviz-kilted` instead of the
  conda-based image, see the "Test Results Kilted Centos-Based Image" section above
- **entrypoint-pointcloud-kilted.sh**: same pattern as `entrypoint-kilted.sh`, plus overlaying the
  `gpu_pointcloud_test` colcon workspace and the `nvidia-*` wheel library-path discovery it needs
- **Containerfile.rviz-fedora-lyrical**: the Fedora + official Copr RPMs alternative (`rviz-lyrical`), see
  the "Fedora based alternative (Lyrical & official Copr RPMs)" section above
- **entrypoint-lyrical.sh**: sources `/opt/ros/lyrical/setup.bash`, then execs the given command
- **Containerfile.rviz-pointcloud-lyrical**: `gpu_pointcloud_test` layered on `rviz-lyrical`, see the
  "Test Results Lyrical Fedora-Based Image" section above
- **entrypoint-pointcloud-lyrical.sh**: same pattern as `entrypoint-lyrical.sh`, plus overlaying the
  `gpu_pointcloud_test` colcon workspace and the `nvidia-*` wheel library-path discovery it needs
- **run-gpu-pointcloud-lyrical.sh**: drives the node + `rviz2` directly via `ros2 run`, since this
  Copr has no `ros2launch` package to provide the `ros2 launch` verb `Containerfile.rviz-pointcloud`/
  `Containerfile.rviz-pointcloud-kilted` rely on, see the Containerfile's own comments
- **Containerfile.rviz-pointcloud-moveit2**: `gpu_pointcloud_test` layered directly on
  [`moveit/moveit2:jazzy-release`](https://hub.docker.com/r/moveit/moveit2); see the Containerfile's own
  comments for the Ubuntu/Debian-specific quirks that come with that
- **entrypoint-pointcloud-moveit2.sh**: same pattern as the other `entrypoint-pointcloud-*.sh` scripts,
  sourcing `/opt/ros/jazzy/setup.bash` instead
- **nvidia-cdi-setup.md**: how to install `nvidia-container-toolkit` and generate the CDI spec this
  container's GPU passthrough depends on
