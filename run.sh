#!/bin/bash
export SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd -P)"
cd "$SCRIPT_DIR"
source .env
set -e
set -o pipefail
# set -o nounset

export HOST_GID=$(id -g $(id -g -n))
export HOST_UID=$(id -u $(whoami))

export ZEPHYR_IMG_BASE=${ZEPHYR_IMG_BASE:-$ZEPHYR_URL}
export ZEPHYR_IMG_TAG=${ZEPHYR_IMG_TAG:-fsw_$(git rev-parse --abbrev-ref HEAD | sed 's/\//_/g')}
export ZEPHYR_IMG="$ZEPHYR_IMG_BASE:$ZEPHYR_IMG_TAG"
DEFAULT_SVC="zephyr"

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
    else
        echo "Found $port"
    fi

    echo "$port"
}

BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] COMMAND [ARGS]

Options:
  --daemon                           Run containers in detached mode (remove interactive TTY).
  --verbose                          Run command with verbose logs enabled.
  --debug                            Enable debug-related configurations (such as gdb).
  --force                            Force start, run, provision, deploy ect.
  --as-host                          Execute command on the host instead of within Docker.
  --clean                            Force cleaning of build directories or caches
                                     (e.g., rebuild sources from scratch).
  --local                            Run related command in such a way that doesn't
                                     rely on network/remote resources.
  --host-thread-ctrl                 Enable non-sudo thread control for host execution (requires sudo)
  --help                             Display this help message.

Commands:
  pull                               Retrieve the latest source code and docker image using ${BRANCH_NAME}.
  push                               Update remote servers with the local code and dockerfile ${BRANCH_NAME}.
  build <target>                     Builds a target component, specified by the second argument.
                                     Note the following example build targets:
                                     fsw           Build the Flight Software application
                                     docker        Build the Docker image

  exec <target>                      Executes a target inside the container specified by the second argument.
                                     Note the following example build targets:
                                     fsw                  Run the Flight Software application
                                     gds                  Launch the Flight Software Ground Data System (GDS)
                                     ut [component dir]   Leverages fprime-util generate/check to build/run
                                                          unit tests against a specified component.
  deploy                             Deploy a target to some execution environment.
                                     fsw                  Deploy the Flight Software application
                                     gds                  Deploy the Ground Data System (GDS)

  log <target> <target deployment>   Displays logs for a specific target. The second argument specifies the target:
                                     fsw                  Display logs for the Flight Software application
                                     gds                  Display logs for the Ground Data System (GDS)

  inspect                Opens an interactive shell (bash) inside the default service container.

Examples:
  "./run.sh" build fsw --clean
  "./run.sh" exec fsw --daemon
EOF
}

CLEAN=0
AS_HOST=0
DAEMON=0
DEBUG=0
LOCAL=0
VERBOSE=0
SET_THREAD_CTRL=0
FORCE=0

POSITIONAL_ARGS=()

# gets flags and removes them from the argument list with shift
# positional args retains non-flag arguments
for arg in "$@"; do
  case $arg in
    --daemon)
      DAEMON=1
      shift
      ;;
    --verbose)
      VERBOSE=1
      shift
      ;;
    --debug)
      DEBUG=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --as-host)
      AS_HOST=1
      shift
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    --host-thread-ctl)
      SET_THREAD_CTRL=1
      shift
      ;;
    --local)
      LOCAL=1
      shift
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save it in an array for later
      shift # Remove generic argument from processing
      ;;
  esac
done

# restore positional parameters
set -- "${POSITIONAL_ARGS[@]}"

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
    local container_name="devenv-${service}"  # assuming your container naming convention
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

