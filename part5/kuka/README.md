# KUKA Driver Compatibility Test (moveit_example)

Tests [kroshu/examples](https://github.com/kroshu/examples)' `moveit_example` — KUKA's own MoveIt 2
integration demo for the iiQKA driver — against this project's RHEL10 + real-time kernel setup, on
`lenovo-p330` (currently running `6.12.0-211.51.1.el10_2.x86_64+rt`).

## What this validates, and what it doesn't

No real KUKA robot is attached. This runs against
[`kuka_mock_hardware_interface`](https://github.com/kroshu/kuka_robot_descriptions/tree/master/kuka_mock_hardware_interface) —
a mock `ros2_control` hardware plugin KUKA ships specifically for this purpose (selected via `mode:=mock`
in the robot's URDF), not the standard `mock_components/GenericSystem`, and not Gazebo.

That means this **does** validate:
- The actual driver source (`kuka_iiqka_eac_driver`, `kuka_drivers_core`, the custom KUKA `ros2_control`
  controllers) builds cleanly on RHEL10/ROS2 Humble via RoboStack
- The RT-relevant control loop code — `control_node`'s `cpu_affinity`/`thread_priority`/`lock_memory`
  (`mlockall`) options — runs without error
- MoveIt 2 planning, `ros2_control` controller spawning/activation, and the driver's lifecycle-node
  orchestration all work together on this host

This does **not** validate real robot communication — the RSI/EAC network protocol, actual motion
execution, or anything specific to talking to a physical LBR iisy over the network. It's a build/runtime
compatibility check for the ROS2 stack, not a robot-communication test.

## Why Humble, not the upstream-recommended Jazzy

`kroshu/kuka_drivers`' own README recommends its `master` branch (currently ROS2 Jazzy) over its
`humble` branch. This test uses Humble instead — the most-proven RHEL10 ROS2 path in this project so
far. Humble keeps this test to one new variable at a time. `master`/Jazzy is worth revisiting later if
there's a specific reason to.

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
UBI, where CRB is a normal, unrestricted repo. This is now a **standalone** image (CentOS Stream 10 +
RoboStack, redoing the X11/GPU/ROS2 setup `rviz-humble` normally provides) rather than layered on
`rviz-humble`.

## Source layout

Four repos, three different branches, built together as one colcon workspace (see the Containerfile's
own comments for the full reasoning per repo):

| Repo | Branch | Why |
|---|---|---|
| `kroshu/kuka_drivers` | `humble` | the driver itself, matches the ROS2 distro choice above |
| `kroshu/kuka_robot_descriptions` | `master` | URDF/moveit-configs/mock hardware plugin — distro-agnostic, no per-ROS2-version branch exists |
| `kroshu/kuka-external-control-sdk` | `master` | non-ROS SDK wrapped for colcon — also distro-agnostic |
| `kroshu/examples` | `humble` | `moveit_example` itself |

`colcon build --packages-up-to moveit_example` keeps the build scoped to what the iiQKA driver actually
needs — `kuka_drivers` also contains RSI/FRI/KSS drivers for KUKA's other (industrial/LBR iiwa) product
lines that aren't relevant here and would pull in their own dependencies otherwise.

## Build

```bash
cd part5/kuka
podman build -t quay.io/luferrar/part5:kuka-moveit-example -f Containerfile.kuka-moveit-example .
```

## Run

Same X11/GPU passthrough launcher as `rviz-tests` — no new script needed:

```bash
cd ../rviz-tests
./run-rviz-test.sh quay.io/luferrar/part5:kuka-moveit-example
```

This brings up the mock driver, `ros2_control` controllers, `move_group`, and RViz together
(`moveit_planning_fake_hardware.launch.py`, see the Containerfile for why this entry point is used
instead of `moveit_example`'s own launch file, which doesn't wire up mock mode on its own).

To actually exercise motion planning through the stack, run one of `moveit_example`'s own planning nodes
in a second terminal against the already-running container:

```bash
./run-rviz-test.sh quay.io/luferrar/part5:kuka-moveit-example -- \
    ros2 run moveit_example moveit_basic_planners_example
```

Other available example nodes (same package, swap the executable name): `moveit_collision_avoidance_example`,
`moveit_constrained_planning_example`, `moveit_depalletizing_example`.

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
launch file's command line would just fail):

```bash
# Terminal 1 - RT-tuned control loop against the mock hardware plugin
./run-rviz-test.sh quay.io/luferrar/part5:kuka-moveit-example -- \
    ros2 launch kuka_iiqka_eac_driver startup.launch.py \
    mode:=mock rt_core:=1 non_rt_cores:=2,3 rt_prio:=80 roundtrip_time:=1000

# Terminal 2 - MoveIt + RViz, once terminal 1's controllers are active
./run-rviz-test.sh quay.io/luferrar/part5:kuka-moveit-example -- \
    ros2 launch kuka_lbr_iisy_moveit_config moveit_server.launch.py robot_model:=lbr_iisy3_r760

# Terminal 3 - generate actual motion/load through the loop
./run-rviz-test.sh quay.io/luferrar/part5:kuka-moveit-example -- \
    ros2 run moveit_example moveit_basic_planners_example
```

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
