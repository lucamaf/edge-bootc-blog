# KUKA Driver Compatibility Test

Tests [kroshu/examples](https://github.com/kroshu/examples)' `moveit_example`, KUKA's own MoveIt 2
integration and containerized demo for the iiQKA driver, running on RHEL10 + real-time kernel, on `lenovo-p330`.

## KUKA validation process

No physical KUKA robot is attached. This runs against [`kuka_mock_hardware_interface`](https://github.com/kroshu/kuka_robot_descriptions/tree/master/kuka_mock_hardware_interface), a mock `ros2_control` hardware plugin KUKA ships specifically for this purpose (selected via `mode:=mock` in the robot's URDF).

- The actual driver source (`kuka_iiqka_eac_driver`, `kuka_drivers_core`, the custom KUKA `ros2_control`
  controllers) builds cleanly against ROS2 Jazzy, confirmed on Ubuntu 24.04/MoveIt2's official
  image
- The RT-relevant control loop code — `control_node`'s `cpu_affinity`/`thread_priority`/`lock_memory`
  (`mlockall`) options runs without error
- MoveIt 2 planning, `ros2_control` controller spawning/activation, and the driver's lifecycle-node
  orchestration all work together on this host

This does **not** validate real robot communication, the RSI/EAC network protocol, actual motion
execution.

## Two image test

This test is built two ways:

- **`Containerfile.kuka-moveit-example`** (`kuka-moveit-example`): CentOS Stream 10 with RoboStack/conda,
  built standalone from scratch.   
- **`Containerfile.kuka-moveit2`** (`kuka-moveit2`), layered directly on MoveIt2's own official Docker
  image (`moveit/moveit2:jazzy-release`, Ubuntu 24.04), the same approach
  `../rviz-tests/Containerfile.rviz-pointcloud-moveit2` used for the GPU pointcloud test.

<!--
## Why CentOS Stream 10, not UBI10/rviz-humble

This was originally layered on `../rviz-tests`' `rviz-humble` image (UBI10-based), but that hit a real
dead end: `kuka_external_control_sdk` needs `grpc++`/protobuf, and neither conda-forge's `grpc-cpp`
(capped at a version needing `libprotobuf <3.22`, incompatible with `robostack-humble`'s own pin to
`libprotobuf` 5.x/6.x) nor RHEL10's system `grpc-devel` (needs `protobuf-devel`/`protobuf-compiler`,
which live behind the *full* RHEL10 CodeReady Builder repo — UBI10's own `crb enable` enables a
different, narrower repo that doesn't carry them, confirmed by actually running it inside the container)
could satisfy it. Full reasoning and the exact commands that confirmed each dead end are in the
Containerfile's own header comment.

Same class of problem this project already hit once for the Kilted image (UBI9's CodeReady Builder not
matching what the CentOS Stream/RHEL-proper install guide expected) — same fix: CentOS Stream instead of
UBI, where CRB is a normal, unrestricted repo. This is a **standalone** image (CentOS Stream 10 +
RoboStack, redoing the X11/GPU/ROS2 setup `rviz-humble` normally provides) rather than layered on
`rviz-humble`.
--> 

### MoveIt2/Ubuntu test

Simpler image build thanks to:  

- **No CRB/protobuf-version fight at all.** `libgrpc++-dev`, `protobuf-compiler-grpc`, `libtinyxml2-dev`,
  and `libcap-dev` are normal, always-available Ubuntu 24.04 apt packages.  
- **No symlink needed for `grpc_cpp_plugin`.** `kuka_external_control_sdk`'s CMakeLists.txt hardcodes
  the plugin path as `/usr/bin/grpc_cpp_plugin`, Debian's `protobuf-compiler-grpc` package installs it at exactly that path.
- **No `LIBRARY_PATH`/`CMAKE_INSTALL_RPATH` workaround needed.** ROS2, the compiler, and everything this Containerfile builds from source are all part of the same apt-based system.
- **Most of the needed ROS2 packages are already installed.** `moveit/moveit2:jazzy-release`'s own
  `ros-jazzy-moveit-*` install already transitively pulls in `controller-manager`, `moveit-visual-tools`,
  `ros2launch`, and `joint-state-publisher-gui` (confirmed via `dpkg -l` against the real image). Only
  `ros2-control`/`ros2-controllers`/`ros2-controllers-test-nodes` needed adding explicitly.

## Kuka Source layout

Four repos, built together as one colcon workspace:

| Repo | Branch | Why |
|---|---|---|
| `kroshu/kuka_drivers` | `master` (= Jazzy) | the driver itself, matches the ROS2 distro choice above |
| `kroshu/kuka_robot_descriptions` | `master` | URDF/moveit-configs/mock hardware plugin distro-agnostic, no per-ROS2-version branch exists |
| `kroshu/kuka-external-control-sdk` | `master` | non-ROS SDK wrapped for colcon also distro-agnostic |
| `kroshu/examples` | `master` (= Jazzy) | `moveit_example` itself |

`colcon build --packages-up-to moveit_example` keeps the build scoped to what the iiQKA driver actually
needs and nothing else in the repos.

## Build Kuka example

```bash
cd part5/kuka
# CentOS Stream 10 + RoboStack
podman build -t quay.io/luferrar/part5:kuka-moveit-example -f Containerfile.kuka-moveit-example .
# MoveIt2/Ubuntu
podman build -t quay.io/luferrar/part5:kuka-moveit2 -f Containerfile.kuka-moveit2 .
```

## Run Kuka example

Same X11/GPU passthrough launcher as `rviz-tests` for either image:  

```bash
cd ../rviz-tests
./run-rviz-test.sh quay.io/luferrar/part5:kuka-moveit-example
```

This brings up the mock driver, `ros2_control` controllers, `move_group`, and RViz together.  

To actually exercise motion planning through the stack, run one of `moveit_example`'s own planning nodes
against the already-running container:  

```bash
CID=$(podman ps --filter "ancestor=quay.io/luferrar/part5:kuka-moveit-example" --format "{{.ID}}")
podman exec -it "$CID" bash -c '
  eval "$(micromamba shell hook -s bash)"
  micromamba activate ros_env
  source /opt/kuka_ws/install/local_setup.bash
  ros2 run moveit_example moveit_basic_planners_example'
```

For the MoveIt2/Ubuntu image, the `exec` activation is a plain `source`:

```bash
CID=$(podman ps --filter "ancestor=quay.io/luferrar/part5:kuka-moveit2" --format "{{.ID}}")
podman exec -it "$CID" bash -c '
  source /opt/ros/jazzy/setup.bash
  source /opt/kuka_ws/install/local_setup.bash
  ros2 run moveit_example moveit_basic_planners_example'
```

Other available example nodes (same package, swap the executable name): `moveit_collision_avoidance_example`,
`moveit_constrained_planning_example`, `moveit_depalletizing_example`.  

Here is the video recording of the test with the `kuka-moveit2` image:  
[![Kuka drivers](http://img.youtube.com/vi/fsdSST87yjI/0.jpg)](http://www.youtube.com/watch?v=fsdSST87yjI "Kuka drivers test")  

## Testing RT Performance

The default `CMD` (`moveit_planning_fake_hardware.launch.py`) is good for a quick "does it plan and
move" check, but applies **no RT tuning at all** — it starts the control loop via the plain
`ros2_control_node` executable (from `controller_manager`), not KUKA's own `control_node` (from
`kuka_drivers_core`). Launch chains: `moveit_planning_fake_hardware
.launch.py` → `kuka_resources`' `fake_hardware_planning_template.launch.py` → plain `ros2_control_node`,
with no `cpu_affinity`/`thread_priority`/`lock_memory` parameters anywhere in that chain. The RT-tuned
entry point is a different launch file: `kuka_iiqka_eac_driver`'s own `startup.launch.py`, which is
what `moveit_example`'s `moveit_planning_example.launch.py` actually uses, and is the one that runs
`kuka_drivers_core/src/control_node.cpp`'s `SCHED_FIFO`/`pthread_setaffinity_np`/`mlockall` setup and
exposes `rt_core`, `rt_prio`, `non_rt_cores`, `lock_memory`, `roundtrip_time` as launch arguments.

To exercise the RT-tuned path, launch the driver and MoveIt separately instead of using the default
`CMD` (`moveit_planning_example.launch.py` itself doesn't forward these args, so passing them on that
launch file's command line would just fail). Only the *first* of these is a `run-rviz-test.sh` invocation
— it starts the container. The other two must be `podman exec` into that same container, not separate
`run-rviz-test.sh` calls: `run-rviz-test.sh` doesn't set `--network host`, so each `podman run` gets its
own isolated network namespace, and separate invocations can never discover each other over ROS2 DDS no
matter what command each one runs (confirmed directly — a second `run-rviz-test.sh` call here just times
out waiting for `robot_description` and crashes on shutdown; see the "Run" section above for the same
issue in the simpler mock-hardware case).

```bash
# Terminal 1 - starts the container; RT-tuned control loop against the mock hardware plugin
./run-rviz-test.sh quay.io/luferrar/part5:kuka-moveit-example -- \
    ros2 launch kuka_iiqka_eac_driver startup.launch.py \
    mode:=mock rt_core:=1 non_rt_cores:=2,3 rt_prio:=80 roundtrip_time:=1000
```

```bash
# Get the container ID once terminal 1's controllers are active, then use it for terminals 2 and 3
CID=$(podman ps --filter "ancestor=quay.io/luferrar/part5:kuka-moveit-example" --format "{{.ID}}")

# Terminal 2 - MoveIt + RViz, exec'd into the same container
podman exec -it "$CID" bash -c '
  eval "$(micromamba shell hook -s bash)"; micromamba activate ros_env
  source /opt/kuka_ws/install/local_setup.bash
  ros2 launch kuka_lbr_iisy_moveit_config moveit_server.launch.py robot_model:=lbr_iisy3_r760
'

# Terminal 3 - generate actual motion/load through the loop, same container again
podman exec -it "$CID" bash -c '
  eval "$(micromamba shell hook -s bash)"; micromamba activate ros_env
  source /opt/kuka_ws/install/local_setup.bash
  ros2 run moveit_example moveit_basic_planners_example
'
```

For the MoveIt2/Ubuntu image, use `quay.io/luferrar/part5:kuka-moveit2` throughout and drop the
`micromamba` lines from terminals 2 and 3 (same plain `source` swap as the "Run" section above).

Adjust `rt_core`/`non_rt_cores` to match whichever cores are actually isolated on the host (see
`../rt/README.md`'s kargs section), check `cat /proc/cmdline | grep isolcpus` on the host before picking values.

### What to check

**1. RT setup actually took effect, not just requested.** `control_node.cpp` logs on success:
```
CPU affinity set to core %d
Control loop priority was set to %d
Memory of control loop locked successfully to disable paging
```
or explicit `RCLCPP_ERROR`s if `sched_setscheduler`/`mlockall`/`pthread_setaffinity_np` failed (e.g.
missing `CAP_SYS_NICE`/`CAP_IPC_LOCK` in the container). Check terminal 1's startup log for these before
trusting anything else — if RT setup silently failed, the rest of this is measuring nothing.

**2. The driver's own cycle-overrun detector.** `kuka_mock_hardware_interface::write()` checks every
cycle against `roundtrip_time` and logs a WARN if it's missed:
```
Cycle exceeded allowed round-trip time
```
(`kuka_mock_hardware_interface/src/hardware_interface.cpp`, confirmed directly against the source). Set
`roundtrip_time` tighter than the driver's own default (2500μs) to make this a meaningful check — the
`1000` above is a starting point, not a validated threshold for this hardware. Run a long soak (matching
`../rt-tests`' methodology: hours, not seconds) with `moveit_basic_planners_example` cycling motion
through terminal 3, and grep terminal 1's output/`journalctl` for the warning over that whole window
rather than trusting a short sample.

**3. (Optional) broader system RT health.** Run `../rt-tests/run-cyclictest.sh` on a **different**
isolated core than `rt_core` (pinning both to the same core would just create artificial contention, not
measure anything meaningful) to confirm nothing else on the host degraded while the KUKA control loop
was running — the same "does load elsewhere disturb RT timing" check already used for the GPU pointcloud
tests in `../rviz-tests`, with the KUKA control loop as the load source this time instead of GPU compute.

Not yet done: an actual soak run with real numbers. Everything above is the *how*, verified against the
actual driver/launch source — it hasn't been run yet, so there's no equivalent "Test Results" section
here the way `../rt/README.md` and `../rviz-tests/README.md` have for their own soak tests.

## Files

- **Containerfile.kuka-moveit-example**: standalone (CentOS Stream 10 + RoboStack, see "Why CentOS
  Stream 10" above); sets up X11/GPU passthrough and ROS2/MoveIt 2/`ros2_control` the same way
  `../rviz-tests`' images do, then builds the four KUKA source repos in `/opt/kuka_ws`
- **entrypoint.sh**: activates the `ros_env` micromamba environment, sources the `kuka_ws` workspace
  overlay, then execs the given command
- **Containerfile.kuka-moveit2**: layered directly on `moveit/moveit2:jazzy-release` (see "Why also
  MoveIt2/Ubuntu" above); builds the same four KUKA source repos in `/opt/kuka_ws`  
- **entrypoint-moveit2.sh**: sources `/opt/ros/jazzy/setup.bash` and the `kuka_ws` workspace overlay,
  then execs the given command
