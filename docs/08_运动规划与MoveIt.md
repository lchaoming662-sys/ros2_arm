# 第 08 章 运动规划与 MoveIt 2

> 本章把你的机械臂从"听命令才动"升级为"自己算路径"。这一章用**配置向导**而不是手写，
> 但你必须**看懂向导每一步在配什么**，否则出了问题完全无从下手。

---

## 8.1 学习目标

读完并做完本章你应该能够：
1. 说出 MoveIt 的 5 个核心组件及其分工；
2. 独立用 MoveIt Setup Assistant 生成一个可用的配置包，并解释每一步的作用；
3. 说明 SRDF 与 URDF 的分工；
4. 在 RViz 里完成一次"规划 + 执行"，并让 Gazebo 里的机械臂动起来；
5. 诊断最常见的"规划失败"的三类原因。

---

## 8.2 重点内容（一）：MoveIt 是什么、组件有哪些

MoveIt 2 是 ROS 2 的机械臂运动规划框架。**它不负责让关节转动**（那是第 06 章控制器的事），它只负责**算出"该怎么动"**。

| 组件 | 职责 | 本项目里的角色 |
|------|------|--------------|
| **move_group** | 总调度：接收目标 → 解 IK → 规划路径 → 交给控制器 | 主节点，读一个庞大的参数集 |
| **规划组（Planning Group）** | "把哪些关节当成一个整体来规划" | `arm`（3 个关节）、`gripper`（1 个关节） |
| **运动学求解器（Kinematics Plugin）** | 解逆运动学：末端位姿 → 关节角度 | `kdl_kinematics_plugin/KDLKinematicsPlugin` |
| **规划器（Planner）** | 在关节空间里找一条从 A 到 B 的可行路径 | `ompl`（默认） |
| **控制器管理器（Controller Manager）** | 把算好的轨迹交给 ros2_control 的控制器执行 | `moveit_simple_controller_manager` |
| **RViz 插件（MotionPlanning）** | 可视化 + 交互式拖拽规划 | 你操作的那个面板 |

### 8.2.1 URDF 与 SRDF 的分工（重要概念）

| | URDF | SRDF |
|---|------|------|
| 描述 | 物理与运动学事实（连杆多长、关节怎么连） | **语义**：什么叫"一个组"、哪些姿态是预设姿态、谁是末端执行器 |
| 类比 | 汽车的工程图纸 | 汽车的使用说明（"这四个轮子组成底盘组"） |
| 谁生成 | 你自己写（第 05 章） | Setup Assistant 生成 |

**为什么需要 SRDF**：URDF 只知道"3 个关节串在一起"，不知道"这 3 个关节合起来叫手臂、末端是 link3、初始姿态叫 home"。这些**语义信息**由 SRDF 提供，MoveIt 靠它工作。

---

## 8.3 重点内容（二）：用 Setup Assistant 生成配置包（实操）

### 8.3.1 前置条件

- 第 05 章的模型文件已通过 RViz 验证；
- `ros-humble-moveit-setup-assistant` 已安装（第 02 章）；
- 环境已 source。

