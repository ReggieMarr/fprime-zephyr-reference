#!/bin/bash
export SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd -P)"
cd "$SCRIPT_DIR"
source .env
set -e
set -o pipefail
# set -o nounset

export ZEPHYR_IMG_BASE=${ZEPHYR_IMG_BASE:-$ZEPHYR_URL}
export ZEPHYR_IMG_TAG=${ZEPHYR_IMG_TAG:-fsw_$(git rev-parse --abbrev-ref HEAD | sed 's/\//_/g')}
export ZEPHYR_IMG="$ZEPHYR_IMG_BASE:$ZEPHYR_IMG_TAG"

check_port() {
    local port=$1
    if netstat -ano | grep ":$port "; then
        echo "Port $port is in use. Checking its state..."
        if netstat -ano | grep ":$port.*TIME_WAIT"; then
            echo "Port $port is in TIME_WAIT state. Wait $(cat /proc/sys/net/ipv4/tcp_fin_timeout) seconds, or use a different port."
        else
            echo "Port $port is actively in use by another process. Use lsof -i :$port to find the process."
        fi
        return 1
    fi
    return 0
}

find_board_port() {
    local port=""
    case "$OSTYPE" in
        darwin*) port=$(ls /dev/cu.usbmodem* 2>/dev/null | head -n 1) ;;
        linux*)  port=$(ls /dev/ttyACM* 2>/dev/null | head -n 1) ;;
        *) echo "Unsupported OS for automatic port detection"; return 1 ;;
    esac

    if [ -z "$port" ]; then
        echo "Board port ($port) not found."
        return 1
    fi

    echo "$port"
}

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS] COMMAND
Options:
  --clean              Clean build
  --daemon             Run as daemon
  --debug              Run using gdb/gdbserver
  --standalone         Run the command without starting any implied dependencies
  --logs               To be used with the inspect command, just polls for logs from the assumed to be running container
  --help               Show this help message
Commands:
  mbd-to-xml           Convert MBD to XML
  build base           Build the base application
  build docker         Build the Docker image
  exec test            Run the yamcs studio editor
  inspect              Inspect the development container
  teardown             Tear down the environment
EOF
}

# Default values
DEFAULT_SERVICE="zephyr"
DEFAULT_FLAGS="-it"
BASE_FLAGS="--rm --user $(id -u):$(id -g) --remove-orphans"
CLEAN=0
DEBUG=0
STANDALONE=0
DAEMON=0
LOGS=0

# Process flags
for arg in "$@"; do
    case $arg in
        --daemon) DAEMON=1 ;;
        --clean) CLEAN=1 ;;
        --debug) DEBUG=1 ;;
        --logs) LOGS=1 ;;
        --standalone) STANDALONE=1 ;;
        --help) show_help; exit 0 ;;
    esac
done

exec_cmd() {
    local cmd="${1}"
    echo "Executing: $cmd"
    eval "$cmd"
    exit_code=$?
    if [ $exit_code -eq 1 ] || [ $exit_code -eq 2 ]; then
        echo "Failed cmd with error $exit_code"
        exit $exit_code;
    fi
}

run_docker_compose() {
    local service="$1"
    local cmd="$2"
    # Always kill the container after executing the command
    # by default run the command with an interactive tty
    local flags="$BASE_FLAGS ${3:$DEFAULT_FLAGS}"

    if [ "${DAEMON}" -eq "1" ]; then
        flags="${flags//-it/}"   # Remove standalone "-it"

        flags+=" --detach"
    fi

    [ "$STANDALONE" -eq 1 ] && flags="--no-deps"

    exec_cmd "docker compose run $flags $service $cmd"
}

try_docker_exec() {
    local service="$1"
    local cmd="$2"
    local container_name="fprime-${service}"  # assuming your container naming convention
    local flags="$3"

    # Check if container is running
    if docker container inspect "$container_name" >/dev/null 2>&1; then
        echo "Container $container_name is running, using docker exec..."
        exec_cmd "docker exec $flags $container_name $cmd"
    else
        echo "Container $container_name is not running, using docker compose run..."
        run_docker_compose "$service" "$cmd" "$flags"
    fi
}

try_stop_container() {
  local container_name="$1"
  local timeout=${2:-10}  # default 10 seconds timeout

  if docker container inspect "$container_name" >/dev/null 2>&1; then
      echo "Stopping container $container_name (timeout: ${timeout}s)..."
      if ! docker container stop -t "$timeout" "$container_name"; then
          echo "Failed to stop container $container_name gracefully"
          return 1
      fi
      echo "Container $container_name stopped successfully"
  else
      echo "Container $container_name is not running"
  fi
}

