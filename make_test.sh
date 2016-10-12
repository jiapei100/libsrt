#!/bin/bash
#
# make_test.sh
#
# Syntax: ./make_test.sh [mask]
#
# Where:
# - No parameters: all tests
# - mask = "or" operation of the following:
#		 1: Validate all available C/C++ builds
#		 2: Valgrind memcheck
#		 4: Clang static analyzer
#		 8: Generate documentation
#		16: Check coding style
#
# Examples:
# ./make_test.sh    # Equivalent to ./make_test.sh 31
# ./make_test.sh 1  # Do the builds
# ./make_test.sh 17 # Do the builds and check coding style
# ./make_test.sh 24 # Generate documentation and check coding style
#
# libsrt build, test, and documentation generation.
#
# Copyright (c) 2015-2016 F. Aragon. All rights reserved.
#

if (($# == 1)) && (($1 >= 1 && $1 < 32)) ; then TMUX=$1 ; else TMUX=31 ; fi
if [ "$SKIP_FORCE32" == "1" ] ; then
	FORCE32T=""
else
	FORCE32T="FORCE32=1"
fi
TEST_CC[0]="gcc"
TEST_CC[1]="gcc"
TEST_CC[2]="gcc"
TEST_CC[3]="gcc"
TEST_CC[4]="clang"
TEST_CC[5]="clang"
TEST_CC[6]="clang"
TEST_CC[7]="tcc"
TEST_CC[8]="g++"
TEST_CC[9]="g++"
TEST_CC[10]="clang++"
TEST_CC[11]="clang++"
TEST_CC[12]="arm-linux-gnueabi-gcc"
TEST_CC[13]="arm-linux-gnueabi-gcc"
TEST_FLAGS[0]="C99=1 PEDANTIC=1"
TEST_FLAGS[1]="PROFILING=1"
TEST_FLAGS[2]="C99=0"
TEST_FLAGS[3]="C99=0 $FORCE32T"
TEST_FLAGS[4]="C99=1 PEDANTIC=1"
TEST_FLAGS[5]="C99=0 $FORCE32T"
TEST_FLAGS[6]="C99=1"
TEST_FLAGS[7]=""
TEST_FLAGS[8]=""
TEST_FLAGS[9]="CPP0X=1"
TEST_FLAGS[10]=""
TEST_FLAGS[11]="CPP11=1"
TEST_FLAGS[12]="C99=0"
TEST_FLAGS[13]="C99=1"
TEST_DO_UT[0]="all"
TEST_DO_UT[1]="all"
TEST_DO_UT[2]="all"
TEST_DO_UT[3]="all"
TEST_DO_UT[4]="all"
TEST_DO_UT[5]="all"
TEST_DO_UT[6]="all"
TEST_DO_UT[7]="all"
TEST_DO_UT[8]="all"
TEST_DO_UT[9]="all"
TEST_DO_UT[10]="all"
TEST_DO_UT[11]="all"
TEST_DO_UT[12]="stest"
TEST_DO_UT[13]="stest"
INNER_LOOP_FLAGS[0]=""
INNER_LOOP_FLAGS[1]="DEBUG=1"
INNER_LOOP_FLAGS[2]="MINIMAL=1"
INNER_LOOP_FLAGS[3]="MINIMAL=1 DEBUG=1"
ERRORS=0
NPROCS=0
MJOBS=1

if [ -e /proc/cpuinfo ] ; then # Linux CPU count
	NPROCS=$(grep processor /proc/cpuinfo | wc -l)
fi
if [ $(uname) = Darwin ] ; then # OSX CPU count
	NPROCS=$(sysctl hw.ncpu | awk '{print $2}')
fi
if (( NPROCS > MJOBS )) ; then MJOBS=$NPROCS ; fi

echo "make_test.sh running..."

# Locate GNU Make
if [ "$MAKE" == "" ] ; then
	if type gmake >/dev/null 2>&1 ; then
		MAKE=gmake
	else
		MAKE=make
	fi
fi

if (($TMUX & 1)) ; then
	for ((i = 0 ; i < ${#TEST_CC[@]}; i++)) ; do
		if type ${TEST_CC[$i]} >/dev/null 2>&1 >/dev/null ; then
			for ((j = 0 ; j < ${#INNER_LOOP_FLAGS[@]}; j++)) ; do
				CMD="$MAKE -j $MJOBS CC=${TEST_CC[$i]} ${TEST_FLAGS[$i]}"
				CMD="$CMD ${INNER_LOOP_FLAGS[$j]} ${TEST_DO_UT[$i]}"
				$MAKE clean >/dev/null 2>&1
				echo -n "Test #$i.$j: [$CMD] ..."
				if $CMD >/dev/null 2>&1 ; then
					echo " OK"
				else 	echo " ERROR"
					ERRORS=$((ERRORS + 1))
				fi
			done
		else
			echo "Test #$i: ${TEST_CC[$i]} compiler not found (skipped)"
		fi
	done
fi

VAL_ERR_TAG="ERROR SUMMARY:"
VAL_ERR_FILE=valgrind.errors

if (($TMUX & 2)) && type valgrind >/dev/null 2>&1 ; then
	echo -n "Valgrind test..."
	if $MAKE clean >/dev/null 2>&1 &&				  \
	   $MAKE -j $MJOBS DEBUG=1 >/dev/null 2>&1 &&			  \
	   valgrind --track-origins=yes --tool=memcheck --leak-check=yes  \
		    --show-reachable=yes --num-callers=20 --track-fds=yes \
		    ./stest >/dev/null 2>$VAL_ERR_FILE ; then
		VAL_ERRS=$(grep "$VAL_ERR_TAG" "$VAL_ERR_FILE" | awk -F \
			   'ERROR SUMMARY:' '{print $2}' | awk '{print $1}')
		if (( $VAL_ERRS > 0 )) ; then
			ERRORS=$((ERRORS + $VAL_ERRS))
			echo " ERROR"
		else
			echo " OK"
		fi
	else 	echo " ERROR"
		ERRORS=$((ERRORS + 1))
	fi
fi

if (($TMUX & 4)) && type scan-build >/dev/null 2>&1 ; then
	echo -n "Clang static analyzer..."
	$MAKE clean
	if scan-build -v $MAKE CC=clang 2>&1 >clang_analysis.txt ; then
		echo " OK"
	else	echo " ERROR"
		ERRORS=$((ERRORS + 1))
	fi
fi

if (($TMUX & 8)) ; then
	if  type python3 >/dev/null 2>&1 ; then
		echo "Documentation generation test..."
		if ! utl/mk_doc.sh src out_doc ; then
			ERRORS=$((ERRORS + 1))
		fi
	else
		echo "WARNING: doc not generated (python3 not found)"
	fi
fi

if (($TMUX & 16)) ; then
	echo "Checking style..."
	ls -1  src/*c src/saux/*c examples/*c examples/*h Makefile \
		*\.sh utl/*\.sh | while read line ; do
		if ! utl/check_style.sh "$line" ; then
			echo "$line... ERROR"
			ERRORS=$((ERRORS + 1))
		fi
	done
fi

exit $ERRORS

