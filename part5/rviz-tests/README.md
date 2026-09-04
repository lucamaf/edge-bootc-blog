# RViz2 GPU Visualization Test Container

A standalone application container (not a bootc OS image, unlike the rest of `part5/`) for testing
GPU-accelerated ROS2 visualization (`rviz2`) on an x86_64 RHEL10 host with an NVIDIA Quadro P620,
showing the GUI via X11/XWayland passthrough into the container.

## RPM-based alternative (Kilted)

This directory has two image families. Everything below through "Files" documents the primary one
(RoboStack/conda-forge, ROS2 Humble). There's also an RPM-based alternative — `Containerfile.ros2-rpm`
(`quay.io/luferrar/part5:rviz-kilted`) and its own GPU load test variant, `Containerfile.pointcloud-rpm`
(`quay.io/luferrar/part5:rviz-pointcloud-rpm`) — built for a "cleaner, more Red Hat supported" version
of the same idea, using ROS2's official RPM channel instead of conda.

That channel doesn't target RHEL10 for any current distro, checked directly against each one's install
docs: Humble's official RPMs only target RHEL 8, Jazzy and Kilted target RHEL 9. Kilted (the newest) is
the closest match. The image uses **CentOS Stream 9**, not UBI9 — the official install guide's `crb
enable` step is written for CentOS Stream/RHEL-proper's CodeReady Builder repo naming; UBI9 names the
equivalent repo differently. It runs fine via podman on the RHEL10 host regardless, since containers
aren't tied to the host's OS version.

Results so far: the image is dramatically smaller (~6GB vs. `rviz-humble`'s 14GB, even though this is
the full `ros-kilted-desktop`, not a trimmed-down variant), and GPU rendering is confirmed working the
same way as the RoboStack images (`check-gpu.sh` / `nvidia-smi`). One genuine surprise: this Qt build
*does* have a working `wayland` platform plugin (unlike RoboStack's, which has none at all) — but RViz2
still needs `xcb`/XWayland regardless, because `rviz-ogre-vendor`'s actual 3D render window creation is
hardcoded to GLX/X11 integration independent of what platform Qt itself is running under (confirmed:
under `QT_QPA_PLATFORM=wayland`, RViz2's own log shows it calling `OgreGLXWindow.cpp`/`GLXWindow::create`
regardless). See the "Test Results" section at the end for the GPU load test's findings on this image,
including a stability difference worth knowing about before relying on it for sustained work.

### Fedora + Lyrical (official Copr RPMs)

A third alternative, even closer to a "real" upstream-supported RPM channel than the Kilted image:
`Containerfile.fedora-lyrical` (`quay.io/luferrar/part5:rviz-lyrical`), Fedora 44 base, ROS2 "Lyrical"
from the Fedora robotics-sig's own `hellaenergy/ros2` Copr — see the correction above for why this
works despite that Copr's own docs claiming `rviz2` isn't available.

The image is smaller still than Kilted (~2.5GB vs. ~6GB) and needs no EPEL/CodeReady Builder wrangling
— Fedora's own repos are self-contained. It did need two runtime dependencies added explicitly that
`ros-lyrical-ros-desktop` doesn't pull in on its own — `rviz2` fails at library-load time without them,
even though nothing in the RPM dependency chain declares them as required (a packaging gap in this
Copr, not a Fedora or dnf issue; see the Containerfile's comments for exactly how that was diagnosed).

Confirmed working the same way as the other images: `check-gpu.sh` shows the real GLX renderer
(`Quadro P620/PCIe/SSE2`), and `nvidia-smi` on the host shows an actual `rviz2` GPU process while it's
running. Same X11/XWayland-not-Wayland story as Kilted, too — `QT_QPA_PLATFORM=wayland` fails with the
identical `OgreGLXWindow.cpp`/`GLXWindow::create`/`Invalid parentWindowHandle` error, confirming
Lyrical's `rviz-ogre-vendor` hardcodes GLX the same way Kilted's does. `xcb` (the default here) launches
clean.

No GPU load test variant (`gpu_pointcloud_test`) built for this image yet — the Kilted-based one already
answered the "does the RPM approach get real GPU compute working" question, and its result (working but
less stable under sustained load than the conda image) is documented below.

## Why RoboStack instead of RPMs

RHEL10 has no official ROS2 RPMs. The Fedora robotics-sig documents a
[Copr-based install for CentOS Stream 10](https://docs.fedoraproject.org/en-US/robotics-sig/ros2/) via
`hellaenergy/ros2` (ROS2 "Lyrical") / `hellaenergy/ros2-jazzy`, and that repo's own docs say plainly:

> The `rviz2` 3D visualizer is not available in this Copr due to upstream build issues with Ogre and
> Assimp on Fedora.

That's stale, at least for the Fedora target: an unpaginated check of the Copr's package list earlier
in this project's own history wrongly concluded the same thing (zero `rviz2`/`ogre`/`assimp` packages
anywhere), but re-checking with correct API pagination turned up a full `rviz2` stack —
`ros-lyrical-rviz2`, `ros-lyrical-rviz-ogre-vendor`, `ros-lyrical-rviz-common`,
`ros-lyrical-rviz-default-plugins` — plus a `ros-lyrical-ros-desktop` metapackage pulling all of it in.
It genuinely builds and runs; see "Fedora + Lyrical (official Copr RPMs)" below. Not re-checked against
the CentOS Stream 10 chroot of the same Copr specifically — this project only built and tested the
Fedora target.

RoboStack sidesteps this entirely: it builds ROS2 (including `rviz2`) via conda-forge, with its own
vendored Ogre build, independent of Fedora's packaging. `ros-humble-desktop` from
`-c conda-forge -c robostack-humble` includes `rviz2`.

## Why X11/XWayland, not Wayland

Wayland passthrough was the original plan, but RoboStack/conda-forge's Qt build for
`ros-humble-desktop` has no `wayland` platform plugin at all — confirmed by Qt's own startup error,
which lists its available plugins (`eglfs, minimal, minimalegl, offscreen, vnc, webgl, xcb`) with no
`wayland` among them. That's a gap in how conda-forge built this specific Qt package, not a host
configuration issue, so no amount of Wayland setup on the host side would fix it.

`xcb` connects through **XWayland** instead. RHEL10 removes the standalone Xorg server, but keeps
XWayland specifically for X11 app compatibility — GNOME/Mutter starts it automatically the moment an
X11 client tries to connect. So this still works on a normal RHEL10 Wayland desktop; it just goes
through the compatibility layer rather than talking to Wayland natively.

## Prerequisites

- RHEL10 host with the NVIDIA driver working (this machine: see `lenovo-p330-nvidia-fix.md`) **and**
  `nvidia-container-toolkit` installed with a generated CDI spec — the driver alone is not enough. See
  `nvidia-cdi-setup.md`. This container does **not** install the NVIDIA driver itself; it's injected at
  runtime via `--device nvidia.com/gpu=all`, which has nothing to resolve against without that setup.
- A desktop session running on the host with `$DISPLAY` set (check with `echo $DISPLAY`) — this is
  XWayland's socket, present on a normal GNOME Wayland session, not a separate X11 session you need to
  set up.
- `podman` new enough to support CDI devices (`--device vendor.com/device=...`).

## Before you run this: 2 checks

Neither of these is verified by the tooling here — they depend on the specific host, and getting them
wrong produces confusing failures (or silent software rendering) rather than a clear error.

**1. Does this host have more than one GPU (e.g. NVIDIA + integrated Intel/AMD)?**
```bash
lspci | grep -Ei 'vga|3d controller'
```
If NVIDIA is the only entry, the default Mesa/GLVND dispatch should pick it automatically — no
changes needed. If there's also an integrated GPU, Mesa may pick the wrong one; run `check-gpu.sh`
after starting the container and if the renderer string isn't NVIDIA, force it explicitly by adding
`-e __GLX_VENDOR_LIBRARY_NAME=nvidia -e __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json`
to the `podman run` invocation (adjust the path if the mounted vendor JSON lands elsewhere — check
with `ls /usr/share/glvnd/egl_vendor.d/` inside the container).

**2. Can your host user actually open the GPU device nodes without root?**
```bash
ls -la /dev/nvidia* /dev/dri/render*
groups
```
`--device nvidia.com/gpu=all` (CDI) bind-mounts these nodes into the container with their *host*
permissions unchanged — it doesn't grant access on its own. If they're group-owned by `render`/`video`
and your user isn't in that group, `run-rviz-test.sh`'s non-root `--user` will get permission denied
opening them, not a helpful error. Fix is group membership, not `sudo podman run` (that trades a
missing-group problem for a "now everything the container writes is owned by root" one):
```bash
sudo usermod -aG render,video "$USER"   # then log out and back in
```

## Build

```bash
podman build -t quay.io/luferrar/part5:rviz-humble -f Containerfile .
```

First build takes a while — the `ros-humble-desktop` conda solve/install pulls a large package set.

## Run

```bash
./run-rviz-test.sh                                            # launches rviz2 (default)
./run-rviz-test.sh quay.io/luferrar/part5:rviz-humble -- bash  # interactive shell
./run-rviz-test.sh quay.io/luferrar/part5:rviz-humble -- check-gpu.sh
```

Run this from a terminal *inside* the host's desktop session (not a bare SSH session with no display
available) — the script exits with an error if it can't find an X11/XWayland socket for `$DISPLAY`.

## Verifying the GPU is actually being used

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
Confirm a GPU process actually shows up — the more reliable of the two checks, since it reflects what
the driver itself sees rather than just what the app reports.

## GPU Load Test (gpu_pointcloud_test)

A second, standalone image specifically for generating a controllable, sustained GPU load — useful
for the "does GPU rendering interfere with an RT control loop" question from `part5/rt`: run this
alongside `cyclictest` on the isolated core instead of just watching RViz sit idle, to see whether
real GPU/rendering activity on the housekeeping cores actually disturbs RT timing.

It wraps [`../gpu_pointcloud_test/`](../gpu_pointcloud_test/) (see that package's own README for full
details), which loads a point cloud (synthetic by default), applies a deliberately GPU-heavy iterative
warp (CuPy, falling back to NumPy automatically if no GPU/CuPy is available), and republishes it as a
high-frequency `PointCloud2` for RViz. `gpu_iterations`, `num_points`, and `neighbor_sample` control
how heavy the load is.

Built **standalone from scratch** (`Containerfile.pointcloud`), not layered on this directory's main
`Containerfile`: `gpu_pointcloud_test` only needs `ros-humble-ros-base` + `rviz2`, not the full
`ros-humble-desktop` metapackage — per that package's own README, `rviz2` isn't in `ros-base`, only in
`desktop`, and nothing else in `desktop` (`rqt`, demo nodes, `turtlesim`, teleop packages, ...) is
relevant here. Same X11/GPU passthrough rationale as the rest of this directory applies unchanged.

### Build

Build context is the **parent** directory (`part5/`), not this one, since it needs to reach the
sibling `gpu_pointcloud_test/` package:

```bash
cd /path/to/part5
podman build -t quay.io/luferrar/part5:rviz-pointcloud -f rviz-tests/Containerfile.pointcloud .
```

### Run

Same launcher as the base image — no new script needed, `run-rviz-test.sh` already generalizes over
image/command:

```bash
cd rviz-tests
./run-rviz-test.sh quay.io/luferrar/part5:rviz-pointcloud                     # node + RViz together
./run-rviz-test.sh quay.io/luferrar/part5:rviz-pointcloud -- check-gpu.sh     # renderer check
./run-rviz-test.sh quay.io/luferrar/part5:rviz-pointcloud -- \
    ros2 launch gpu_pointcloud_test gpu_pointcloud.launch.py gpu_iterations:=800 num_points:=2000000