repo_check() {
    echo "Running repo check"
    # Check for unstaged or uncommitted changes in the fprime submodule
    local repo_target=$1
    if [ -z "$repo_target" ] || [ ! -d $repo_target ]; then
       printf "Error: Invalid submodule target: $repo_target \n"
       exit 1;
    fi
    local starting_dir=$(pwd)

    cd $repo_target
    # Check if there are any modifications (unstaged/staged changes)
    if ! git diff-index --quiet HEAD --; then
      read -p "$repo_target has unstaged changes. Continue? (y/n) " -n 1 -r
      echo
      [[ $REPLY =~ ^[Yy]$ ]] || { echo "Build cancelled."; exit 1; }
    fi

    # Retrieve the current commit hash in the submodule
    local current_commit=$(git rev-parse HEAD)

    # Check if the commit exists on the remote by listing all remote refs and searching for the commit
    if ! git ls-remote origin | grep -q "$current_commit"; then
      read -p "$repo_target commit ${current_commit} not found in remote repository. Continue? (y/n) " -n 1 -r
      echo
      [[ $REPLY =~ ^[Yy]$ ]] || { echo "Build cancelled."; exit 1; }
    fi

    cd $starting_dir
}

retrieve_requirements_from_remote() {
    if ! repo_check "$SCRIPT_DIR/fprime"; then
      printf "Failed to validate fprime submodule\n"
      exit 1
    fi
    # Fetch from remote to ensure we have latest refs
    exec_cmd "git fetch -q origin"
    # Get current commit hash
    local fsw_commit=$(git rev-parse HEAD)
    printf "Retrieving fprime commit via GitHub REST API with curl...\n"

    # Extract the repo owner and name from the remote URL
    local github_baseurl="github.com"
    local fsw_project_path=$(git remote get-url origin | sed -nE "s/.*(${github_baseurl})[:/](.*)\.git/\2/p")

    # Get the submodule commit hash using the GitHub API
    # First, we need to get the .gitmodules content to find the path to the submodule
    local submodule_url="https://api.github.com/repos/${fsw_project_path}/contents/.gitmodules?ref=${fsw_commit}"
    local curl_cmd="curl -s \"${submodule_url}\""
    local gitmodules_content=$(eval $curl_cmd | jq -r '.content' | base64 -d)

    # Extract the fprime submodule path and URL
    local fprime_path=$(echo "$gitmodules_content" | grep -A3 '\[submodule "fprime"\]' | grep 'path' | cut -d'=' -f2 | tr -d ' ')
    local fprime_url=$(echo "$gitmodules_content" | grep -A3 '\[submodule "fprime"\]' | grep 'url' | cut -d'=' -f2 | tr -d ' ')

    # Get the commit hash of the submodule
    local submodule_status_url="https://api.github.com/repos/${fsw_project_path}/contents/${fprime_path}?ref=${fsw_commit}"
    local fprime_commit=$(curl -s "${submodule_status_url}" | jq -r '.sha')

    # Extract the owner and repo name from the fprime URL
    local fprime_project=$(echo "$fprime_url" | sed -nE "s/.*(${github_baseurl})[:/](.*)\.git/\2/p")

    # Now generate a URL which requests the requirements.txt from the fprime repo
    local requirements_url="https://api.github.com/repos/${fprime_project}/contents/requirements.txt?ref=${fprime_commit}"

    # Download the requirements file
    local cmd="curl -s \"${requirements_url}\" | jq -r '.content' | base64 -d > $SCRIPT_DIR/.tmp/fprime_requirements.txt"
    exec_cmd "$cmd"
}

retrieve_requirements_from_local() {
    # Alternatively we could get the submodule commit from our local copy of the
    # fprime submodule however this would be less "purely local" so doesn't quiet match the DWIM ethos
    requirements_dir=${1:fprime}
    requirements_path="${SCRIPT_DIR}/${requirements_dir}/requirements.txt"
    local cmd="cp $requirements_path $SCRIPT_DIR/.tmp/fprime_requirements.txt"
    exec_cmd "$cmd"
}

build_docker() {
    # Dependending on our config we either want to get the requirements url by probing remote servers
    # or by finding the file locally
    if [ $LOCAL -eq 1 ]; then
      retrieve_requirements_from_local "fprime"
    else
      retrieve_requirements_from_remote
    fi

    local build_cmd="docker compose --progress=plain --env-file=${SCRIPT_DIR}/.env build zephyr"

    [ "$CLEAN" -eq 1 ] && build_cmd+=" --no-cache"

    build_cmd+=" --build-arg FSW_WDIR=${ZEPHYR_WDIR} --build-arg HOST_UID=$HOST_UID --build-arg HOST_GID=$HOST_GID"
    exec_cmd "$build_cmd; rm -f tmp_requirements.txt"
}

