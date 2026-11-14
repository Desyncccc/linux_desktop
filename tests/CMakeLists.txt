find_package(Qt6 REQUIRED COMPONENTS Test)

qt_add_executable(tst_desktopentry tst_desktopentry.cpp)
target_link_libraries(tst_desktopentry PRIVATE vitrumcore Qt6::Test)
add_test(NAME desktopentry COMMAND tst_desktopentry)

qt_add_executable(tst_keyfilter tst_keyfilter.cpp ../src/keyfilter.cpp)
target_include_directories(tst_keyfilter PRIVATE ../src)
target_link_libraries(tst_keyfilter PRIVATE Qt6::Gui Qt6::Qml Qt6::Test)
add_test(NAME keyfilter COMMAND tst_keyfilter)
set_tests_properties(keyfilter PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
