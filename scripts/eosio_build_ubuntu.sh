	OS_VER=$( grep VERSION_ID /etc/os-release | cut -d'=' -f2 | sed 's/[^0-9\.]//gI' )
	OS_MAJ=$(echo "${OS_VER}" | cut -d'.' -f1)
	OS_MIN=$(echo "${OS_VER}" | cut -d'.' -f2)

	MEM_MEG=$( free -m | sed -n 2p | tr -s ' ' | cut -d\  -f2 || cut -d' ' -f2 )
	CPU_SPEED=$( lscpu | grep -m1 "MHz" | tr -s ' ' | cut -d\  -f3 || cut -d' ' -f3 | cut -d'.' -f1 )
	CPU_CORE=$( lscpu -pCPU | grep -v "#" | wc -l )

	MEM_GIG=$(( ((MEM_MEG / 1000) / 2) ))
	JOBS=$(( MEM_GIG > CPU_CORE ? CPU_CORE : MEM_GIG ))

	DISK_INSTALL=$(df -h . | tail -1 | tr -s ' ' | cut -d\  -f1 || cut -d' ' -f1)
	DISK_TOTAL_KB=$(df . | tail -1 | awk '{print $2}')
	DISK_AVAIL_KB=$(df . | tail -1 | awk '{print $4}')
	DISK_TOTAL=$(( DISK_TOTAL_KB / 1048576 ))
	DISK_AVAIL=$(( DISK_AVAIL_KB / 1048576 ))

	# Enter working directory
	cd $SRC_LOCATION

	# Legacy path support (ln -s for boost/wasm) | TODO: Remove reliance on $HOME/opt for /opt
	mkdir -p $HOME/opt

	printf "\\nOS name: ${OS_NAME}\\n"
	printf "OS Version: ${OS_VER}\\n"
	printf "CPU speed: ${CPU_SPEED}Mhz\\n"
	printf "CPU cores: %s\\n" "${CPU_CORE}"
	printf "Physical Memory: ${MEM_MEG} Mgb\\n"
	printf "Disk install: ${DISK_INSTALL}\\n"
	printf "Disk space total: ${DISK_TOTAL%.*}G\\n"
	printf "Disk space available: ${DISK_AVAIL%.*}G\\n"

	if [ "${MEM_MEG}" -lt 7000 ]; then
		printf "Your system must have 7 or more Gigabytes of physical memory installed.\\n"
		printf "Exiting now.\\n"
		exit 1
	fi

	case "${OS_NAME}" in
		"Linux Mint")
		   if [ "${OS_MAJ}" -lt 18 ]; then
			   printf "You must be running Linux Mint 18.x or higher to install EOSIO.\\n"
			   printf "Exiting now.\\n"
			   exit 1
		   fi
		;;
		"Ubuntu")
			if [ "${OS_MAJ}" -lt 16 ]; then
				printf "You must be running Ubuntu 16.04.x or higher to install EOSIO.\\n"
				printf "Exiting now.\\n"
				exit 1
			fi
			# UBUNTU 18 doesn't have MONGODB 3.6.3
			if [ $OS_MAJ -gt 16 ]; then
				MONGODB_VERSION=4.1.1
			fi
		;;
		"Debian")
			if [ $OS_MAJ -lt 10 ]; then
				printf "You must be running Debian 10 to install EOSIO, and resolve missing dependencies from unstable (sid).\n"
				printf "Exiting now.\n"
				exit 1
		fi
		;;
	esac

	if [ "${DISK_AVAIL%.*}" -lt "${DISK_MIN}" ]; then
		printf "You must have at least %sGB of available storage to install EOSIO.\\n" "${DISK_MIN}"
		printf "Exiting now.\\n"
		exit 1
	fi

	DEP_ARRAY=(clang-4.0 lldb-4.0 libclang-4.0-dev cmake make automake libbz2-dev libssl-dev \
	libgmp3-dev autotools-dev build-essential libicu-dev python2.7-dev python3-dev \
    autoconf libtool curl zlib1g-dev doxygen graphviz sudo)
	COUNT=1
	DISPLAY=""
	DEP=""

	if [[ "${ENABLE_CODE_COVERAGE}" == true ]]; then
		DEP_ARRAY+=(lcov)
	fi

	printf "\\nDo you wish to update repositories with apt-get update?\\n\\n"
	select yn in "Yes" "No"; do
		case $yn in
			[Yy]* ) 
				printf "\\n\\nUpdating...\\n\\n"
				if ! sudo apt-get update; then
					printf "\\nAPT update failed.\\n"
					printf "\\nExiting now.\\n\\n"
					exit 1;
				else
					printf "\\nAPT update complete.\\n"
				fi
			break;;
			[Nn]* ) echo "Proceeding without update!";;
			* ) echo "Please type 1 for yes or 2 for no.";;
		esac
	done

	printf "\\nChecking for installed dependencies.\\n\\n"

	for (( i=0; i<${#DEP_ARRAY[@]}; i++ ));
	do
		pkg=$( dpkg -s "${DEP_ARRAY[$i]}" 2>/dev/null | grep Status | tr -s ' ' | cut -d\  -f4 )
		if [ -z "$pkg" ]; then
			DEP=$DEP" ${DEP_ARRAY[$i]} "
			DISPLAY="${DISPLAY}${COUNT}. ${DEP_ARRAY[$i]}\\n"
			printf "Package %s ${bldred} NOT ${txtrst} found.\\n" "${DEP_ARRAY[$i]}"
			(( COUNT++ ))
		else
			printf "Package %s found.\\n" "${DEP_ARRAY[$i]}"
			continue
		fi
	done		

	if [ "${COUNT}" -gt 1 ]; then
		printf "\\nThe following dependencies are required to install EOSIO.\\n"
		printf "\\n${DISPLAY}\\n\\n" 
		printf "Do you wish to install these packages?\\n"
		select yn in "Yes" "No"; do
			case $yn in
				[Yy]* ) 
					printf "\\n\\nInstalling dependencies\\n\\n"
					if ! sudo apt-get -y install ${DEP}
					then
						printf "\\nDPKG dependency failed.\\n"
						printf "\\nExiting now.\\n"
						exit 1
					else
						printf "\\nDPKG dependencies installed successfully.\\n"
					fi
				break;;
				[Nn]* ) echo "User aborting installation of required dependencies, Exiting now."; exit;;
				* ) echo "Please type 1 for yes or 2 for no.";;
			esac
		done
	else 
		printf "\\nNo required dpkg dependencies to install."
	fi


	printf "\\n"


	printf "Checking CMAKE installation...\\n"
	CMAKE=$(command -v cmake 2>/dev/null)
    if [ -z $CMAKE ]; then
		printf "Installing CMAKE...\\n"
		curl -LO https://cmake.org/files/v$CMAKE_VERSION_MAJOR.$CMAKE_VERSION_MINOR/cmake-$CMAKE_VERSION.tar.gz \
    	&& tar xf cmake-$CMAKE_VERSION.tar.gz \
    	&& cd cmake-$CMAKE_VERSION \
    	&& ./bootstrap \
    	&& make -j$( nproc ) \
    	&& make install \
    	&& cd .. \
    	&& rm -f cmake-$CMAKE_VERSION.tar.gz
		printf " - CMAKE successfully installed @ ${CMAKE}.\\n"
	else
		printf " - CMAKE found @ ${CMAKE}.\\n"
	fi


	printf "\\n"


	printf "Checking Boost library (${BOOST_VERSION}) installation...\\n"
    if [ ! -d $BOOST_ROOT ]; then
		printf "Installing Boost library...\\n"
		curl -LO https://dl.bintray.com/boostorg/release/$BOOST_VERSION_MAJOR.$BOOST_VERSION_MINOR.$BOOST_VERSION_PATCH/source/boost_$BOOST_VERSION.tar.bz2 \
		&& tar -xf boost_$BOOST_VERSION.tar.bz2 \
		&& cd boost_$BOOST_VERSION/ \
		&& ./bootstrap.sh "--prefix=${SRC_LOCATION}/boost_${BOOST_VERSION}" \
		&& ./b2 -q -j$( nproc ) install \
		&& cd .. \
		&& rm -f boost_$BOOST_VERSION.tar.bz2 \
		&& rm -rf $HOME/opt/boost \
		&& ln -s $BOOST_ROOT $HOME/opt/boost
		printf " - Boost library successfully installed @ ${BOOST_ROOT}.\\n"
	else
		printf " - Boost library found with correct version @ ${BOOST_ROOT}.\\n"
	fi


	printf "\\n"


	printf "Checking MongoDB installation...\\n"
	# eosio_build.sh sets PATH with /opt/mongodb/bin
    if [ ! -e $MONGODB_CONF ]; then
		printf "Installing MongoDB...\\n"
		curl -OL http://downloads.mongodb.org/linux/mongodb-linux-x86_64-ubuntu$OS_MAJ$OS_MIN-$MONGODB_VERSION.tgz \
		&& tar -xzvf mongodb-linux-x86_64-ubuntu$OS_MAJ$OS_MIN-$MONGODB_VERSION.tgz \
		&& mv $SRC_LOCATION/mongodb-linux-x86_64-ubuntu$OS_MAJ$OS_MIN-$MONGODB_VERSION $MONGO_ROOT \
		&& mkdir $MONGO_ROOT/data \
		&& mkdir $MONGO_ROOT/log \
		&& touch $MONGO_ROOT/log/mongod.log \
		&& rm -f mongodb-linux-x86_64-ubuntu$OS_MAJ$OS_MIN-$MONGODB_VERSIONtgz \
		&& mv ${SOURCE_DIR}/scripts/mongod.conf $MONGO_ROOT/mongod.conf \
		&& mkdir -p /data/db \
		&& mkdir -p /var/log/mongodb
		printf " - MongoDB successfully installed @ ${MONGO_ROOT}.\\n"
	else
		printf " - MongoDB found with correct version @ ${MONGO_ROOT}.\\n"
	fi
	printf "Checking MongoDB C driver installation...\\n"
	if [ ! -d $MONGO_C_DRIVER_ROOT ]; then
		printf "Installing MongoDB C driver...\\n"
		curl -LO https://github.com/mongodb/mongo-c-driver/releases/download/$MONGO_C_DRIVER_VERSION/mongo-c-driver-$MONGO_C_DRIVER_VERSION.tar.gz \
		&& tar -xf mongo-c-driver-$MONGO_C_DRIVER_VERSION.tar.gz \
		&& cd mongo-c-driver-$MONGO_C_DRIVER_VERSION \
		&& mkdir -p cmake-build \
		&& cd cmake-build \
		&& cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local -DENABLE_BSON=ON -DENABLE_SSL=OPENSSL -DENABLE_AUTOMATIC_INIT_AND_CLEANUP=OFF -DENABLE_STATIC=ON .. \
		&& make -j$(nproc) \
		&& make install \
		&& cd ../.. \
		&& rm mongo-c-driver-$MONGO_C_DRIVER_VERSION.tar.gz
		printf " - MongoDB C driver successfully installed @ ${MONGO_C_DRIVER_ROOT}.\\n"
	else
		printf " - MongoDB C driver found with correct version @ ${MONGO_C_DRIVER_ROOT}.\\n"
	fi
	printf "Checking MongoDB C++ driver installation...\\n"
	if [ ! -d $MONGO_CXX_DRIVER_ROOT ]; then
		printf "Installing MongoDB C++ driver...\\n"
		git clone https://github.com/mongodb/mongo-cxx-driver.git --branch releases/v$MONGO_CXX_DRIVER_VERSION --depth 1 mongo-cxx-driver-$MONGO_CXX_DRIVER_VERSION \
		&& cd mongo-cxx-driver-$MONGO_CXX_DRIVER_VERSION/build \
		&& cmake -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local .. \
		&& make -j$(nproc) VERBOSE=1 \
		&& make install \
		&& cd ../..
		printf " - MongoDB C++ driver successfully installed @ ${MONGO_CXX_DRIVER_ROOT}.\\n"
	else
		printf " - MongoDB C++ driver found with correct version @ ${MONGO_CXX_DRIVER_ROOT}.\\n"
	fi


	printf "\\n"


	printf "Checking LLVM with WASM support...\\n"
	if [ ! -d $LLVM_CLANG_ROOT ]; then
		printf "Installing LLVM with WASM...\\n"
		git clone --depth 1 --single-branch --branch $LLVM_CLANG_VERSION https://github.com/llvm-mirror/llvm.git llvm-$LLVM_CLANG_VERSION \
		&& cd llvm-$LLVM_CLANG_VERSION/tools \
		&& git clone --depth 1 --single-branch --branch $LLVM_CLANG_VERSION https://github.com/llvm-mirror/clang.git clang-$LLVM_CLANG_VERSION \
		&& cd .. \
		&& mkdir build \
		&& cd build \
		&& cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX=.. -DLLVM_TARGETS_TO_BUILD= -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=WebAssembly -DLLVM_ENABLE_RTTI=1 -DCMAKE_BUILD_TYPE=Release .. \
		&& make -j1 \
		&& make install \
		&& cd ../.. \
		&& rm -f $HOME/opt/wasm \
		&& ln -s $LLVM_CLANG_ROOT $HOME/opt/wasm
		printf "WASM compiler successfully installed @ ${LLVM_CLANG_ROOT} (Symlinked to ${HOME}/opt/wasm)\\n"
	else
		printf " - WASM found @ ${LLVM_CLANG_ROOT} (Symlinked to ${HOME}/opt/wasm).\\n"
	fi


	cd ..
	printf "\\n"

	function print_instructions()
	{
		printf "$( command -v mongod ) -f ${MONGODB_CONF} &\\n"
		printf "Ensure ${MONGO_ROOT}/bin is in your \$PATH \\n"
		printf "cd ${BUILD_DIR}; make test\\n\\n"
	return 0
	}