build_docker() {
  if ! git diff-index --quiet HEAD --; then
      read -p "You have unstaged changes. Continue? (y/n) " -n 1 -r
      echo
      [[ $REPLY =~ ^[Yy]$ ]] || { echo "Build cancelled."; exit 1; }
  fi

  # Fetch from remote to ensure we have latest refs
  git fetch -q origin

  # Get current commit hash
  CURRENT_COMMIT=$(git rev-parse HEAD)

  # Check if current commit exists in any remote branch
  if ! git branch -r --contains "$CURRENT_COMMIT" | grep -q "origin/"; then
      read -p "Current commit not found in remote repository. Continue? (y/n) " -n 1 -r
      echo
      [[ $REPLY =~ ^[Yy]$ ]] || { echo "Build cancelled."; exit 1; }
  fi

  CMD="docker compose --progress=plain --env-file=${SCRIPT_DIR}/.env build zephyr"
  [ "$CLEAN" -eq 1 ] && CMD+=" --no-cache"
  CMD+=" --build-arg GIT_COMMIT=$(git rev-parse HEAD) --build-arg GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)"
  exec_cmd "$CMD"
}

update_build_env() {
  build_json_path=$1
  clangd_cmd="sed -i \"s|CompilationDatabase: .*|CompilationDatabase: \"${build_json_path}\"|\" .clangd"
  exec_cmd "$clangd_cmd"

  mod_dict_cmd="sed -i \"s|${ZEPHYR_WDIR}|${SCRIPT_DIR}|g\" \"${build_json_path}/compile_commands.json\""

  exec_cmd "$mod_dict_cmd"
}

build_cmsis_st() {
    cmsis_path="fprime-cmsis/cmake/toolchain/support/sources/zephyrv71q21b"
    flags="-w $ZEPHYR_WDIR/$cmsis_path $DEFAULT_FLAGS"
    # NOTE we often get stuck on trivial schema errors.
    # prevent this with -n
    # cmd="csolution -v -d convert blinky.csolution.yml"
    # cmd="cbuild -v -p blinky.csolution.yml"
    # cmd="cbuild setup blinky.csolution.yml --context-set"
    cmd="cbuild blinky.csolution.yml -d --context-set --packs --rebuild"
    try_docker_exec "zephyr" "bash -c \"$cmd\"" "$flags"

    update_build_env "${SCRIPT_DIR}/${cmsis_path}/out/blinky/ZephyrV71-Xplained-Board/Debug"
}

build_zephyr_st() {
    zephyr_path="zephyr-test/smoketest/"
    flags="-w $ZEPHYR_WDIR/$zephyr_path $DEFAULT_FLAGS"

    cmd="west build -b zephyr_v71_xult/zephyrv71q21b "
    [ "$CLEAN" -eq 1 ] && cmd+="-t pristine -p always "

    cmd+="${ZEPHYR_WDIR}/${zephyr_path}"

    try_docker_exec "zephyr" "bash -c \"$cmd\"" "$flags"

    update_build_env "${SCRIPT_DIR}/${zephyr_path}build"
}

build_ledblinker_st() {
    zephyr_path="build"
    flags="-w $ZEPHYR_WDIR/$zephyr_path $DEFAULT_FLAGS"

    gen_cmd="cmake .. -GNinja -B /fprime-zephyr-reference/build -DBOARD=sam_v71_xult -DBOARD_QUALIFIERS=/samv71q21"
    build_cmd="cmake --build /fprime-zephyr-reference/build --target zephyr_final -- -v"
    cmd=$build_cmd
    [ "$CLEAN" -eq 1 ] && cmd="rm ../build/* -rf && ${gen_cmd} && ${build_cmd}"

    try_docker_exec "zephyr" "bash -c \"$cmd\"" "$flags"

    update_build_env "${SCRIPT_DIR}/build"
}

case $1 in
  "format")
    if [[ "$2" == *.fpp ]]; then
      container_file="${2/$SCRIPT_DIR/$ZEPHYR_WDIR}"
      echo "Formatting FPP file: $container_file"
      cmd="fpp-format $container_file"
      # Create a temporary marker that's unlikely to appear in normal code
      marker="@ COMMENT_PRESERVE@"
      # Chain the commands:
      # 1. Transform comments to temporary annotations
      # 2. Run fpp-format
      # 3. Transform back to comments
      # 4. Write back to the original file
    tmp_file="${container_file/.fpp/_tmp.fpp}"

    # Create a multi-line command with error checking
    read -r -d '' cmd <<EOF
    set -e  # Exit on any error

    # Create backup
    cp "$container_file" "${container_file}.bak"

    # Attempt formatting pipeline
    if sed 's/^\\([ ]*\\)#/\\1${marker}#/' "$container_file" \
       | fpp-format \
       | sed 's/^\\([ ]*\\)${marker}#/\\1#/' > "$tmp_file"; then

        # If successful, verify tmp file exists and has content
        if [ -s "$tmp_file" ]; then
            mv "$tmp_file" "$container_file"
            rm "${container_file}.bak"
            echo "Format successful"
        else
            echo "Error: Formatted file is empty"
            mv "${container_file}.bak" "$container_file"
            exit 1
        fi
    else
        echo "Error during formatting"
        mv "${container_file}.bak" "$container_file"
        [ -f "$tmp_file" ] && rm "$tmp_file"
        exit 1
    fi