### 8.3.2 启动向导

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_arm/install/setup.bash
ros2 run moveit_setup_assistant moveit_setup_assistant
```

### 8.3.3 向导的每一步（照着做，并读懂"为什么"）

| 步骤 | 你要做什么 | 为什么 / 注意 |
|------|-----------|--------------|
| **1. Start** | 点 **Create New MoveIt Configuration Package**，Browse 选择模型文件：`~/ros2_arm/src/ros2_arm_description/urdf/ros2_arm.urdf.xacro`，然后 **Load Files** | 用"显示用"的纯 URDF 即可；右侧能看到机械臂就说明加载成功 |
| **2. Self-Collision** | 采样密度用默认（10000），点 **Generate Collision Matrix** | 它生成一张"哪些连杆之间会互撞"的表，用于规划时避开自碰撞。生成需要几秒 |
| **3. Virtual Joints** | **跳过** | 虚拟关节用于把机器人"挂"到世界坐标系。我们已经在 URDF 里用 `world`+固定关节解决了 |
| **4. Planning Groups** | ① **Add Group**：Name = `arm`，Kinematic Solver = `kdl_kinematics_plugin/KDLKinematicsPlugin`，选 **Kinematic Chain**，Base Link = `base_link`，Tip Link = `link3` → Save<br>② 再 **Add Group**：Name = `gripper`，Solver 选 **None**，选 **Joints**，勾选 `finger_right_joint`（主动指；左指由 mimic 自动跟随）→ Save | ① 用"运动链"方式会自动包含 base_joint / shoulder_joint / elbow_joint；② 夹爪只有一个移动关节，不需要 IK |
| **5. Robot Poses** | **Add Pose**：Name = `home`，所有滑块归 0 → Save | 预设姿态，RViz 里可一键回位。**姿态不能处于自碰撞状态**，全零最安全 |
| **6. End Effectors** | **Add End Effector**：Name = `hand`，Group = `gripper`，Parent Link = `link3` → Save | 告诉 MoveIt"手臂末端挂着这个夹爪"，抓取相关功能会用到 |
| **7. Passive Joints** | **跳过** | 被动关节（如随动连杆）本项目没有 |
| **8. ros2_control URDF** | 选 **None / Skip** | 我们第 06 章已经手写了 `ros2_arm.ros2_control.xacro`，不要让向导再插一份，否则会冲突 |
| **9. Simulation（Gazebo）** | **跳过** | 我们第 07 章已经有了自己的世界与仿真启动 |
| **10. MoveIt Controllers** | **Add Controller**：Name = `ros2_arm_controller`，Type = `FollowJointTrajectory`，勾选 base/shoulder/elbow → Save；再 **Add Controller**：Name = `finger_controller`，Type = `GripperCommand`，Joint = `finger_right_joint` → Save | **这一步最容易出错**：控制器名与关节名必须与你第 06 章 YAML 里的**逐字符一致**，否则规划成功但执行失败 |
| **11. ROS 2 Controllers** | 选 **Skip / 不生成** | 控制器配置我们已经在 `ros2_arm_bringup/config/ros2_arm_controllers.yaml` 里手写了，避免两份配置互盖 |
| **12. Authors** | 填你的名字和邮箱 | 生成 package.xml 要用 |
| **13. Configuration Files** | **Generate Package**，路径填 `~/ros2_arm/src/ros2_arm_moveit_config` | 生成完成后**退出向导**（先别 Launch） |

> **出错重来很方便**：向导生成的整个 `ros2_arm_moveit_config` 目录可以整体删掉重新生成，不会影响你手写的其他包。

### 8.3.4 生成后编译

```bash
cd ~/ros2_arm
colcon build --symlink-install
source install/setup.bash
ls src/ros2_arm_moveit_config/     # 应看到 config  launch  srdf 等目录
```

---

## 8.4 重点内容（三）：读懂生成的关键文件

向导生成了几十个文件，**只有 5 个需要你看懂**。

### 8.4.1 `config/ros2_arm.srdf`（在 `srdf/` 目录下，Humble 生成在 `config/`）

```xml
<robot name="ros2_arm">
  <!-- 规划组：arm（3 个转动关节） -->
  <group name="arm">
    <chain base_link="base_link" tip_link="link3"/>
  </group>

  <!-- 规划组：gripper（旋转夹爪，只列主动指） -->
  <group name="gripper">
    <joint name="finger_right_joint"/>
  </group>

  <!-- 预设姿态 -->
  <group_state name="home" group="arm">
    <joint name="base_joint" value="0"/>
    <joint name="shoulder_joint" value="0"/>
    <joint name="elbow_joint" value="0"/>
  </group_state>

  <!-- 末端执行器 -->
  <end_effector name="hand" parent_link="link3" group="gripper"/>

  <!-- 禁用碰撞检查的连杆对（向导自动生成一大堆，暂时不用管） -->
  <disable_collisions link1="base_link" link2="link1" reason="Adjacent"/>
  ...
