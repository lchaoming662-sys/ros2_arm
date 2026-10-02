# ros2_arm —— 你的第一个 ROS 2 机械臂项目（学习用骨架）

本目录是**从零手写**的 3 自由度机械臂仿真项目骨架，原型参照 `~/akabot-main`（6 自由度，含视觉）。
文档已经全部写好并**实测验证**；`src/` 下的代码文件是**空的**，等你自己按章节填写。

---

## 快速导航

| 想做的事 | 去哪 |
|---------|------|
| 先了解全貌、章节目录、项目规格 | [`docs/00_总览与阅读指南.md`](docs/00_总览与阅读指南.md) |
| 装环境 / 排查环境问题 | [`docs/02_环境搭建.md`](docs/02_环境搭建.md) |
| 写模型（URDF/Xacro） | [`docs/05_模型文件详解.md`](docs/05_模型文件详解.md) |
| 写控制系统 | [`docs/06_控制系统详解.md`](docs/06_控制系统详解.md) |
| 写仿真环境 | [`docs/07_仿真环境详解.md`](docs/07_仿真环境详解.md) |
| 配 MoveIt 运动规划 | [`docs/08_运动规划与MoveIt.md`](docs/08_运动规划与MoveIt.md) |
| 按阶段推进 / 排错方法 | [`docs/10_开发步骤安排.md`](docs/10_开发步骤安排.md) |

完整章节顺序：01 背景与目标 → 02 环境 → 03 整体架构 → 04 目录结构 → 05 模型 →
06 控制 → 07 仿真 → 08 规划 → 09 模块划分 → 10 开发步骤。

---

## 项目规格（一句话版）

3 自由度机械臂 + 2 个夹爪关节（含 1 个 mimic 从动），ROS 2 Humble + Gazebo Fortress + MoveIt 2，
4 个包（description / bringup / gazebo / moveit_config），仿真中可被 MoveIt 规划与执行。

**关节**：`base_joint`（转 Z）→ `shoulder_joint`（转 Y）→ `elbow_joint`（转 Y）→ `finger_right_joint`（转 X，夹爪主动指）+ `finger_left_joint`（转 X，`mimic` 反向跟随）。
**连杆**：`world` → `base_link` → `link1` → `link2` → `link3` → `gripper_base` → `finger_right` / `finger_left`。

详细规格见 `docs/00_总览与阅读指南.md` 的 0.2.2。

---

## 目录说明

```
ros2_arm/
├── docs/                 ← 11 个章节文档（完整可照抄，已实测）
├── src/                  ← 你的源码（当前为空文件，按章节顺序填写）
│   ├── ros2_arm_description/   模型 + 显示 launch
│   ├── ros2_arm_bringup/       控制器配置
│   ├── ros2_arm_gazebo/        世界文件 + 话题桥 + 仿真 launch
│   └── ros2_arm_moveit_config/ 第 08 章由配置向导生成
├── practice/             ← 自由练习区（两个示例节点，10.3 节有完整代码）
└── README.md
```

---

## 重要提醒

1. **`src/` 里的文件现在是空的**。在完成第 04 章的 `package.xml` / `CMakeLists.txt` 之前，
   运行 `colcon build` 一定会报解析错误——**那不是你写错了，只是还没到那一步**。
2. **编译命令**：
   ```bash
   cd ~/ros2_arm && colcon build --symlink-install && source install/setup.bash
   ```
   若在自动化环境里编译遇到 `catkin_pkg` 报错，见 `docs/02_环境搭建.md` 2.2.5 的"坑 1"。
3. **Python 节点必须用系统解释器**：`/usr/bin/python3`（ROS 的 rclpy 装在 Python 3.10 里）。

---

## 验证状态（本机实测）

| 验证项 | 结果 |
|-------|------|
| 环境（Humble + Gazebo 6.18 + MoveIt 2） | ✅ 可用 |
| 文档中的 4 个 xacro 展开 | ✅ 通过；`check_urdf` 结构与文档一致 |
| 文档中的 world / bridge / controllers / launch | ✅ 端到端跑通 |
| 三个控制器激活 | ✅ 全部 `active` |
| 四个关节接口被占用 | ✅ 全部 `[claimed]` |
| 发轨迹让关节运动 | ✅ 0 → [0.5, -0.4, 0.6]，`SUCCEEDED` |
| 夹爪开合 | ✅ 0 → 0.02，`SUCCEEDED`（修复几何贴合问题后） |

> 夹爪那个坑（活动爪与底座贴死被摩擦卡住）的完整排查过程写在 `docs/05_模型文件详解.md` 5.8.1，
> 是刻意保留的真实案例——**建模时凡是有相对运动的零件，都要留 2~5 mm 间隙**。