EOF
      flags="-w $ZEPHYR_WDIR $DEFAULT_FLAGS"
      try_docker_exec "zephyr" "$cmd" "$flags"
    else
      fprime_root="${2:-$SCRIPT_DIR/deps/fprime}"  # Get the path provided or use current directory
      fprime_root="${fprime_root/$SCRIPT_DIR/$ZEPHYR_WDIR}"
      echo "Formatting from $fprime_root"
      cmd="git diff --name-only --relative | fprime-util format --no-backup --stdin"
      try_docker_exec "zephyr" "bash -c \"$cmd\""
    fi
    ;;

  "build")
    EXEC_TARGET=${2:-}
    [ -z "$EXEC_TARGET" ] && { echo "Error: must specify target to exec"; exit 1; }

    case $EXEC_TARGET in
      "zephyr-st")
        build_zephyr_st
      ;;
      "LedBlinker")
        build_ledblinker_st
      ;;
      "docker")
        build_docker
      ;;
      "test")
        echo "Not yet supported"
        exit 1
      ;;
      *)
      echo "Invalid exec command: ${EXEC_TARGET}"
      exit 1
      ;;
    esac
    ;;

  "load")
    EXEC_TARGET=${2:-}
    [ -z "$EXEC_TARGET" ] && { echo "Error: must specify target to exec"; exit 1; }

    case $EXEC_TARGET in
      "cmsis-st")
        # Stands for cmsis smoketest
        bin_path="./fprime-cmsis/cmake/toolchain/support/sources/zephyrv71q21b/out/blinky/ZephyrV71-Xplained-Board/Debug/blinky.elf"
        debug_cmd="pyocd gdbserver --elf ${bin_path} -t atzephyrv71q21b"
        load_cmd="pyocd load ${bin_path} -t atsamv71q21b"

        [ "$DEBUG" -eq 1 ] && load_cmd+=" && $debug_cmd"

        export HOST_DEVICE_PORT=$(find_board_port) || exit 1

        run_docker_compose "zephyr-tty" "bash -c \"${load_cmd}\""
      ;;
      *)
      echo "Invalid operation."
      exit 1
      ;;
    esac
    ;;

  "exec")
    EXEC_TARGET=${2:-}
    [ -z "$EXEC_TARGET" ] && { echo "Error: must specify target to exec"; exit 1; }

    case $EXEC_TARGET in
      "keil-cfg")
        keil_exec "uv"
      ;;
      "mplab-cfg")
        mplab_exec "mplab_ide"
      ;;
      "debug-cmsis-st")
        bin_path="./fprime-cmsis/cmake/toolchain/support/sources/zephyrv71q21b/out/blinky/ZephyrV71-Xplained-Board/Debug/blinky.elf"
        debug_cmd="pyocd gdbserver --elf ${bin_path} -t atzephyrv71q21b"

        export HOST_DEVICE_PORT=$(find_board_port) || exit 1
        run_docker_compose "zephyr-tty" "bash -c \"${debug_cmd}\""
      ;;
      "base")
        echo "Not yet supported"
        exit 1
      ;;
      "test")
        echo "Not yet supported"
        exit 1
      ;;
      *)
      echo "Invalid operation."
      exit 1
      ;;
    esac
    ;;

    "inspect")
        INSPECT_TARGET=${2:-}
        [ -z "$INSPECT_TARGET" ] && { echo "Error: must specify target to inspect"; exit 1; }
        case $INSPECT_TARGET in
            "wine")
              wine_exec "bash"
          ;;
            "mplab")
              # Fall through, all these case are the zephyre.
          ;&
            "zephyr")
              if [ "$LOGS" -eq 1 ]; then
                  exec_cmd "docker compose logs -f ${INSPECT_TARGET}"
              else
                try_docker_exec $INSPECT_TARGET "bash" "-it"
              fi
          ;;
            "zephyr-tty")
              export HOST_DEVICE_PORT=$(find_board_port) || exit 1
              if [ "$LOGS" -eq 1 ]; then
                  exec_cmd "docker compose logs -f ${INSPECT_TARGET}"
              else
                try_docker_exec $INSPECT_TARGET "bash" "-it"
              fi
          ;;
          *)
          echo "Invalid inspect target: ${INSPECT_TARGET}"
          exit 1
          ;;
        esac
        ;;
    "teardown")
        echo "Tearing down services..."
        exec_cmd "docker compose down"
        ;;
    *)
        echo "Invalid operation. Not a valid run.sh argument."
        show_help
        exit 1
        ;;
esac
