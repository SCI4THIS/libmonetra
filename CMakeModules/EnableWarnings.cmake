# EnableWarnings.cmake
#
# Checks for and turns on a large number of warning C flags.
#
# Adds the following helper functions:
#
#	remove_warnings(... list of warnings ...)
#		Turn off given list of individual warnings for all targets and subdirectories added after this.
#
#   remove_all_warnings()
#		Remove all warning flags, add -w to suppress built-in warnings.
#
#   remove_all_warnings_from_targets(... list of targets ...)
#       Suppress warnings for the given targets only.
#
#   push_warnings()
#		Save current warning flags by pushing them onto an internal stack. Note that modifications to the internal
#		stack are only visible in the current CMakeLists.txt file and its children.
#
#       Note: changing warning flags multiple times in the same directory only affects add_subdirectory() calls.
#             Targets in the directory will always use the warning flags in effect at the end of the CMakeLists.txt
#             file - this is due to really weird and annoying legacy behavior of CMAKE_C_FLAGS.
#
#   pop_warnings()
#       Restore the last set of flags that were saved with push_warnings(). Note that modifications to the internal
#		stack are only visible in the current CMakeLists.txt file and its children.
#

if (_internal_enable_warnings_already_run)
	return()
endif ()
set(_internal_enable_warnings_already_run TRUE)

include(CheckCCompilerFlag)


# Default compiler flags we want enabled if supported.
set(_flags
	-W -Wextra -Wchar-subscripts -Wcomment -Wno-coverage-mismatch
	-Wdouble-promotion -Wformat -Wnonnull -Winit-self -Wimplicit-int
	-Wimplicit-function-declaration -Wimplicit -Wignored-qualifiers -Wmain
	-Wmissing-braces -Wmissing-include-dirs -Wparentheses -Wsequence-point
	-Wreturn-type -Wswitch -Wtrigraphs -Wunused-but-set-parameter
	-Wunused-but-set-variable -Wunused-function -Wunused-label
	-Wunused-local-typedefs -Wunused-parameter -Wunused-variable -Wunused-value
	-Wunused -Wuninitialized -Wmaybe-uninitialized -Wunknown-pragmas
	-Wmissing-format-attribute -Warray-bounds
	-Wtrampolines -Wfloat-equal
	-Wdeclaration-after-statement -Wundef -Wshadow -Wunsafe-loop-optimizations
	-Wpointer-arith -Wtype-limits -Wbad-function-cast -Wcast-qual
	-Wcast-align -Wwrite-strings -Wclobbered -Wempty-body
	-Wenum-compare -Wjump-misses-init -Wsign-compare -Wsizeof-pointer-memaccess
	-Waddress -Wlogical-op -Waggregate-return
	-Wstrict-prototypes -Wold-style-declaration -Wold-style-definition
	-Wmissing-parameter-type -Wmissing-prototypes -Wmissing-declarations
	-Wmissing-field-initializers -Woverride-init -Wpacked -Wredundant-decls
	-Wnested-externs -Winline -Winvalid-pch -Wvariadic-macros -Wvarargs
	-Wvector-operation-performance -Wvla -Wpointer-sign
	-Wdisabled-optimization -Wendif-labels -Wpacked-bitfield-compat
	-Wformat-security -Woverlength-strings -Wstrict-aliasing
	-Wstrict-overflow -Wsync-nand -Wvolatile-register-var
	-Wconversion -Wsign-conversion
)

if (WIN32)
	# W4 would be better but it produces unnecessary warnings like:
	# *  warning C4706: assignment within conditional expression
	#     Triggered when doing "while(1)"
	# * warning C4115: 'timeval' : named type definition in parentheses
	# * warning C4201: nonstandard extension used : nameless struct/union
	#     Triggered by system includes (commctrl.h, shtypes.h, Shlobj.h)
	list(APPEND _flags "-W3")
else ()
	# Don't put this in the default list because it causes unnecessary warnings on windows.
	list(APPEND _flags "-Wall")
endif ()

# Check and set compiler flags.
foreach(_flag ${_flags})
	CHECK_C_COMPILER_FLAG(${_flag} HAVE_${_flag})
	if (HAVE_${_flag})
		set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${_flag}")
	endif ()
endforeach ()


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Helper functions


# This function can be called in subdirectories, to prune out warnings that they don't want.
#  vararg: warning flags to remove from list of enabled warnings. All "no" flags after EXPLICIT_DISABLE
#          will be added to C flags.
#
# Ex.: remove_warnings(-Wall -Wdouble-promotion -Wcomment) prunes those warnings flags from the compile command.
function(remove_warnings)
	set(pruned "${CMAKE_C_FLAGS}")
	set(toadd)
	set(in_explicit_disable FALSE)
	foreach (flag ${ARGN})
		if (flag STREQUAL "EXPLICIT_DISABLE")
			set(in_explicit_disable TRUE)
		elseif (in_explicit_disable)
			string(APPEND toadd " ${flag}")
		else ()
			string(REGEX REPLACE "${flag}([ \t]+|$)" "" pruned "${pruned}")
		endif ()
	endforeach ()
	if (toadd)
		string(APPEND pruned " ${toadd}")
	endif ()
	set(CMAKE_C_FLAGS "${pruned}" PARENT_SCOPE)
endfunction()


# Explicitly suppress all warnings. As long as this flag is the last warning flag, warnings will be
# suppressed even if earlier flags enabled warnings.
function(remove_all_warnings)
	string(REGEX REPLACE "[-/]W[^ \t]*([ \t]+|$)" "" CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")
	if (MSVC)
		string(APPEND CMAKE_C_FLAGS " /w")
	else ()
		string(APPEND CMAKE_C_FLAGS " -w")
	endif ()
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}" PARENT_SCOPE)
endfunction()


function(remove_all_warnings_from_targets)
	foreach (target ${ARGN})
		if (MSVC)
			target_compile_options(${target} PRIVATE "/w")
		else ()
			target_compile_options(${target} PRIVATE "-w")
		endif ()
	endforeach()
endfunction()


# Save the current warning settings to an internal variable.
function(push_warnings)
	if (CMAKE_C_FLAGS MATCHES ";")
		message(FATAL_ERROR "Cannot push_warnings, CMAKE_C_FLAGS contains semicolons")
	endif ()
	# Add current flags to end of internal list.
	list(APPEND _enable_warnings_internal_cflags_stack "${CMAKE_C_FLAGS}")
	# Propagate results up to caller's scope.
	set(_enable_warnings_internal_cflags_stack "${_enable_warnings_internal_cflags_stack}" PARENT_SCOPE)
endfunction()


# Restore the current warning settings from an internal variable.
function(pop_warnings)
	if (NOT _enable_warnings_internal_cflags_stack)
		message(AUTHOR_WARNING "pop_warnings called when nothing is in the warnings stack, must be an extra call")
	endif ()
	# Pop flags off of end of list, overwrite current flags with whatever we popped off.
	list(GET _enable_warnings_internal_cflags_stack -1 CMAKE_C_FLAGS)
	list(REMOVE_AT _enable_warnings_internal_cflags_stack -1)
	# Propagate results up to caller's scope.
	set(_enable_warnings_internal_cflags_stack "${_enable_warnings_internal_cflags_stack}" PARENT_SCOPE)
	set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}" PARENT_SCOPE)
endfunction()