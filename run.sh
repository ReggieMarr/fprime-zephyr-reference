#!/bin/bash
export SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd -P)"
cd "$SCRIPT_DIR"
source .env
set -e
set -o pipefail

export HOST_GID=$(id -g $(id -g -n))
export HOST_UID=$(id -u $(whoami))

export ZEPHYR_IMG_BASE=${ZEPHYR_IMG_BASE:-$ZEPHYR_URL}
export ZEPHYR_IMG_TAG=${ZEPHYR_IMG_TAG:-fsw_$(git rev-parse --abbrev-ref HEAD | sed 's/\//_/g')}
export ZEPHYR_IMG="$ZEPHYR_IMG_BASE:$ZEPHYR_IMG_TAG"

# For some commands we don't really care which service is used, for these just use "zephyr"
DEFAULT_SVC="zephyr"
# The base flags ensures that containers are run with the following:
# deleted after use or exit, run the user with the id and gid of the host user
# also remove dead containers from previous sessions (if for some reason they exist)
BASE_FLAGS="--rm --user $(id -u):$(id -g) --remove-orphans"

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

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] COMMAND [ARGS]

Options:
  --daemon                           Run containers in detached mode (remove interactive TTY).
  --verbose                          Run command with verbose logs enabled.
  --debug                            Enable debug-related configurations (such as gdb).
  --clean                            Force cleaning of build directories or caches
                                     (e.g., rebuild sources from scratch).
  --local                            Run related command in such a way that doesn't
                                     rely on network/remote resources.
  --help                             Display this help message.

Commands:
  pull                               Retrieve the latest source code and docker image for this branch ($(git rev-parse --abbrev-ref HEAD)).
  build <target>                     Builds a target component, specified by the second argument.
                                     Note the following example build targets:
                                     BaseDeployment Build the F' BaseDeployment application
                                     docker         Build the Docker image

  exec <target>                      Executes a target inside the container specified by the second argument.
                                     Note the following example build targets:
                                     fsw                  Run the Flight Software application
                                     gds                  Launch the Flight Software Ground Data System (GDS)
  deploy                             Deploy a target to some execution environment.
                                     fsw                  Deploy the Flight Software application
                                     gds                  Deploy the Ground Data System (GDS)

  inspect                Opens an interactive shell (bash) inside the default service container.

Examples:
  "./run.sh" build fsw --clean
  "./run.sh" exec fsw --daemon
EOF
}

CLEAN=0
DAEMON=0
DEBUG=0
LOCAL=0
VERBOSE=0

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
    --clean)
      CLEAN=1
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
    local flags="$BASE_FLAGS $3"

    if [ "${DAEMON}" -eq "1" ]; then
        flags="${flags//-it/}"   # Remove standalone "-it"

        flags+=" --detach"
    fi

    exec_cmd "docker compose run --name devenv-$service $flags $service $cmd"
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

fetch_requirements_file() {
    local repo=$1
    local commit=$2
    local file_path=$3
    local temp_dir=$4

    echo "Fetching requirements file: $file_path"

    # Generate URL for the requirements file
    local req_url="https://api.github.com/repos/${repo}/contents/${file_path}?ref=${commit}"

    # Create a unique name for this response file
    local req_response="${temp_dir}/$(basename ${file_path}).json"

    # Fetch the file
    exec_cmd "curl -s -L \"${req_url}\" > \"${req_response}\""

    # Check for errors
    local file_error=$(jq -r '.message // empty' "${req_response}")
    if [ ! -z "$file_error" ]; then
        echo "WARNING: Could not fetch ${file_path}: ${file_error}"
        return 1
    fi

    # Decode the content
    local file_content=$(jq -r '.content // "No content found"' "${req_response}" | base64 -d 2>/dev/null)

    # Process each line of the requirements file
    while IFS= read -r line; do
        # Check if this line is a reference to another requirements file
        if [[ "$line" =~ ^-r[[:space:]]+([^[:space:]]+) ]]; then
            # Extract the referenced file path
            local ref_file="${BASH_REMATCH[1]}"
            # Get the directory of the current file
            local current_dir=$(dirname "$file_path")
            # Construct the full path to the referenced file
            local ref_path="${current_dir}/${ref_file}"
            # Recursively fetch the referenced file
            fetch_requirements_file "$repo" "$commit" "$ref_path" "$temp_dir"
        else
            # If it's a normal requirement line, output it
            echo "$line" >> "${temp_dir}/combined_requirements.txt"
        fi
    done <<< "$file_content"
}