</robot>
```

**读法**：`<group>` 就是你在向导里配的"规划组"，`<group_state>` 是预设姿态，`<disable_collisions>` 是"这两个连杆挨着，别检查它们撞不撞"。

### 8.4.2 `config/kinematics.yaml`（选运动学求解器）

```yaml
arm:
  kinematics_solver: kdl_kinematics_plugin/KDLKinematicsPlugin
  kinematics_solver_search_resolution: 0.005
  kinematics_solver_timeout: 0.005
  kinematics_solver_attempts: 3
```

**规划失败时第一个要改的地方**：把 `kinematics_solver_timeout` 从 0.005 调大到 0.05、`attempts` 调到 10，会显著提高 IK 成功率（代价是每次规划更慢）。

### 8.4.3 `config/joint_limits.yaml`（关节动力学限制）

```yaml
default_velocity_scaling_factor: 0.1      # 默认只用 10% 速度，安全
default_acceleration_scaling_factor: 0.1

joint_limits:
  base_joint:
    has_velocity_limits: true
    max_velocity: 1.0
    has_acceleration_limits: false
    max_acceleration: 0
  ...
```

**为什么默认只跑 10% 速度**：新手第一次规划通常目标离得很远，全速运动容易看起来像"甩飞"。调大这个系数（最大 1.0）可以让动作更快。

### 8.4.4 `config/moveit_controllers.yaml`（MoveIt ↔ 控制器对接表）

```yaml
moveit_controller_manager: moveit_simple_controller_manager/MoveItSimpleControllerManager

moveit_simple_controller_manager:
  controller_names:
    - ros2_arm_controller
    - finger_controller

  ros2_arm_controller:
    type: FollowJointTrajectory
    action_ns: follow_joint_trajectory
    default: true
    joints:
      - base_joint
      - shoulder_joint
      - elbow_joint

  finger_controller:
    type: GripperCommand
    action_ns: gripper_cmd
    default: true
    joints:
      - finger_right_joint
```

**这就是"规划层 → 控制层"的接线图**：MoveIt 按这里的名字找到 action，把轨迹发出去。`action_ns` + 控制器名拼起来正好是 `/ros2_arm_controller/follow_joint_trajectory`。

### 8.4.5 `launch/moveit_rviz.launch.py`（我们要用的启动文件）

```bash
ros2 launch ros2_arm_moveit_config moveit_rviz.launch.py use_sim_time:=True
```

它启动 **move_group + RViz**（带 MotionPlanning 插件）。

> ⚠️ **不要用 `demo.launch.py`**：它会给一个"假的控制器"（mock），专门用于**没有 Gazebo 时**单独玩规划。我们要让真仿真执行，所以用 `moveit_rviz.launch.py`。
>
> **可能的告警**：该 launch 可能也会启动一个 `robot_state_publisher`，与第 07 章的那个重复，日志里会出现 TF 重复发布的警告。两种处理：① 忽略（功能正常，实测原型项目也是这样）；② 把该 launch 里启动 rsp 的那段注释掉，只用 Gazebo 那边的。

---

## 8.5 重点内容（四）：完整验收（阶段 4 过关标准）

**两个终端，顺序不能反：**

```bash
# 终端 1：仿真（含控制器）
cd ~/ros2_arm && source install/setup.bash
ros2 launch ros2_arm_gazebo gz_launch.py

