if(NOT UNIX)
  message(FATAL_ERROR "Unsupported platform")
endif()

cmake_minimum_required(VERSION 3.12 FATAL_ERROR)

project(runner)
find_package(Torch REQUIRED)
find_package(OpenCV REQUIRED)

enable_language(CXX)
set(ABSL_PROPAGATE_CXX_STD ON)
set(CMAKE_BUILD_TYPE Release)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC -O3 -Wall -Wextra -Wno-unused-parameter")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-missing-field-initializers")
if(APPLE)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -undefined dynamic_lookup")
endif()

include(CheckLanguage)
check_language(CUDA)
if(CMAKE_CUDA_COMPILER)
  add_compile_definitions(HAVE_CUDA)
endif()

file(GLOB_RECURSE runner_sources
  LIST_DIRECTORIES false
  CONFIGURE_DEPENDS
  "${SRC_DIR}/*.cc" "${SRC_DIR}/*.hh"
)

add_executable(runner ${runner_sources})
target_include_directories(runner PUBLIC "${ERL_INTERFACE_INCLUDE_DIR}")
target_include_directories(runner PUBLIC "${ERTS_INCLUDE_DIR}")
target_link_libraries(runner PUBLIC "${TORCH_LIBRARIES}")
target_link_libraries(runner PUBLIC "${OpenCV_LIBS}")
target_link_libraries(runner PUBLIC ei)
target_link_directories(runner PUBLIC "${ERL_INTERFACE_LIB_DIR}")

set_target_properties(runner PROPERTIES
  INSTALL_RPATH_USE_LINK_PATH TRUE
  BUILD_WITH_INSTALL_RPATH TRUE
)

if(APPLE)
  set_target_properties(runner PROPERTIES INSTALL_RPATH "@loader_path/install")
else()
  set_target_properties(runner PROPERTIES INSTALL_RPATH "\$ORIGIN/install")
endif()
