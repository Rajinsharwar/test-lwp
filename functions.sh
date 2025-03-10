#!/usr/bin/env bash

# These functions have been adapted from
# https://github.com/dokku/dokku/blob/master/plugins/common/functions

has_tty() {
  declare desc="return 0 if we have a tty"
  if [[ "$(/usr/bin/tty || true)" == "not a tty" ]]; then
    return 1
  else
    return 0
  fi
}

ee_log_quiet() {
  declare desc="log quiet formatter"
  if [[ -z "$EE_QUIET_OUTPUT" ]]; then
    echo "$*"
  fi
}

ee_log_info1() {
  declare desc="log info1 formatter"
  echo "-----> $*"
}

ee_log_info2() {
  declare desc="log info2 formatter"
  echo "=====> $*"
}

ee_log_info1_quiet() {
  declare desc="log info1 formatter (with quiet option)"
  if [[ -z "$EE_QUIET_OUTPUT" ]]; then
    echo "-----> $*"
  else
    return 0
  fi
}

ee_log_info2_quiet() {
  declare desc="log info2 formatter (with quiet option)"
  if [[ -z "$EE_QUIET_OUTPUT" ]]; then
    echo "=====> $*"
  else
    return 0
  fi
}

ee_col_log_info1() {
  declare desc="columnar log info1 formatter"
  printf "%-6s %-18s %-25s %-25s %-25s\n" "----->" "$@"
}

ee_col_log_info1_quiet() {
  declare desc="columnar log info1 formatter (with quiet option)"
  if [[ -z "$EE_QUIET_OUTPUT" ]]; then
    printf "%-6s %-18s %-25s %-25s %-25s\n" "----->" "$@"
  else
    return 0
  fi
}

ee_col_log_info2() {
  declare desc="columnar log info2 formatter"
  printf "%-6s %-18s %-25s %-25s %-25s\n" "=====>" "$@"
}

ee_col_log_info2_quiet() {
  declare desc="columnar log info2 formatter (with quiet option)"
  if [[ -z "$EE_QUIET_OUTPUT" ]]; then
    printf "%-6s %-18s %-25s %-25s %-25s\n" "=====>" "$@"
  else
    return 0
  fi
}

ee_col_log_msg() {
  declare desc="columnar log formatter"
  printf "%-25s %-25s %-25s %-25s\n" "$@"
}

ee_col_log_msg_quiet() {
  declare desc="columnar log formatter (with quiet option)"
  if [[ -z "$EE_QUIET_OUTPUT" ]]; then
    printf "%-25s %-25s %-25s %-25s\n" "$@"
  else
    return 0
  fi
}

ee_log_verbose_quiet() {
  declare desc="log verbose formatter (with quiet option)"
  if [[ -z "$EE_QUIET_OUTPUT" ]]; then
    echo "       $*"
  else
    return 0
  fi
}

ee_log_verbose() {
  declare desc="log verbose formatter"
  echo "       $*"
}

ee_log_warn() {
  declare desc="log warning formatter"
  echo " !     $*" 1>&2
}

ee_log_fail() {
  declare desc="log fail formatter"
  echo "$@" 1>&2
  exit 1
}

parse_args() {
  declare desc="top-level cli arg parser"
  local next_index=1
  local skip=false
  local args=("$@")
  for arg in "$@"; do
    if [[ "$skip" == "true" ]]; then
      next_index=$((next_index + 1))
      skip=false
      continue
    fi

    case "$arg" in
      --quiet)
        export EE_QUIET_OUTPUT=1
        ;;
      --trace)
        export EE_TRACE=1
        ;;
      --dry-run)
        export EE_DRY_RUN=1
        ;;
      --all)
        export EE_SITE_ALL=1
        ;;
      --remote-host)
        export REMOTE_HOST=${args[$next_index]}
        skip=true
        ;;
    esac
    next_index=$((next_index + 1))
  done
  return 0
}

function check_ssh() {
  ee_log_info1 "Checking connection to remote server."
  ssh -q -i $SSH_KEY "root@$REMOTE_HOST" exit >/dev/null 2>&1 # No need to show this output
  if [ $? -eq 0 ]; then
    true
  else
    if [ ! -f "$SSH_KEY" ]; then
      ssh-keygen -t rsa -b 4096 -N '' -C 'ee3_to_ee4_key' -f $SSH_KEY >/dev/null 2>&1 # No need to show this output
    else
      ee_log_info2 "If you have not done so already, you need to add the following"
      cat "${SSH_KEY}.pub"
      ee_log_info2 "to \`/root/.ssh/authorized_keys\` on the remote server"
      ee_log_fail "Unable to connect to remote server. Please check if \`ssh root@$REMOTE_HOST\` is working."
      false
    fi
    ee_log_info2 "Add the following"
    cat "${SSH_KEY}.pub"
    ee_log_info2 "to \`/root/.ssh/authorized_keys\` on the remote server"
    false
  fi
}

function run_remote_command() {
  declare desc="run_remote_command COMMAND [HOST:$REMOTE_HOST] [DIR:/root] [USER:root]"
  COMMAND="$1"
  HOST="${2:-$REMOTE_HOST}"
  DIR="${3:-/root}"
  USER="${4:-root}"

  ssh -i $SSH_KEY $USER@$HOST "source ${REMOTE_TMP_WORK_DIR}install-script; source ${REMOTE_TMP_WORK_DIR}helper-functions; $COMMAND"
}