# 终端 2：规划（等终端 1 出现 "Configured and activated" 之后再启动）
cd ~/ros2_arm && source install/setup.bash
ros2 launch ros2_arm_moveit_config moveit_rviz.launch.py use_sim_time:=True
```

**终端 2 的期望日志**：

```
[move_group-2] You can start planning now!
[rviz2-1] [INFO] [move_group_interface]: Ready to take commands for planning group arm.
```

**RViz 里的操作**：

1. 左侧找到 **Motion Planning** 面板（如果没有：Panels → Add New Panel → MotionPlanning）；
2. **Planning Group** 选 `arm`；
3. 场景里会出现一个可拖动的球/箭头（Interactive Marker）——**拖动它改变目标位姿**；
4. 点 **Plan**（只看路径）；看到一条彩色轨迹后，点 **Execute**（真的执行）；
5. 转头看 Gazebo 窗口：**机械臂动起来了**；
6. 把 Planning Group 切到 `gripper`，用面板里的夹爪控制让它开合。

**命令行旁证**：

```bash
ros2 node list | grep move_group                     # 规划器在
ros2 action list | grep -E "follow_joint|gripper"    # 两个 action 都在
ros2 topic echo /joint_states --once --field position # 执行时数值持续变化
```

---

## 8.6 重点内容（五）：规划失败的三大类原因（诊断表）

| 症状 | 类别 | 原因 | 对策 |
|------|------|------|------|
| 拖到某位置，Plan 变红/报 `No motion plan found`，但位置看着不远 | **IK 不可达** | 超出臂长、关节限位挡住、目标姿态要求太苛刻 | 拖近一点；调大 `kinematics_solver_timeout/attempts`；放宽第 05 章的关节限位 |
| 有解但规划失败，报 `Unable to find a valid path` | **路径被挡** | 自碰撞（新算的碰撞矩阵太保守）、撞到世界里的方块、起点就在碰撞状态 | 把目标换到另一个方向；确认起点没撞东西；临时把 `target_cube` 移远 |
| Plan 成功但 Execute 报错 / `Goal ... ABORTED` | **执行层问题** | 控制器名或关节名与 YAML 不一致；控制器没 active；没开 `use_sim_time` | 用第 06 章 6.4.2 的三条 grep 核对；`ros2 control list_controllers` 确认 active |
| Execute 后机械臂只动了一点点就停 | **时间戳/速度问题** | 节点没用仿真时钟；轨迹超时判定 | 确认 `use_sim_time:=True`；看日志里有没有 `trajectory_duration_monitoring` 相关提示 |
| RViz 里机械臂姿态和 Gazebo 里不一致 | **TF/时钟问题** | 两个 robot_state_publisher 冲突；仿真时间不同步 | 见 8.4.5 的说明；确认所有节点同一个时钟 |

**通用排错顺序（从下往上）**：
`/clock` 在走吗 → 控制器 active 吗 → 接口 claimed 吗 → move_group 起了吗 → 控制器名对得上吗。**四步之内必定位。**

---

## 8.7 动手实践提示

1. 完整走一遍 8.3 的向导流程，生成 `ros2_arm_moveit_config`，编译，然后完成 8.5 的验收。**这是全项目的最高潮**——第一次看到自己写的机械臂自己规划并运动。
2. **改速度体验差异**：把 `joint_limits.yaml` 里的 `default_velocity_scaling_factor` 从 0.1 改成 0.5，重新规划，感受速度差别。然后改回 0.1（安全）。
3. **故意制造一次规划失败**：在 RViz 里把目标拖到机械臂**正后方的远处地面下**（明显够不到），点 Plan，观察报错原文并抄进笔记。这就是"IK 不可达"的样子。
4. **故意制造一次执行失败**：把 `moveit_controllers.yaml` 里的 `ros2_arm_controller` 改成 `ros2_arm_controllr`（少个 e），重启规划终端，Plan 成功后 Execute，观察报错。然后改回来。**这个坑很多人会真踩，先演练一次。**
5. 在 `practice/notes.md` 回答：URDF 和 SRDF 的分工是什么？为什么不能手写 SRDF？`demo.launch.py` 和 `moveit_rviz.launch.py` 的区别是什么？