```

Watch the terminal at startup for `Compute backend: cupy (GPU)` — if it says `numpy (CPU)` instead,
CuPy didn't find the GPU; check with `nvidia-smi` the same way as the [GPU verification](#verifying-the-gpu-is-actually-being-used)
above.

## Test Results: Heavy Load Crash, Tuned Load Clean for ~2h53m

Findings from testing on `lenovo-p330` (Quadro P620), running RT kernel
`6.12.0-211.51.1.el10_2.x86_64+rt` for both runs below. Same image, same host, same kernel for both; only the launch parameters
differed. Numbers below are from the actual `journalctl` history (~3 hours available), not just a
short sample.

### Heavy defaults (`num_points=1000000 gpu_iterations=400 neighbor_sample=3000`): crashed after 20 frames

Ran cleanly for 20 frames (avg 3741ms/frame, min 3053ms, max 5035ms — the max is the first frame,
almost certainly inflated by CuPy's one-time NVRTC kernel-compile-on-first-use cost rather than
reflecting steady-state compute; consistent with the package's own "~<2Hz on mid-range GPUs"
expectation, proportionally worse here since the P620 is well below mid-range), then crashed on the
21st cycle. The Python side raised:

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

### Tuned defaults (`num_points=200000 gpu_iterations=80 neighbor_sample=800`, the new image default): clean for 2h53m straight

4642 frames over a single continuous run — not just a short sample, the full session from launch to
the point it was manually stopped. Steady-state (excluding the first frame, which shows the same
one-time JIT-compile inflation as the heavy run's first frame: 2316ms vs. everything else): **avg
139ms/frame, min 114ms, max 142ms** — tight, consistent, no jitter of note. `systemd` confirms the
full span: `Consumed 2h 53min 18.707s CPU time`. Zero Xid errors anywhere in that entire window.

<!--It ended via a manual Ctrl+C, not a crash — `journalctl` shows `user interrupted with ctrl-c (SIGINT)`
right before shutdown. The shutdown does log a Python exception
(`RCLError: failed to shutdown: rcl_shutdown already called on the given context`), which made the
launch wrapper report `process has died, exit code 1` — worth knowing about so it doesn't look like a
second crash if you go looking at these logs later, but it's a harmless double-shutdown race between
`rclpy`'s own cleanup and the SIGINT handler, unrelated to GPU/compute correctness, and it only appears
at the very end after 2h53m of otherwise clean operation.-->

### Takeaway

The tuned defaults (now the image's default `CMD`) ran clean for nearly 3 hours straight on this
hardware and this RT kernel, versus the heavy defaults faulting after 20 frames (~75 seconds of actual
compute). That's a solid basis for trusting the tuned settings for sustained use here.

## Test Results: RPM-Based Image (`rviz-pointcloud-rpm`), Tuned Load Crashed After ~4.5min

Same GPU load test as above, same tuned parameters (`num_points=200000 gpu_iterations=80
neighbor_sample=800`), same host, same RT kernel (`6.12.0-211.51.1.el10_2.x86_64+rt`) — but on
`Containerfile.pointcloud-rpm` instead of the conda-based `Containerfile.pointcloud`. Reported plainly
because the result is meaningfully different, not just a repeat confirmation.

GPU acceleration is genuinely working here too: `Compute backend: cupy (GPU)` at startup, a first-frame
JIT-compile warmup (2174ms, the same one-time-cost pattern seen on the conda image), then a steady
state around **176ms/frame** — about 27% slower per-frame compute than the conda image's 139ms at the
identical parameters. Not the CUDA toolkit version: `cupy.show_config()` on both images shows an
identical CUDA Build/NVRTC version (12090 / 12.9) — the difference here is CuPy's own version (13.6.0
here vs. 14.2.0 on conda/Fedora-Lyrical, a consequence of this image's Python 3.9 being too old for
newer CuPy wheels), or something else about this environment entirely; not isolated further.

It crashed after about 4.5 minutes (~1500 frames), not the 2h53m (4600+ frames) the conda-based image
ran clean at these same settings. Same fault signature as the earlier heavy-load crash on the conda
image:

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
conda image (see the Fedora/Lyrical Test Results section below) shows an *identical* CUDA
Build/NVRTC version (12090 / 12.9) on both — so a less-tested pip-installed CUDA toolkit component
version is not the explanation, at least not on its own. What remains unconfirmed: CuPy's own version
(13.6.0 here, older, forced by this image's Python 3.9), and whether the RT kernel is involved at all,
which remains exactly as untested as it was for the conda-based crash — both fired on the same kernel,
no standard-kernel comparison has been run.

**Takeaway:** this image gets real GPU-accelerated compute working, but on this one comparison it's
noticeably less stable under sustained load than the conda-based image — worth further investigation
before relying on it the way the conda image's tuned defaults are now trusted. Good evidence the
architecture works end to end; not yet evidence it's production-ready.

## Test Results: RPM-Based Image (`rviz-pointcloud-lyrical`), Tuned Load Crashed After ~1m54s

Same GPU load test, same tuned parameters (`num_points=200000 gpu_iterations=80 neighbor_sample=800`),
same host, same RT kernel (`6.12.0-211.51.1.el10_2.x86_64+rt`) — this time on
`Containerfile.pointcloud-lyrical`, layered on the Fedora + official Copr RPMs image (`rviz-lyrical`)
instead of Kilted/CentOS Stream 9. Launched via `run-gpu-pointcloud-lyrical.sh` rather than `ros2
launch`, since this Copr has no `ros2launch` package — see the "Fedora + Lyrical" section above and the
Containerfile's own comments for why.

GPU acceleration was genuinely working: `cupy (GPU)` backend at startup, a first-frame JIT-compile
warmup (2352ms, the same one-time-cost pattern seen on the other two images), then a tight, clean steady
state — **avg 136.8ms/frame, min 133.4ms, max 138.0ms** over the 53 frames it managed before crashing.
That's actually the *best* per-frame number of the three images so far (vs. the conda image's 139ms and
the Kilted RPM image's 176ms at the identical parameters) — this crash is not a slow/struggling-GPU
story, the compute itself was clean and fast right up to the fault.

It crashed after roughly **114 seconds** (container started 17:46:22, last successful frame and the
kernel fault both logged at 17:48:16) — noticeably faster than the Kilted RPM image's ~4.5 minutes at
these same settings, and nowhere near the conda image's clean 2h53m run. Identical fault signature to
both earlier crashes:

```
NVRM: Xid (PCI:0000:01:00): 13, Graphics SM Warp Exception on (GPC 0, TPC 0): Out Of Range Address
NVRM: Xid (PCI:0000:01:00): 13, Graphics Exception: ESR 0x504648=0x11d000e 0x504650=0x20 0x504644=0xd3eff2 0x50464c=0x17f
NVRM: Xid (PCI:0000:01:00): 43, pid=70045, name=gpu_pointcloud_, channel 0x00000028
```

Same recovery behavior too — Xid 43 reset just that process's channel; `nvidia-smi` was healthy
immediately after (565MiB, 6% util, normal temp), and the container itself kept running (only the
backgrounded compute node process died — `rviz2`, running separately in the foreground, was unaffected
and stayed up). A contained fault, not a GPU hang, consistent with both prior crashes.

**Still not root-caused, but two specific guesses have been checked and ruled out.** This is now the
*second* RPM-based image to crash under tuned load within minutes, while the conda-forge/RoboStack image
ran the identical tuned settings clean for nearly 3 hours. Two follow-up checks, both read-only (no
rebuilding, no bisecting):

- **CUDA toolkit version skew.** `cupy.show_config()` run on all three images shows an *identical* CUDA
  Build/NVRTC version (12090 / 12.9) across conda, Kilted, and Fedora/Lyrical — and the conda and
  Fedora/Lyrical images even share the exact same CuPy version (14.2.0). So the pip-installed CUDA
  toolkit being a "less-tested" or different version than conda-forge's own build is directly
  contradicted by the data, not just unconfirmed.
- **Host desktop/GPU contention.** Checked `journalctl` in a window around all three Xid faults (this
  crash, the Kilted crash, and the original conda heavy-load crash) for `gnome-shell`,
  `gnome-remote-desktop`, `Xwayland`, or `mutter` activity that might indicate the desktop compositor
  competing for the P620's 2GB VRAM at the moment of each fault — nothing showed up in any of the three
  windows.
- One incidental finding along the way: all three crashes and the 2h53m clean conda run happened within
  the *same* host boot session (uptime since 11:51:49 that day) — ruling out "the host was in a bad
  post-reboot state" as well, since the long clean run and both crashes share the same uptime.

What's left unconfirmed, and would require actually building/running something new to check (the point
where this stops being a bounded, read-only investigation): whether Fedora 44's much newer Python
(3.14.7, vs. conda's 3.12.14) or glibc (2.43 vs. 2.39) plays any role, and the RT-kernel question, which
remains exactly as untested as before — all three crashes and the one long clean run happened on the
same kernel.

**Takeaway:** three images, two dependency-installation paths, and now two crashes with the identical
fault signature on the pip/RPM path — both notably faster than this same path's own first attempt on
Kilted. Whatever the actual cause turns out to be, it's reproducible enough now to be worth isolating
before trusting either RPM-based image for sustained GPU load, even though both demonstrably get real,
fast GPU compute working right up to the moment they fault.

## Conclusion

Three ROS2 distribution mechanisms were built and tested end to end on this host: RoboStack/conda-forge
(`rviz-humble`), official RPMs on CentOS Stream 9 (`rviz-kilted`), and Fedora + the robotics-sig's own
Copr (`rviz-lyrical`). All three get genuine GPU-accelerated `rviz2` rendering and, via
`gpu_pointcloud_test`, genuine GPU-accelerated compute — this was never in question. What separates them
is what happened under sustained load:

| Image | Basis | Per-frame (tuned) | Sustained-load result |
|---|---|---|---|
| `rviz-pointcloud` | conda-forge/RoboStack | 139ms | Clean for 2h53m (4600+ frames), zero faults |
| `rviz-pointcloud-rpm` | Kilted RPMs, CentOS Stream 9 | 176ms | Xid 13/43 crash at ~4.5min |
| `rviz-pointcloud-lyrical` | Fedora + Copr RPMs | 137ms | Xid 13/43 crash at ~114s |

The RPM-based images are the better fit on paper — smaller (Fedora/Lyrical: 2.5GB vs. RoboStack's
14GB), no conda/micromamba layer, and Fedora/Lyrical in particular needs no EPEL/CodeReady Builder
wrangling at all. But "on paper" doesn't hold once `gpu_pointcloud_test` actually drives the GPU hard:
both RPM images faulted with the identical illegal-memory-access signature within minutes, while the
conda image is the only one of the three with any evidence of standing up to sustained load at all.

**For sustained/production-shaped GPU compute workloads on this hardware, use the conda-forge/RoboStack
image (`Containerfile`, `rviz-humble`) and its `gpu_pointcloud_test` variant
(`Containerfile.pointcloud`).** It's the only one of the three with hours of clean runtime behind it —
everything else here is evidence the other two *can* work, not that they reliably do.

That recommendation is scoped to the compute-heavy case specifically, not to `rviz2` visualization on
its own — nothing here suggests plain `rviz2` (no `gpu_pointcloud_test` alongside it) is unstable on any
of the three images; all the observed crashes happened inside `gpu_pointcloud_test`'s CuPy compute path,
never from `rviz2` rendering by itself. For a lightweight, short-lived, or purely-visualization use case
where image size and RHEL-friendliness matter more than proven long-run stability, the Fedora/Lyrical
image is a reasonable, much cleaner alternative — just not yet a validated one for anything that leans
on the GPU hard for an extended period.

The root cause behind the RPM-path crashes is still open (see both Test Results sections above for what
was and wasn't ruled out) — this conclusion is a practical recommendation based on the evidence gathered
so far, not a final diagnosis.

## Files

- **Containerfile**: UBI10 base + RoboStack (`ros-humble-desktop`, includes `rviz2`) via micromamba
- **entrypoint.sh**: activates the `ros_env` micromamba environment, then execs the given command
- **check-gpu.sh**: prints the EGL/GLX renderer string to confirm NVIDIA vs. software rendering
- **run-rviz-test.sh**: host-side launcher — mounts the X11/XWayland socket, passes the GPU via CDI,
  runs as the host's own UID (the image has no fixed user; `/etc/passwd` is bind-mounted read-only so
  the arbitrary UID still resolves to a name)
- **Containerfile.pointcloud**: standalone (`ros-base` + `rviz2`, not layered on `Containerfile`) image
  for [`../gpu_pointcloud_test/`](../gpu_pointcloud_test/) — see [above](#gpu-load-test-gpu_pointcloud_test)
- **entrypoint-pointcloud.sh**: same activation pattern as `entrypoint.sh`, plus overlaying the
  `gpu_pointcloud_test` colcon workspace
- **Containerfile.ros2-rpm**: the RPM-based alternative (`rviz-kilted`) — see
  [above](#rpm-based-alternative-kilted)
- **entrypoint-kilted.sh**: sources `/opt/ros/kilted/setup.bash`, then execs the given command
- **Containerfile.pointcloud-rpm**: `gpu_pointcloud_test` layered on `rviz-kilted` instead of the
  conda-based image — see [Test Results](#test-results-rpm-based-image-rviz-pointcloud-rpm-tuned-load-crashed-after-45min)
  above
- **entrypoint-pointcloud-rpm.sh**: same pattern as `entrypoint-kilted.sh`, plus overlaying the
  `gpu_pointcloud_test` colcon workspace and the `nvidia-*` wheel library-path discovery it needs
- **Containerfile.fedora-lyrical**: the Fedora + official Copr RPMs alternative (`rviz-lyrical`) — see
  [above](#fedora--lyrical-official-copr-rpms)
- **entrypoint-lyrical.sh**: sources `/opt/ros/lyrical/setup.bash`, then execs the given command
- **Containerfile.pointcloud-lyrical**: `gpu_pointcloud_test` layered on `rviz-lyrical` — see
  [Test Results](#test-results-rpm-based-image-rviz-pointcloud-lyrical-tuned-load-crashed-after-1m54s)
  above
- **entrypoint-pointcloud-lyrical.sh**: same pattern as `entrypoint-lyrical.sh`, plus overlaying the
  `gpu_pointcloud_test` colcon workspace and the `nvidia-*` wheel library-path discovery it needs
- **run-gpu-pointcloud-lyrical.sh**: drives the node + `rviz2` directly via `ros2 run`, since this
  Copr has no `ros2launch` package to provide the `ros2 launch` verb `Containerfile.pointcloud`/
  `Containerfile.pointcloud-rpm` rely on — see the Containerfile's own comments
- **nvidia-cdi-setup.md**: how to install `nvidia-container-toolkit` and generate the CDI spec this
  container's GPU passthrough depends on
- **lenovo-p330-nvidia-fix.md**: how the NVIDIA driver itself was gotten working on this host