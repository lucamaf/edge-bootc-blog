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
`humble` branch. This test uses Humble instead, layered on this project's `rviz-humble` image
(`../rviz-tests/Containerfile.rviz-humble`) — the most-proven RHEL10 ROS2 path in this project so far. Humble keeps this test to one new variable at a time. `master`/Jazzy is worth revisiting later if there's a specific reason to.

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
(`moveit_planning_fake_hardware.launch.py` — see the Containerfile for why this entry point is used
instead of `moveit_example`'s own launch file, which doesn't wire up mock mode on its own).

To actually exercise motion planning through the stack, run one of `moveit_example`'s own planning nodes
in a second terminal against the already-running container:

```bash
./run-rviz-test.sh quay.io/luferrar/part5:kuka-moveit-example -- \
    ros2 run moveit_example moveit_basic_planners_example
```

Other available example nodes (same package, swap the executable name): `moveit_collision_avoidance_example`,
`moveit_constrained_planning_example`, `moveit_depalletizing_example`.

## Files

- **Containerfile.kuka-moveit-example**: layered on `../rviz-tests`' `rviz-humble` image; adds MoveIt
  2/`ros2_control` conda packages, then builds the four KUKA source repos in `/opt/kuka_ws`
- **entrypoint.sh**: activates the `ros_env` micromamba environment, sources the `kuka_ws` workspace
  overlay, then execs the given command
