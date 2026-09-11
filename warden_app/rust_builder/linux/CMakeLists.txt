cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "rust_lib_wcash_warden")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../../rust rust_lib_wcash_warden "")

set(rust_lib_wcash_warden_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
