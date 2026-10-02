cmake_minimum_required(VERSION 3.8)
project(ros2_arm_description)

find_package(ament_cmake REQUIRED)

# 把资源目录安装到 install/<包名>/share/<包名>/ 下
install(
  DIRECTORY config launch rviz urdf
  DESTINATION share/${PROJECT_NAME}
)

ament_package()