retrieve_remote_requirements() {
    local local_submodule_path=$1
    local remote_requirements_path=$2
    local temp_dir_path=$3

    if ! repo_check "$local_submodule_path"; then
      printf "Failed to validate fprime submodule\n"
      exit 1
    fi

    # Fetch from remote to ensure we have latest refs
    exec_cmd "git fetch -q origin"
    # Get current commit hash
    local fsw_repo_commit=$(git rev-parse HEAD)
    printf "Retrieving requirements for submodule '${local_submodule_path}' via GitHub REST API...\n"

    # Extract the repo owner and name from the remote URL
    local github_baseurl="github.com"
    local fsw_project_path=$(git remote get-url origin | sed -nE "s/.*(${github_baseurl})[:/](.*)\.git/\2/p")

    # Get the .gitmodules content - add -L flag to follow redirects
    local submodule_url="https://api.github.com/repos/${fsw_project_path}/contents/.gitmodules?ref=${fsw_repo_commit}"

    # Save the raw response, using -L to follow redirects
    local raw_response="/tmp/github_response.json"
    exec_cmd "curl -s -L \"${submodule_url}\" > ${raw_response}"

    # Check if the response still contains an error
    local error_message=$(jq -r '.message // empty' ${raw_response})
    if [ ! -z "$error_message" ]; then
        echo "ERROR: GitHub API Error: ${error_message}"
        return 1
    fi

    local gitmodules_content=$(jq -r '.content // "No content field found"' ${raw_response} | base64 -d 2>/dev/null || echo "Failed to decode base64 content")

    # Extract the specific submodule information
    local submodule_section=$(echo "${gitmodules_content}" | grep -A3 "\[submodule \"${local_submodule_path}\"\]" || echo "")

    # Try looking for the path part without the full submodule name
    local submodule_base=$(basename "$local_submodule_path")
    if [ -z "${submodule_section}" ]; then
        submodule_section=$(echo "${gitmodules_content}" | grep -A3 "\[submodule \"${submodule_base}\"\]" || echo "")

        if [ -z "${submodule_section}" ]; then
            echo "ERROR: Submodule '${local_submodule_path}' or '${submodule_base}' not found in .gitmodules"
            return 1
        fi
    fi

    # Extract the submodule path and URL
    local remote_submodule_path=$(echo "$submodule_section" | grep 'path' | cut -d'=' -f2 | tr -d ' ')
    local submodule_url=$(echo "$submodule_section" | grep 'url' | cut -d'=' -f2 | tr -d ' ')

    # Get the commit hash of the submodule
    local submodule_status_url="https://api.github.com/repos/${fsw_project_path}/contents/${remote_submodule_path}?ref=${fsw_repo_commit}"

    exec_cmd "curl -s -L \"${submodule_status_url}\" > ${raw_response}"
    local status_error=$(jq -r '.message // empty' ${raw_response})
    if [ ! -z "$status_error" ]; then
        echo "ERROR: GitHub API Error for submodule status: ${status_error}"
        return 1
    fi

    local submodule_commit=$(jq -r '.sha // "No SHA found"' ${raw_response})

    # Extract the owner and repo name from the submodule URL
    echo "DEBUG: Submodule url: ${submodule_url}"
    local ssh_regex="s/.*(${github_baseurl})[:/](.*)\.git/\2/p"
    local https_regex="s/.*(${github_baseurl})[:/](.*)$/\2/p"
    local submodule_repo=$(echo "$submodule_url" | sed -nE "$ssh_regex")
    # If we didn't get a submodule_repo yet we probably have a https not ssh submodule url
    if [ -z $submodule_repo ]; then
      submodule_repo=$(echo "$submodule_url" | sed -nE "$https_regex")
    fi

    # Start with the main requirements.txt file
    echo "submodule_repo ${submodule_repo} submodule_commit: ${submodule_commit} remote_requirements_path $remote_requirements_path temp_dir_path ${temp_dir_path}"
    fetch_requirements_file "${submodule_repo}" "${submodule_commit}" "$remote_requirements_path" "${temp_dir_path}"

    # Check if we got any requirements
    echo "temp path $temp_dir_path"
    if [ -f "${temp_dir_path}/combined_requirements.txt" ]; then
        # Sort and remove duplicates
        # NOTE we could make a requirements.txt per project but this seems simpler
        # sort -u "${temp_dir_path}/combined_requirements.txt" > "tmp_${submodule_base}_requirements.txt"
        # echo "Combined requirements for ${local_submodule_path} saved to tmp_${submodule_base}_requirements.txt"
        echo "Saving requirements for ${local_submodule_path} to combined_requirements.txt"
        sort_cmd="sort -u \"${temp_dir_path}/combined_requirements.txt\" > \"combined_requirements.txt\""
        exec_cmd "$sort_cmd"
    else
        echo "No requirements files were successfully fetched."
        return 1
    fi
}

