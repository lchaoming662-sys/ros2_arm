import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.conditions import IfCondition, UnlessCondition
from launch.substitutions import Command, LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue


def generate_launch_description():
    pkg_share = get_package_share_directory('ros2_arm_description')
    xacro_file = os.path.join(pkg_share, 'urdf', 'ros2_arm.urdf.xacro')
    rviz_config = os.path.join(pkg_share, 'rviz', 'display.rviz')

    use_gui = LaunchConfiguration('use_gui')

    # Command 会执行 "xacro <文件>" 并把输出（纯 URDF 文本）作为参数传给节点
    robot_description = {
        'robot_description': ParameterValue(Command(['xacro ', xacro_file]), value_type=str)
    }

    # RViz 配置文件还不存在时，就让 rviz2 用默认配置启动（避免报错吓人）
    rviz_args = ['-d', rviz_config] if os.path.exists(rviz_config) else []

    return LaunchDescription([
        DeclareLaunchArgument('use_gui', default_value='true',
                              description='true=用滑块手动摆关节，false=用默认值'),

        # 把 URDF 转成 TF 树（RViz 靠它知道零件之间的位置关系）
        Node(package='robot_state_publisher', executable='robot_state_publisher',
             output='screen', parameters=[robot_description]),

        # 滑块窗口：手动给每个关节设角度
        Node(package='joint_state_publisher_gui', executable='joint_state_publisher_gui',
             condition=IfCondition(use_gui)),

        # 无滑块时的替代：给关节发默认值
        Node(package='joint_state_publisher', executable='joint_state_publisher',
             condition=UnlessCondition(use_gui)),

        Node(package='rviz2', executable='rviz2', output='screen', arguments=rviz_args),
    ])

    