container_to_host_paths() {
  host_path=$1
  container_path=$2
  build_json_path=$3
  clangd_cmd="sed -i \"s|CompilationDatabase: .*|CompilationDatabase: \"${build_json_path}\"|\" .clangd"
  exec_cmd "$clangd_cmd"

  mod_dict_cmd="sed -i \"s|${host_path}|${container_path}|g\" \"${build_json_path}/compile_commands.json\""

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

    container_to_host_path "${SCRIPT_DIR}/${cmsis_path}/out/blinky/ZephyrV71-Xplained-Board/Debug"
}

build_zephyr_st() {
    zephyr_path="zephyr-test/smoketest/"
    flags="-w $ZEPHYR_WDIR/$zephyr_path $DEFAULT_FLAGS"

    cmd="west build -b zephyr_v71_xult/zephyrv71q21b "
    [ "$CLEAN" -eq 1 ] && cmd+="-t pristine -p always "

    cmd+="${ZEPHYR_WDIR}/${zephyr_path}"

    try_docker_exec "zephyr" "bash -c \"$cmd\"" "$flags"

    container_to_host_path "${SCRIPT_DIR}/${zephyr_path}build"
}

build_ledblinker() {
    zephyr_path="build"
    flags="-w $ZEPHYR_WDIR/$zephyr_path $DEFAULT_FLAGS"

    sam_board_info="-DBOARD=sam_v71_xult -DBOARD_QUALIFIERS=/samv71q21b"
    gen_cmd="cmake -S ${ZEPHYR_WDIR} -GNinja -B ${ZEPHYR_WDIR}/build ${sam_board_info}"
    # build_cmd="cmake --build /fprime-zephyr-reference/build --target zephyr_final"
    # this is essentially the equivalent
    build_cmd="ninja zephyr_final"
    cmd=$build_cmd
    [ "$CLEAN" -eq 1 ] && cmd="rm ../build/* -rf && ${gen_cmd} && ${build_cmd}"

    # cmd="ls /fprime-zephyr-reference/zephyr"
    # try_docker_exec "zephyr" "bash -c \"$cmd\"" "$flags"
    run_docker_compose "zephyr" "bash -c \"$cmd\"" "$flags"

    container_to_host_path "${SCRIPT_DIR}/build"
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
        build_ledblinker
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
      "LedBlinker")
        # Stands for cmsis smoketest
        flags="-w $ZEPHYR_WDIR/$zephyr_path $DEFAULT_FLAGS"
        debug_cmd="west gdbserver --skip-rebuild"
        load_cmd="west flash --skip-rebuild"

        [ "$DEBUG" -eq 1 ] && load_cmd+=" && $debug_cmd"

        export HOST_DEVICE_PORT=$(find_board_port) || exit 1

        run_docker_compose "zephyr-tty" "bash -c \"${load_cmd}\"" "$flags"
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
      "console")
        #NOTE the gds port is not the debug port, if incorrectly selected the serial output will appear garbled (serial_)
        console_port=${3:-"/dev/ttyACM1"}
        # use -o to let the device dict comms settings
        cmd="minicom -D $console_port -o"
        flags="-it"
        try_docker_exec "zephyr-tty" "bash -c \"$cmd\"" "$flags"

        echo "Not yet supported"
        exit 1
      ;;
      "env")
        container_to_host_path "${SCRIPT_DIR}/build"
      ;;
      "gds")
        #NOTE the gds port is not the debug port, if incorrectly selected the serial output will appear garbled (see exec console output)
        gds_port=${3:-"/dev/ttyACM0"}
        baud="115200"
        dict_path="${ZEPHYR_WDIR}/build/LedBlinker/Top/LedBlinkerTopologyDictionary.json"
        cmd="fprime-gds --dictionary ${dict_path} --uart-device ${gds_port} --uart-baud ${baud} --communication-selection uart -n"
        flags="-it"
        try_docker_exec "zephyr-tty" "bash -c \"$cmd\"" "$flags"

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
              # export HOST_DEVICE_PORT=$(find_board_port) || exit 1
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