process_local_requirements_file() {
    local file_path=$1
    local temp_dir=$2

    echo "Processing local requirements file: ${file_path}"

    # Check if the file exists
    if [ ! -f "${file_path}" ]; then
        echo "WARNING: Could not find referenced requirements file: ${file_path}"
        return 1
    fi

    # Process each line of the requirements file
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines or comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Check if this line is a reference to another requirements file
        if [[ "$line" =~ ^-r[[:space:]]+([^[:space:]]+) ]]; then
            # Extract the referenced file path
            local ref_file="${BASH_REMATCH[1]}"
            # Get the directory of the current file
            local current_dir=$(dirname "$file_path")
            # Construct the full path to the referenced file
            local ref_path="${current_dir}/${ref_file}"

            # Recursively process the referenced file
            process_local_requirements_file "$ref_path" "$temp_dir"
        else
            # If it's a normal requirement line, output it
            echo "$line" >> "${temp_dir}/combined_requirements.txt"
        fi
    done < "$file_path"
}

retrieve_local_requirements() {
    local local_submodule_path=$1
    local requirements_path=$2
    local temp_dir_path=$3

    echo "Retrieving requirements from local path: ${local_submodule_path}/${requirements_path}"

    # The complete path to the requirements file
    local full_requirements_path="${SCRIPT_DIR}/${local_submodule_path}/${requirements_path}"

    # Check if the file exists
    if [ ! -f "${full_requirements_path}" ]; then
        echo "ERROR: Requirements file not found at ${full_requirements_path}"
        return 1
    fi

    if [ $CLEAN -eq 1 ]; then
      exec_cmd "rm -f ${temp_dir_path}/combined_requirements.txt"
    fi

    exec_cmd "touch ${temp_dir_path}/combined_requirements.txt"

    # Start processing with the main requirements file
    process_local_requirements_file "${full_requirements_path}" "${temp_dir_path}"

    # Check if we got any requirements
    if [ -f "${temp_dir_path}/combined_requirements.txt" ]; then
        # Sort and remove duplicates
        # Note: Since the remote function is already handling the final sorting and saving,
        # we'll just ensure the combined file exists and is ready for that step
        echo "Successfully processed local requirements for ${local_submodule_path}/${requirements_path}"

        # Sort and save directly to combined_requirements.txt if needed
        sort_cmd="sort -u \"${temp_dir_path}/combined_requirements.txt\" > \"combined_requirements.txt\""
        exec_cmd "$sort_cmd"
    else
        echo "No requirements were successfully processed."
        return 1
    fi
}

retrieve_requirements() {
    local local_submodule_path=$1
    local requirements_path=$2
    local temp_dir_path=$3
    if [ -z $local_submodule_path ] || [ -z $requirements_path ] || [ -z $temp_dir_path ]; then
      printf "Error! to retrieve requirements we need the local_submodule_path, remote_requirements_path, and temp_dir_path!\n"
    fi

    # Dependending on our config we either want to get the requirements url by probing remote servers
    # or by finding the file locally
    if [ $LOCAL -eq 1 ]; then
      retrieve_local_requirements "$local_submodule_path" "$requirements_path" "$temp_dir_path"
    else
      retrieve_remote_requirements "$local_submodule_path" "$requirements_path" "$temp_dir_path"
    fi
}

