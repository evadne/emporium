PRIV_DIR = priv
EXECUTABLE = $(PRIV_DIR)/runner
CMAKE_BUILD_FLAGS = --verbose
CMAKE_BUILD_DIR := $(shell mktemp -d)
SRC_DIR = $(shell pwd)/c_src
C_SOURCES = $(wildcard $(SRC_DIR)/*.c)
CC_SOURCES = $(wildcard $(SRC_DIR)/*.cc)

ifdef CMAKE_TOOLCHAIN_FILE
	CMAKE_CONFIGURE_FLAGS=-DCMAKE_TOOLCHAIN_FILE="$(CMAKE_TOOLCHAIN_FILE)"
endif

.DEFAULT_GLOBAL := build

build: check $(EXECUTABLE)

check:
	@ if [ ! -d "$(LIBTORCH_INSTALL_DIR)" ]; then \
		echo "LIBTORCH_INSTALL_DIR should point to an installation of libTorch"; \
		exit 1; \
	fi
	@ if [ ! -d "$(ERL_INTERFACE_LIB_DIR)" ] || [ ! -d "$(ERL_INTERFACE_INCLUDE_DIR)" ]; then \
		echo "ERL_INTERFACE_LIB_DIR and ERL_INTERFACE_INCLUDE_DIR should be set"; \
		exit 1; \
	fi
	@ if [ ! -d "$(ERTS_INCLUDE_DIR)" ]; then \
		echo "ERTS_INCLUDE_DIR should be set"; \
		exit 1; \
	fi

clean:
	rm -rf $(PRIV_DIR)/install
	rm -rf $(EXECUTABLE)

$(EXECUTABLE): CMakeLists.txt $(C_SOURCES) $(CC_SOURCES)
	@ mkdir -p $(PRIV_DIR)
	@ if [ "${MIX_BUILD_EMBEDDED}" = "true" ]; then \
		cp -a $(abspath $(LIBTORCH_INSTALL_DIR)/lib) $(PRIV_DIR)/install ; \
	else \
		ln -sf $(abspath $(LIBTORCH_INSTALL_DIR)/lib) $(PRIV_DIR)/install ; \
	fi
	@ cd $(CMAKE_BUILD_DIR) && \
		cmake \
			-DCMAKE_PREFIX_PATH=$(LIBTORCH_INSTALL_DIR) \
			-DSRC_DIR=$(SRC_DIR) \
			-DERTS_INCLUDE_DIR=$(ERTS_INCLUDE_DIR) \
			-DERL_INTERFACE_LIB_DIR=$(ERL_INTERFACE_LIB_DIR) \
			-DERL_INTERFACE_INCLUDE_DIR=$(ERL_INTERFACE_INCLUDE_DIR) \
			-S $(shell pwd) $(CMAKE_CONFIGURE_FLAGS) && \
		cmake --build . $(CMAKE_BUILD_FLAGS)
	@ mv $(CMAKE_BUILD_DIR)/runner $(EXECUTABLE)
