# Adds the tronb2 target to b2's own CMake build without changing b2 (build.sh).
set(TRONB2_DIR ${CMAKE_CURRENT_LIST_DIR} CACHE INTERNAL "")
cmake_language(DEFER DIRECTORY ${CMAKE_SOURCE_DIR} CALL _tronb2_add)
function(_tronb2_add)
  add_executable(tronb2 ${TRONB2_DIR}/tronb2.cpp)
  target_link_libraries(tronb2 PRIVATE shared_lib beeb_lib stb_image_lib)
  set_target_properties(tronb2 PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON)
  b2_target_boilerplate(tronb2)
endfunction()