build_docker() {
    local temp_dir=$(mktemp -d -p .)
    local requirements_file="${temp_dir}/combined_requirements.txt"

    # Get the requirements for our submodules
    # NOTE this could probably be expanded to retrieve more file types and loop on submodules
    retrieve_requirements "deps/fprime" "requirements.txt" "$temp_dir"
    # NOTE this could be used to retrieve zephyr's requirements however this was deprecated with
    # since zephyr v4.1+ supports the west packages pip --install command which is a more robust way
    # of achieving the same thing
    # retrieve_requirements "deps/zephyr" "scripts/requirements.txt" "$temp_dir"

    # Clean up temporary directory
    local build_cmd="docker compose --progress=plain --env-file=${SCRIPT_DIR}/.env build zephyr"

    [ "$CLEAN" -eq 1 ] && build_cmd+=" --no-cache"

    build_cmd+=" --build-arg FSW_WDIR=${ZEPHYR_WDIR} --build-arg HOST_UID=$HOST_UID --build-arg HOST_GID=$HOST_GID"
    build_cmd+=" --build-arg REQUIREMENTS_FILE=${requirements_file}"
    build_cmd+="; rm -rf ${temp_dir}; rm -rf ${requirements_file}"
    exec_cmd "$build_cmd"
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

build_zephyr_st() {
    flags="-w $ZEPHYR_WDIR/bare-zephyr-app $DEFAULT_FLAGS"

    cmd="west build -b sam_v71_xult/samv71q21b -d $ZEPHYR_WDIR/bare-zephyr-app/build"
    [ "$CLEAN" -eq 1 ] && cmd+=" --pristine "

    try_docker_exec "zephyr" "bash -c \"$cmd\"" "$flags"

    container_to_host_paths "${ZEPHYR_WDIR}" "${SCRIPT_DIR}" "${SCRIPT_DIR}/bare-zephyr-app/build"
}

# Used as a reference for sticky build issues
build_ledblinker_cmake() {
    container_build_dir="$ZEPHYR_WDIR/BaseDeployment/build"

    sam_board_info="-DBOARD=sam_v71_xult -DBOARD_QUALIFIERS=/samv71q21b"
    gen_cmd="cmake -S ${ZEPHYR_WDIR}/BaseDeployment -GNinja -B $container_build_dir ${sam_board_info}"
    build_cmd="cmake --build $container_build_dir --target zephyr_final"
    cmd=$build_cmd
    [ "$CLEAN" -eq 1 ] && cmd="rm -rf ${container_build_dir}/* && ${gen_cmd} && ${build_cmd}"

    try_docker_exec "zephyr" "bash -c \"$cmd\"" "$DEFAULT_FLAGS"

    container_to_host_paths "${ZEPHYR_WDIR}" "${SCRIPT_DIR}" "$SCRIPT_DIR/BaseDeployment/build"
}

build_ledblinker_west() {
    flags="-w $ZEPHYR_WDIR $DEFAULT_FLAGS"
    exec_cmd "mkdir -p $SCRIPT_DIR/build"

    cmd="west build -b sam_v71_xult/samv71q21b -d $ZEPHYR_WDIR/build"
    [ "$CLEAN" -eq 1 ] && cmd+=" --pristine "

    try_docker_exec "zephyr" "bash -c \"$cmd\"" "$flags"

    container_to_host_paths "${ZEPHYR_WDIR}" "${SCRIPT_DIR}" "${SCRIPT_DIR}/build"
}

case $1 in
  "pull")
    update_cmd="git pull"
    [ "$FORCE" -eq 1 ] && update_cmd="git fetch -a && git reset --hard origin/$(git rev-parse --abbrev-ref HEAD)"
    update_cmd+=" && git submodule sync && git submodule update --init --recursive"
    update_cmd+=" && docker ${ZEPHYR_IMG}"

    exec_cmd "$update_cmd"

    try_docker_exec "$DEFAULT_SVC" "west update -n --stats" "-w $ZEPHYR_WDIR $DEFAULT_FLAGS"
    ;;

  "build")
    EXEC_TARGET=${2:-}
    [ -z "$EXEC_TARGET" ] && { echo "Error: must specify target to exec"; exit 1; }

    case $EXEC_TARGET in
      "zephyr-st")
        build_zephyr_st
      ;;
      "BaseDeployment")
        build_ledblinker_cmake
      ;;
      "BaseDeployment-west")
        build_ledblinker_west
      ;;
      "docker")
        build_docker
      ;;
      *)
      echo "Invalid build command: ${EXEC_TARGET}"
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

        run_docker_compose "zephyr-tty" "bash -c \"${load_cmd}\"" "it"
      ;;
      "BaseDeployment")
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
      "debug-cmsis-st")
        bin_path="./fprime-cmsis/cmake/toolchain/support/sources/zephyrv71q21b/out/blinky/ZephyrV71-Xplained-Board/Debug/blinky.elf"
        debug_cmd="pyocd gdbserver --elf ${bin_path} -t atzephyrv71q21b"

        export HOST_DEVICE_PORT=$(find_board_port) || exit 1
        run_docker_compose "zephyr-tty" "bash -c \"${debug_cmd}\"" "-it"
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
      "gds")
        #NOTE the gds port is not the debug port, if incorrectly selected the serial output will appear garbled (see exec console output)
        gds_port=${3:-"/dev/ttyACM0"}
        baud="115200"
        dict_path="${ZEPHYR_WDIR}/build/BaseDeployment/Top/BaseDeploymentTopologyDictionary.json"
        cmd="fprime-gds --dictionary ${dict_path} --uart-device ${gds_port} --uart-baud ${baud} --communication-selection uart -n"
        flags="-it"
        try_docker_exec "zephyr-tty" "bash -c \"$cmd\"" "$flags"

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
      INSPECT_TARGET=${2:-$DEFAULT_SVC}
      case $INSPECT_TARGET in
          "zephyr")
            try_docker_exec $INSPECT_TARGET "bash" "-it"
        ;;
          "zephyr-tty")
            # export HOST_DEVICE_PORT=$(find_board_port) || exit 1
            try_docker_exec $INSPECT_TARGET "bash" "-it"
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
