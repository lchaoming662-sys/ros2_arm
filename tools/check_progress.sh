#!/usr/bin/env bash
# ============================================================
#  ros2_arm 学习进度自检
#
#  用法：
#      bash ~/ros2_arm/tools/check_progress.sh
#
#  作用：
#      逐项检查第 11 章《从零手敲代码实战》的 12 个步骤，
#      告诉你哪些已通过、哪些没写、哪些写错了。
#
#  图例： ✅ 通过   ❌ 失败（附原因）   ⏭ 跳过（前置条件未满足）
# ============================================================

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$WS/src"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
SKIP=0

ok()   { echo "  ✅ $1"; PASS=$((PASS + 1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  ⏭  $1"; SKIP=$((SKIP + 1)); }
hint() { echo "       $1"; }

# ---------- 挑一个带 pyyaml 的 Python ----------
# 注意：PATH 里的 python3 不一定是系统那个（可能被别的工具链抢占，
# 那个环境里通常没装 pyyaml）。所以优先用 /usr/bin/python3。
PY=""
for cand in /usr/bin/python3 python3; do
    if command -v "$cand" > /dev/null 2>&1 \
       && "$cand" -c "import yaml" > /dev/null 2>&1; then
        PY="$cand"; break
    fi
done

# ---------- 环境准备 ----------
if [[ -f /opt/ros/humble/setup.bash ]]; then
    # shellcheck disable=SC1091
    source /opt/ros/humble/setup.bash
else
    echo "⚠️  找不到 /opt/ros/humble/setup.bash —— ROS 2 Humble 没装？"
    exit 1
fi

SOURCED=0
if [[ -f "$WS/install/setup.bash" ]]; then
    # shellcheck disable=SC1091
    source "$WS/install/setup.bash"
    SOURCED=1
fi

# ------------------------------------------------------------
# 检查 1：文件存在且非空
#   参数: 相对路径  描述
# ------------------------------------------------------------
check_file() {
    local f="$WS/$1" desc="$2"
    if [[ -s "$f" ]]; then
        ok "$desc （$(wc -l < "$f") 行）"
    else
        bad "$desc —— 还没写或为空"
        hint "文件: $1"
    fi
}

# ------------------------------------------------------------
# 检查 2：xacro 能否展开
#   参数: 相对路径  描述
# ------------------------------------------------------------
check_xacro() {
    local rel="$1" desc="$2"
    local f="$WS/$rel"
    if [[ ! -s "$f" ]]; then
        skip "$desc（文件为空）"
        return 1
    fi
    if xacro "$f" > "$TMP/out.urdf" 2> "$TMP/out.err"; then
        ok "$desc"
        return 0
    fi
    # 含 $(find 但没 source / 没编译 → 属于前置条件未满足
    if grep -q '\$(find' "$f" && [[ $SOURCED -eq 0 ]]; then
        skip "$desc（需要先 colcon build 并 source）"
        return 1
    fi
    bad "$desc"
    sed 's/^/       /' "$TMP/out.err" | head -4
    return 1
}

# ------------------------------------------------------------
# 检查 3：YAML 语法
#   参数: 相对路径  描述
# ------------------------------------------------------------
check_yaml() {
    local f="$WS/$1" desc="$2"
    if [[ ! -s "$f" ]]; then
        skip "$desc（文件为空）"
        return
    fi
    if [[ -z "$PY" ]]; then
        # 找不到带 pyyaml 的 Python，降级为"只用 ROS 自己的解析器"
        if xacro "$f" > /dev/null 2>&1; then ok "$desc"; else skip "$desc（没找到 pyyaml，跳过）"; fi
        return
    fi
    if "$PY" -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$f" 2> "$TMP/y.err"; then
        ok "$desc"
    else
        bad "$desc"
        head -3 "$TMP/y.err" | sed 's/^/       /'
    fi
}

echo "============================================================"
echo " ros2_arm 学习进度自检"
echo " 工作空间: $WS"
echo "============================================================"

# ============================================================
# 阶段一 · 让空包编译通过
# ============================================================
echo
echo "【阶段一】让空包编译通过"

echo "  -- 步骤 1：目录结构 --"
missing_dir=0
for d in ros2_arm_description/{urdf,launch,config,rviz} \
         ros2_arm_bringup/{config,launch} \
         ros2_arm_gazebo/{worlds,config,launch}; do
    [[ -d "$SRC/$d" ]] || { bad "缺少目录 src/$d"; missing_dir=1; }
done
[[ $missing_dir -eq 0 ]] && ok "3 个包、11 个子目录齐全"

echo "  -- 步骤 2：package.xml --"
for p in ros2_arm_description ros2_arm_bringup ros2_arm_gazebo; do
    f="$SRC/$p/package.xml"
    if [[ ! -s "$f" ]]; then
        bad "$p/package.xml 为空"
        continue
    fi
    if python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" "$f" 2>/dev/null; then
        name="$(grep -oP '(?<=<name>)[^<]+' "$f" | head -1)"
        if [[ "$name" == "$p" ]]; then
            ok "$p/package.xml （<name> 匹配）"
        else
            bad "$p/package.xml —— <name> 是 '$name'，应等于目录名 '$p'"
        fi
    else
        bad "$p/package.xml —— XML 语法错误"
    fi
done

echo "  -- 步骤 3：CMakeLists.txt --"
for p in ros2_arm_description ros2_arm_bringup ros2_arm_gazebo; do
    f="$SRC/$p/CMakeLists.txt"
    if [[ ! -s "$f" ]]; then
        bad "$p/CMakeLists.txt 为空"
        continue
    fi
    # install(DIRECTORY ...) 里列出的每个目录都必须真实存在
    dirs="$(grep -oP '(?<=DIRECTORY ).*(?=DESTINATION)' "$f" | head -1)"
    if [[ -z "$dirs" ]]; then
        bad "$p/CMakeLists.txt —— 没找到 install(DIRECTORY ...) 语句"
        continue
    fi
    miss=""
    for d in $dirs; do
        [[ -d "$SRC/$p/$d" ]] || miss="$miss $d"
    done
    if [[ -z "$miss" ]]; then
        ok "$p/CMakeLists.txt （install 的目录都存在）"
    else
        bad "$p/CMakeLists.txt —— 这些目录不存在:$miss"
        hint "会报 ament_cmake_symlink_install_directory() can't find ..."
    fi
done

# ============================================================
# 阶段二 · 把模型画出来
# ============================================================
echo
echo "【阶段二】把模型画出来"

echo "  -- 步骤 5：核心模型 ros2_arm_core.xacro --"
CORE="src/ros2_arm_description/urdf/ros2_arm_core.xacro"
check_file "$CORE" "ros2_arm_core.xacro 已写"
if [[ -s "$WS/$CORE" ]]; then
    nlink=$(grep -c '<link name=' "$WS/$CORE")
    njoint=$(grep -c '<joint name=' "$WS/$CORE")
    if [[ $nlink -eq 8 && $njoint -eq 7 ]]; then
        ok "link 数量 8 / joint 数量 7（符合设计）"
    else
        bad "link=$nlink / joint=$njoint（期望 8 / 7）"
    fi
    # 关键的三处易漏点
    grep -q '<link name="world"/>' "$WS/$CORE" \
        && ok "world 链接存在（底座被钉住）" \
        || bad "缺少 <link name=\"world\"/> —— 仿真里机械臂会自由落体"
    grep -q 'type="fixed"' "$WS/$CORE" \
        && : || bad "没有 fixed 关节（world_base_joint / gripper_joint 呢？）"
    nzero=$(grep -cE 'mass value="0(\.0*)?"|mass="0"' "$WS/$CORE")
    if [[ $nzero -eq 0 ]]; then
        ok "没有 mass=0 的连杆"
    else
        bad "有 $nzero 处 mass=0 的连杆 → 仿真会飞天（坑 M-7）"
    fi

    if [[ -z "$(grep -E 'name="finger_right_joint"' "$WS/$CORE")" ]]; then
        bad "找不到 finger_right_joint —— 请按第 11 章批次 C 改用旋转夹爪"
    else
        ok "夹爪用 revolute 双指（finger_right_joint 存在）"
    fi
    grep -q 'mimic joint="finger_right_joint"' "$WS/$CORE" \
        && ok "左指用 <mimic> 反向跟随右指" \
        || bad "缺 <mimic> 声明 → 两指不会对称开合"
    grep -q 'type="prismatic"' "$WS/$CORE" \
        && bad "检测到 prismatic 关节 —— 平移夹爪在机械臂倾斜时会失效（见 05 章 5.8.1）" \
        || ok "没有 prismatic 关节（避开倾斜失效问题）"

    if check_xacro "$CORE" "xacro 展开通过"; then
        if check_urdf "$TMP/out.urdf" > "$TMP/tree.txt" 2>&1; then
            if grep -q 'finger_right' "$TMP/tree.txt" && grep -q 'finger_left' "$TMP/tree.txt"; then
                ok "check_urdf 结构完整（world→...→gripper_base→两片指）"
            else
                bad "结构树缺夹爪指 —— 夹爪那段还没写（批次 C）"
            fi
        else
            bad "check_urdf 失败"
            head -3 "$TMP/tree.txt" | sed 's/^/       /'
        fi
    fi
fi

echo "  -- 步骤 6+7：显示用总装与 display.launch.py --"
check_xacro "src/ros2_arm_description/urdf/ros2_arm.urdf.xacro" "ros2_arm.urdf.xacro 可展开"
check_file "src/ros2_arm_description/launch/display.launch.py" "display.launch.py 已写"

# ============================================================
# 阶段三 · 让关节能被控制
# ============================================================
echo
echo "【阶段三】让关节能被控制"

echo "  -- 步骤 8：接口声明 --"
RSC="src/ros2_arm_description/urdf/ros2_arm.ros2_control.xacro"
check_file "$RSC" "ros2_arm.ros2_control.xacro 已写"
if [[ -s "$WS/$RSC" ]]; then
    c=$(grep -c '<command_interface' "$WS/$RSC")
    s=$(grep -c '<state_interface' "$WS/$RSC")
    [[ $c -eq 5 ]] && ok "command_interface = 5" || bad "command_interface = $c（期望 5）"
    [[ $s -eq 10 ]] && ok "state_interface = 10" || bad "state_interface = $s（期望 10）"
fi

echo "  -- 步骤 9：控制器配置 --"
CTRL="src/ros2_arm_bringup/config/ros2_arm_controllers.yaml"
check_file "$CTRL" "ros2_arm_controllers.yaml 已写"
check_yaml "$CTRL" "ros2_arm_controllers.yaml YAML 语法正确"
if [[ -s "$WS/$CTRL" ]]; then
    # 交叉核对：yaml 里的关节名必须都能在 URDF 里找到
    if [[ -s "$WS/$CORE" ]]; then
        bad_names=""
        for j in $(grep -oE '(base|shoulder|elbow|finger_(left|right))_joint' "$WS/$CTRL" | sort -u); do
            grep -q "joint name=\"$j\"" "$WS/$CORE" || bad_names="$bad_names $j"
        done
        if [[ -z "$bad_names" ]]; then
            ok "yaml 里的关节名都能在 URDF 中找到"
        else
            bad "这些关节名在 URDF 里不存在:$bad_names"
        fi
    fi
    grep -q 'joint_state_broadcaster' "$WS/$CTRL" \
        && ok "声明了 joint_state_broadcaster" \
        || bad "缺 joint_state_broadcaster —— 没有它 RViz/MoveIt 全都瘫"
fi

# ============================================================
# 阶段四 · 让它在仿真里动起来
# ============================================================
echo
echo "【阶段四】让它在仿真里动起来"

echo "  -- 步骤 10：世界文件 --"
WORLD="src/ros2_arm_gazebo/worlds/arm_world.sdf"
check_file "$WORLD" "arm_world.sdf 已写"
if [[ -s "$WS/$WORLD" ]]; then
    if command -v ign > /dev/null 2>&1; then
        out="$(ign sdf -k "$WS/$WORLD" 2>&1)"
        if echo "$out" | grep -q 'Valid'; then
            ok "SDF 校验通过（Valid）"
        else
            bad "SDF 校验失败"; echo "$out" | head -3 | sed 's/^/       /'
        fi
        miss_plugin=""
        for p in Physics UserCommands SceneBroadcaster; do
            grep -q "$p" "$WS/$WORLD" || miss_plugin="$miss_plugin $p"
        done
        if [[ -z "$miss_plugin" ]]; then
            ok "三个必备系统插件齐全（Physics / UserCommands / SceneBroadcaster）"
        else
            bad "world 里缺这些插件:$miss_plugin"
        fi
    else
        skip "ign 命令不存在，跳过 SDF 校验"
    fi
fi

echo "  -- 步骤 11：桥接配置 --"
BR="src/ros2_arm_gazebo/config/ros2_arm_bridge.yaml"
check_file "$BR" "ros2_arm_bridge.yaml 已写"
check_yaml "$BR" "ros2_arm_bridge.yaml YAML 语法正确"
if [[ -s "$WS/$BR" ]]; then
    grep -q '"Clock"' "$WS/$BR" && bad "ros_type_name 写成了 Clock（应为小写 clock，会静默失败）" \
                               || ok "话题名大小写正确"
fi

echo "  -- 步骤 12：仿真用总装 --"
GZU="src/ros2_arm_description/urdf/ros2_arm_gz.urdf.xacro"
check_file "$GZU" "ros2_arm_gz.urdf.xacro 已写"
if [[ -s "$WS/$GZU" ]] && check_xacro "$GZU" "ros2_arm_gz.urdf.xacro 可展开"; then
    c=$(grep -c '<command_interface' "$TMP/out.urdf")
    s=$(grep -c '<state_interface' "$TMP/out.urdf")
    [[ $c -eq 5 ]] && ok "展开后 command_interface = 5" || bad "展开后 command_interface = $c（期望 5）"
    [[ $s -eq 10 ]] && ok "展开后 state_interface = 10" || bad "展开后 state_interface = $s（期望 10）"
    grep -q 'IgnitionROS2ControlPlugin' "$TMP/out.urdf" \
        && ok "Gazebo ros2_control 插件已嵌入" \
        || bad "展开结果里没有 IgnitionROS2ControlPlugin"
    grep -q 'ros2_arm_controllers.yaml' "$TMP/out.urdf" \
        && ok "控制器 yaml 路径已解析（\$(find ...) 成功）" \
        || bad "\$(find ros2_arm_bringup) 未解析 → 控制器一个都加载不出来（坑 S-1）"
fi

echo "  -- 步骤 13：仿真 launch --"
check_file "src/ros2_arm_gazebo/launch/gz_launch.py" "gz_launch.py 已写"

echo "  -- 步骤 14：实际运行状态（需仿真正在跑） --"
# 注意：没有 controller_manager 时 ros2 control 会一直等，必须加 timeout
CTRL_OUT="$(timeout 10 ros2 control list_controllers 2>/dev/null)"
if [[ -z "$CTRL_OUT" ]]; then
    skip "当前没有运行中的 controller_manager（仿真没启动）"
else
    echo "$CTRL_OUT" | sed 's/^/       /'
    n=$(echo "$CTRL_OUT" | grep -c 'active')
    [[ $n -ge 3 ]] && ok "3 个控制器 active" || bad "只有 $n 个 controller active（期望 3）"
    if timeout 10 ros2 control list_hardware_interfaces 2>/dev/null | grep -q 'claimed'; then
        ok "有关节接口被 [claimed]"
    else
        bad "没有接口被 [claimed] —— 控制器没认领硬件接口"
    fi
fi

# ============================================================
# 汇总
# ============================================================
echo
echo "============================================================"
printf " 通过 \033[32m%d\033[0m   失败 \033[31m%d\033[0m   跳过 %d\n" "$PASS" "$FAIL" "$SKIP"
echo "============================================================"

if [[ $FAIL -eq 0 ]]; then
    echo " 🎉 全部通过！"
    if [[ $SKIP -gt 0 ]]; then
        echo "    （有 $SKIP 项跳过，通常是「仿真还没启动」或「还没编译」，属正常）"
    fi
else
    echo " 有问题的地方已用 ❌ 标出，逐条修完再跑一次。"
    echo " 报错原因对照：docs/11_从零手敲代码实战.md 附录 B"
fi
echo