function setup_docker() {
  ee_log_info1 "Installing Docker"
  # Check if docker exists. If not start docker installation.
  if ! command -v docker >/dev/null 2>&1; then
    # Running standard docker installation.
    wget --quiet get.docker.com -O docker-setup.sh
    sh docker-setup.sh
  fi

  # Check if docker-compose exists. If not start docker-compose installation.
  if ! command -v docker-compose >/dev/null 2>&1; then
    ee_log_info1 "Installing Docker-Compose"
    curl -L https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  fi
}

function setup_php() {
  ee_log_info1 "Installing PHP"
  if ! command -v php >/dev/null 2>&1; then
    # Checking linux distro. Currently only Ubuntu and Debian are supported.
    if [ "$EE_LINUX_DISTRO" == "Ubuntu" ]; then
      ee_log_info1 "Installing PHP cli"
      # Adding software-properties-common for add-apt-repository.
      apt-get install -y software-properties-common
      # Adding ondrej/php repository for installing php, this works for all ubuntu flavours.
      add-apt-repository -y ppa:ondrej/php
      apt-get update && apt-get -y upgrade
      # Installing php-cli, which is the minimum requirement to run EasyEngine
      apt-get -y install php8.3-cli
    elif [ "$EE_LINUX_DISTRO" == "Debian" ]; then
      ee_log_info1 "Installing PHP cli"
      # Nobody should have to change their name to enable a package installation
      # https://github.com/oerdnj/deb.sury.org/issues/56#issuecomment-166077158
      # That's why we're installing the locales package.
      apt-get install apt-transport-https lsb-release ca-certificates locales locales-all -y
      export LC_ALL=en_US.UTF-8
      export LANG=en_US.UTF-8
      wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
      echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
      apt-get update
      apt-get install php8.3-cli -y
    fi
  fi
}

function setup_php_extensions() {
  ee_log_info1 "Installing PHP extensions"
  # Setting up the three required php extensions for EasyEngine.
  if command -v php >/dev/null 2>&1; then
    php_extensions=(pcntl curl sqlite3 zip)
    if ! command -v gawk >/dev/null 2>&1; then
      apt install gawk -y
    fi
    # Reading the php version.
    default_php_version="$(readlink -f /usr/bin/php | gawk -F "php" '{ print $2}')"
    ee_log_info1 "Installed PHP : $default_php_version"
    ee_log_info1 "Checking if required PHP modules are installed..."
    packages=""
    for module in "${php_extensions[@]}"; do
      if ! php -m | grep $module >/dev/null 2>&1; then
        ee_log_info1 "$module not installed. Installing..."
        packages+="php$default_php_version-$module "
      else
        ee_log_info1 "$module is already installed"
      fi
      apt install -y $packages
    done
  fi
}

function create_swap() {
  ee_log_info2 "Enabling 1GiB swap"
  EE_SWAP_FILE="/ee-swapfile"
  fallocate -l 1G $EE_SWAP_FILE && \
  chmod 600 $EE_SWAP_FILE && \
  chown root:root $EE_SWAP_FILE && \
  mkswap $EE_SWAP_FILE && \
  swapon $EE_SWAP_FILE
}

function check_swap() {
  ee_log_info1 "Checking swap"
  if free | awk '/^Swap:/ {exit !$2}'; then
    :
  else
    ee_log_info1 "No swap detected"
    create_swap
  fi
}

function setup_host_dependencies() {
    if [ "$EE_LINUX_DISTRO" == "Ubuntu" ] || [ "$EE_LINUX_DISTRO" == "Debian" ]; then
      if ! command -v ip >> $LOG_FILE 2>&1; then
        echo "Installing iproute2"
        apt update && apt install iproute2 -y
      fi
    fi
}

function check_depdendencies() {
  ee_log_info1 "Checking dependencies"
  if ! command -v sqlite3 >/dev/null 2>&1; then
    ee_log_info2 "Installing sqlite3"
    apt install sqlite3 -y
  fi

  setup_host_dependencies
  setup_docker
  setup_php
  setup_php_extensions
  check_swap
}

function download_and_install_easyengine() {
  ee_log_info1 "Downloading EasyEngine phar"
  # Download EasyEngine phar.
  wget -O "$EE4_BINARY" https://raw.githubusercontent.com/Rajinsharwar/test-lwp/master/phar/easyengine.phar?token
  # Make it executable.
  chmod +x "$EE4_BINARY"
}

function pull_easyengine_images() {
  # Running EE migrations and pulling of images by first `ee` invocation.
  ee_log_info1 "Pulling EasyEngine docker images"
  "$EE4_BINARY" cli info
}

function add_ssl_renew_cron() {
  # noglob is required to ensure that '*' is not expanded to list all files in current directory while printing SSL_RENEW_CRON
  set -o noglob

  [[ ":$PATH:" != *":/usr/local/bin:"* ]] && PATH="/usr/local/bin:${PATH}"
  SSL_RENEW_CRON="PATH=$PATH\n\n0 0 * * * /usr/local/bin/ee site ssl-renew --all >> /opt/launchwp/logs/cron.log 2>&1"
  # Check if cron is installed in the system.
  which cron && which crontab

  if [ $? -eq 0 ]
  then
    ee_log_info1 "Adding ssl-renew cron"
    crontab -l > ee_cron
    echo -e $SSL_RENEW_CRON >> ee_cron
    crontab ee_cron
    rm ee_cron
  fi
  
  set +o noglob
}