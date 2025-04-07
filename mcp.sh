#!/bin/bash

# Script to install Homebrew, Node.js v23+ via NVM, Python, uv, and various MCP servers
# Runs without requiring user input, for JAMF deployment
# Created: 2025-04-03

# This script must be run as the logged-in user via JAMF's "Run script as user" option

# ====== Configuration ======
LOG_FILE="$HOME/Library/Logs/mcp_installation_script.log"
CURRENT_USER=$(whoami)
USER_HOME=$HOME
NODE_MIN_VERSION="23"
PYTHON_MIN_VERSION="3.12"
MCP_CONFIG_DIR="$HOME/Library/Application Support/Claude"
MCP_CONFIG_FILE="$MCP_CONFIG_DIR/claude_desktop_config.json"
CURSOR_CONFIG_DIR="$HOME/.cursor"
CURSOR_CONFIG_FILE="$CURSOR_CONFIG_DIR/mcp.json"
OP_VAULT="MCP"  # The name of the 1Password vault containing MCP credentials
CLAUDE_DESKTOP_URL="https://claude.ai/download"
CLAUDE_DOWNLOAD_DIR="$HOME/Downloads"
CLAUDE_APP_PATH="/Applications/Claude.app"
CURSOR_APP_PATH="/Applications/Cursor.app"

# Rootly MCP server configuration
ROOTLY_REPO="https://github.com/Rootly-AI-Labs/Rootly-MCP-server.git"
ROOTLY_INSTALL_DIR="$HOME/rootly-mcp-server"
ROOTLY_ENV_FILE="$ROOTLY_INSTALL_DIR/.env"

# Zendesk MCP server configuration
ZENDESK_REPO="https://github.com/reminia/zendesk-mcp-server.git"
ZENDESK_INSTALL_DIR="$HOME/zendesk-mcp-server"
ZENDESK_ENV_FILE="$ZENDESK_INSTALL_DIR/.env"

# GSuite MCP server configuration
GSUITE_REPO="https://github.com/MarkusPfundstein/mcp-gsuite.git"
GSUITE_INSTALL_DIR="$HOME/mcp-gsuite"
GSUITE_AUTH_FILE="$GSUITE_INSTALL_DIR/.gauth.json"
GSUITE_ACCOUNTS_FILE="$GSUITE_INSTALL_DIR/.accounts.json"

# Atlassian MCP server configuration
ATLASSIAN_REPO="https://github.com/sooperset/mcp-atlassian.git"
ATLASSIAN_INSTALL_DIR="$HOME/mcp-atlassian"
ATLASSIAN_ENV_FILE="$ATLASSIAN_INSTALL_DIR/.env"

# Notion MCP server configuration
NOTION_INSTALL_DIR="$HOME/mcp-notion-server"
NOTION_ENV_FILE="$NOTION_INSTALL_DIR/.env"

# Figma MCP server configuration
FIGMA_PACKAGE_NAME="figma-developer-mcp"

# Sentry MCP server configuration
SENTRY_REPO="https://github.com/MCP-100/mcp-sentry"
SENTRY_INSTALL_DIR="$HOME/sentry-mcp"
SENTRY_ENV_FILE="$SENTRY_INSTALL_DIR/.env"

# Datadog MCP server configuration
DATADOG_PACKAGE_NAME="@winor30/mcp-server-datadog"

# ====== Logging Function ======
log_message() {
    echo "$(date +"%Y-%m-%d %H:%M:%S"): $1" | tee -a "$LOG_FILE"
}

# ====== Helper functions ======
# Function to load NVM
load_nvm() {
    # Try to load NVM from common locations
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        . "$HOME/.nvm/nvm.sh"
        log_message "Loaded NVM from $HOME/.nvm/nvm.sh"
        return 0
    elif [ -s "/usr/local/opt/nvm/nvm.sh" ]; then
        . "/usr/local/opt/nvm/nvm.sh"
        log_message "Loaded NVM from /usr/local/opt/nvm/nvm.sh"
        return 0
    elif [ -s "$BREW_PREFIX/opt/nvm/nvm.sh" ]; then
        . "$BREW_PREFIX/opt/nvm/nvm.sh"
        log_message "Loaded NVM from $BREW_PREFIX/opt/nvm/nvm.sh"
        return 0
    else
        log_message "Could not find NVM installation to load"
        return 1
    fi
}

# Function to check if 1Password CLI is installed and signed in
check_1password_cli() {
    if ! which op > /dev/null 2>&1; then
        log_message "1Password CLI not found. Installing..."
        brew install --cask 1password-cli

        if ! which op > /dev/null 2>&1; then
            log_message "Error: Failed to install 1Password CLI. API keys will not be retrieved automatically."
            return 1
        fi
    fi

    # Check if signed in
    if ! op account list > /dev/null 2>&1; then
        log_message "Not signed in to 1Password CLI. Please sign in manually by running 'op signin' and then rerun this script."
        log_message "API keys will not be retrieved automatically."
        return 1
    fi

    # Check if the MCP vault exists
    if ! op vault list | grep -q "$OP_VAULT"; then
        log_message "1Password vault '$OP_VAULT' not found. API keys will not be retrieved automatically."
        return 1
    fi

    return 0
}

# Function to safely retrieve an item from 1Password
get_1password_item() {
    local item_name="$1"
    local field_name="$2"

    # Try to get the item
    local result
    result=$(op item get "$item_name" --vault "$OP_VAULT" --fields "$field_name" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$result" ]; then
        log_message "Warning: Could not retrieve '$item_name' from 1Password vault '$OP_VAULT'"
        echo ""
        return 1
    fi

    echo "$result"
    return 0
}

# Function to fetch credentials for an MCP service from 1Password
fetch_mcp_credentials() {
    local service_name="$1"
    shift
    local all_retrieved=true

    log_message "Retrieving credentials for $service_name from 1Password vault '$OP_VAULT'..."
    
    # Create result arrays
    declare -a FIELDS=()
    declare -a VALUES=()
    
    # Process each field
    while [ "$#" -gt 0 ]; do
        local field="$1"
        log_message "Retrieving field '$field' for '$service_name'"
        
        local value=$(get_1password_item "$service_name" "$field")
        
        if [ -n "$value" ]; then
            log_message "Retrieved $service_name $field successfully"
        else
            log_message "Could not retrieve $service_name $field. A placeholder will be used."
            all_retrieved=false
            value=""
        fi
        
        # Store field and value in arrays
        FIELDS+=("$field")
        VALUES+=("$value")
        
        shift
    done

    if [ "$all_retrieved" = true ]; then
        log_message "All $service_name credentials retrieved successfully"
    else
        log_message "Some $service_name credentials could not be retrieved. Placeholders will be used where needed."
    fi

    # Print fields and values as newline-separated output for easier parsing
    for i in "${!FIELDS[@]}"; do
        echo "${FIELDS[$i]}=${VALUES[$i]}"
    done
}

# Parse credentials returned by fetch_mcp_credentials
parse_credentials() {
    local service=$1
    local output=$(fetch_mcp_credentials "$service" "$@")
    
    # Process each line of output and convert to export statements
    while IFS= read -r line; do
        if [[ "$line" == *"="* ]]; then
            local key="${line%%=*}"
            local value="${line#*=}"
            log_message "Setting ${service}_${key}=\"${value}\""
            # Output an export statement for each credential
            echo "export ${service}_${key}=\"${value}\""
        fi
    done <<< "$output"
}

# Securely set credential variables without using eval
set_credential() {
    local service="$1"
    local field="$2"
    local var_name="${service}_${field}"
    
    # Get the credential value directly
    local value=$(get_1password_item "$service" "$field")
    
    # if [ -n "$value" ]; then
    #     log_message "Retrieved $service $field successfully"
    # else
    #     log_message "Could not retrieve $service $field. A placeholder will be used."
    #     value=""
    # fi
    
    # Return the value so we can capture it in the parent scope
    echo "$value"
}

# Function to install an npx-based MCP server
install_npx_mcp_server() {
    local package_name="$1"
    local server_name="$2"
    
    log_message "Installing $server_name MCP Server..."
    
    npm install -g "$package_name"
    
    # Check installation
    if npm list -g "$package_name" > /dev/null 2>&1; then
        log_message "$server_name MCP Server installed successfully"
    else
        log_message "Warning: $server_name MCP Server installation may have failed"
    fi
}

# Function to install a uv-based MCP server from GitHub
install_uv_mcp_server() {
    local repo_url="$1"
    local install_dir="$2"
    local server_name="$3"
    local env_file="$4"
    local env_content="$5"
    
    log_message "Installing $server_name MCP Server from GitHub using uv..."

    # Clone the repository
    if [ -d "$install_dir" ]; then
        log_message "$server_name MCP Server directory already exists, updating..."
        cd "$install_dir"
        git pull
    else
        log_message "Cloning $server_name MCP Server repository..."
        git clone "$repo_url" "$install_dir"
        if [ $? -ne 0 ]; then
            log_message "Error: Failed to clone $server_name MCP Server repository"
            return 1
        else
            log_message "$server_name MCP Server repository cloned successfully"
            cd "$install_dir"
        fi
    fi

    # Build using uv
    if [ -d "$install_dir" ]; then
        log_message "Building $server_name MCP Server using uv..."
        cd "$install_dir"
        
        # Create .env file if content is provided
        if [ -n "$env_file" ] && [ -n "$env_content" ]; then
            log_message "Creating .env file with $server_name credentials..."
            echo "$env_content" > "$env_file"
            log_message "$server_name .env file created at $env_file"
        fi
        
        # Install dependencies using uv
        uv build

        if [ $? -ne 0 ]; then
            log_message "Error: Failed to build $server_name MCP Server using uv"
            return 1
        else
            log_message "$server_name MCP Server built successfully using uv"
            return 0
        fi
    fi
    
    return 1
}

# Function to download and install Claude Desktop
install_claude_desktop() {
    log_message "Checking if Claude Desktop is already installed..."

    # Check if Claude Desktop is already installed
    if [ -d "$CLAUDE_APP_PATH" ]; then
        log_message "Claude Desktop is already installed. Checking for updates..."
        # Open Claude to trigger its own update mechanism
        open -a Claude
        # Give it a moment to check for updates
        sleep 5
        # Close Claude
        osascript -e 'tell application "Claude" to quit'
        return 0
    fi

    log_message "Claude Desktop not found. Installing..."

    # Create temporary directory for downloads if it doesn't exist
    mkdir -p "$CLAUDE_DOWNLOAD_DIR"

    # Use curl to download the page and extract the macOS download link
    log_message "Getting download link from Claude website..."
    DOWNLOAD_PAGE=$(curl -s "$CLAUDE_DESKTOP_URL")

    # Look for macOS download link
    MACOS_DOWNLOAD_LINK=$(echo "$DOWNLOAD_PAGE" | grep -o 'href="[^"]*\.dmg"' | head -1 | cut -d'"' -f2)

    if [ -z "$MACOS_DOWNLOAD_LINK" ]; then
        log_message "Error: Could not find macOS download link for Claude Desktop"
        return 1
    fi

    # If the link is relative, make it absolute
    if [[ "$MACOS_DOWNLOAD_LINK" != http* ]]; then
        MACOS_DOWNLOAD_LINK="https://claude.ai$MACOS_DOWNLOAD_LINK"
    fi

    log_message "Found download link: $MACOS_DOWNLOAD_LINK"

    # Download the DMG file
    DMG_PATH="$CLAUDE_DOWNLOAD_DIR/Claude.dmg"
    log_message "Downloading Claude Desktop to $DMG_PATH..."
    curl -L -o "$DMG_PATH" "$MACOS_DOWNLOAD_LINK"

    if [ ! -f "$DMG_PATH" ]; then
        log_message "Error: Failed to download Claude Desktop DMG"
        return 1
    fi

    log_message "Downloaded Claude Desktop successfully"

    # Mount the DMG
    log_message "Mounting DMG file..."
    MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse | tail -n 1 | awk '{print $NF}')

    if [ -z "$MOUNT_POINT" ]; then
        log_message "Error: Failed to mount Claude Desktop DMG"
        return 1
    fi

    log_message "DMG mounted at $MOUNT_POINT"

    # Copy the app to Applications folder
    log_message "Installing Claude Desktop to Applications folder..."
    cp -R "$MOUNT_POINT/Claude.app" /Applications/

    # Unmount the DMG
    log_message "Unmounting DMG..."
    hdiutil detach "$MOUNT_POINT" -quiet

    # Clean up
    log_message "Cleaning up..."
    rm "$DMG_PATH"

    # Verify installation
    if [ -d "$CLAUDE_APP_PATH" ]; then
        log_message "Claude Desktop installed successfully"
        return 0
    else
        log_message "Error: Failed to install Claude Desktop"
        return 1
    fi
}

# Start logging
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
touch "$LOG_FILE" 2>/dev/null
log_message "Starting installation script for Homebrew, NVM, Node.js, Python, uv, and MCP servers"
log_message "Running as user: $CURRENT_USER"

# ====== Set up Homebrew environment for this script session ======
if [[ "$(/usr/bin/uname -m)" == "arm64" ]]; then
    # Apple Silicon Mac
    BREW_PREFIX="/opt/homebrew"
    export PATH="/opt/homebrew/bin:$PATH"
else
    # Intel Mac
    BREW_PREFIX="/usr/local"
    export PATH="/usr/local/bin:$PATH"
fi

# ====== Check if Homebrew is already installed ======
if which brew > /dev/null 2>&1; then
    log_message "Homebrew is already installed, updating..."
    brew update
else
    log_message "Installing Homebrew..."

    # Create environment variables for non-interactive installation
    export NONINTERACTIVE=1
    export CI=1

    # Run the Homebrew installer without user interaction
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Check installation success
    if which brew > /dev/null 2>&1; then
        log_message "Homebrew installed successfully"
    else
        log_message "Error: Homebrew installation failed"

        # Try to add Homebrew to PATH for this session
        if [[ "$(/usr/bin/uname -m)" == "arm64" ]]; then
            export PATH="/opt/homebrew/bin:$PATH"
        else
            export PATH="/usr/local/bin:$PATH"
        fi

        # Check again after PATH update
        if which brew > /dev/null 2>&1; then
            log_message "Homebrew found after PATH update"
        else
            log_message "Homebrew still not found after PATH update. Exiting."
            exit 1
        fi
    fi

    # Add Homebrew to the user's PATH in .zprofile if it doesn't exist
    if [[ "$(/usr/bin/uname -m)" == "arm64" ]]; then
        # Apple Silicon Mac
        if ! grep -q "/opt/homebrew/bin/brew" "$USER_HOME/.zprofile" 2>/dev/null; then
            log_message "Adding Homebrew to PATH for Apple Silicon in .zprofile"
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$USER_HOME/.zprofile"
        fi
    else
        # Intel Mac
        if ! grep -q "/usr/local/bin/brew" "$USER_HOME/.zprofile" 2>/dev/null; then
            log_message "Adding Homebrew to PATH for Intel Mac in .zprofile"
            echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$USER_HOME/.zprofile"
        fi
    fi
fi

# ====== Install Python if needed ======
log_message "Checking for Python installation..."
if which python3 > /dev/null 2>&1; then
    PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    log_message "Python version $PYTHON_VERSION is already installed"

    # Check if installed version meets minimum requirement
    PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
    PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)
    PYTHON_MIN_MAJOR=$(echo $PYTHON_MIN_VERSION | cut -d. -f1)
    PYTHON_MIN_MINOR=$(echo $PYTHON_MIN_VERSION | cut -d. -f2)

    if [ "$PYTHON_MAJOR" -lt "$PYTHON_MIN_MAJOR" ] || [ "$PYTHON_MAJOR" -eq "$PYTHON_MIN_MAJOR" -a "$PYTHON_MINOR" -lt "$PYTHON_MIN_MINOR" ]; then
        log_message "Installed Python version ($PYTHON_VERSION) is older than minimum required version ($PYTHON_MIN_VERSION)"
        log_message "Installing Python $PYTHON_MIN_VERSION via Homebrew..."
        brew install python@$PYTHON_MIN_VERSION

        if [ $? -ne 0 ]; then
            log_message "Warning: Failed to install Python $PYTHON_MIN_VERSION. Will continue with existing Python $PYTHON_VERSION"
        else
            log_message "Python $PYTHON_MIN_VERSION installed successfully"
            # Update symlinks to use the new Python version
            brew link --overwrite python@$PYTHON_MIN_VERSION
        fi
    else
        log_message "Installed Python version ($PYTHON_VERSION) meets minimum requirement ($PYTHON_MIN_VERSION)"
    fi
else
    log_message "Python not found. Installing Python $PYTHON_MIN_VERSION via Homebrew..."
    brew install python@$PYTHON_MIN_VERSION

    if [ $? -ne 0 ]; then
        log_message "Error: Failed to install Python $PYTHON_MIN_VERSION. Trying to install latest Python..."
        brew install python

        if [ $? -ne 0 ]; then
            log_message "Error: Failed to install Python. Some functionality may not work correctly."
        else
            log_message "Latest Python installed successfully"
        fi
    else
        log_message "Python $PYTHON_MIN_VERSION installed successfully"
    fi
fi

# ====== Install uv if needed ======
log_message "Checking for uv installation..."
if which uv > /dev/null 2>&1; then
    UV_VERSION=$(uv --version | head -n 1)
    log_message "uv version $UV_VERSION is already installed"
else
    log_message "uv not found. Installing uv via Homebrew..."
    brew install uv

    if [ $? -ne 0 ]; then
        log_message "Error: Failed to install uv via Homebrew. Trying to install with pip..."

        # Ensure pip is available
        if which pip3 > /dev/null 2>&1; then
            pip3 install uv

            if [ $? -ne 0 ]; then
                log_message "Error: Failed to install uv via pip. Some functionality may not work correctly."
            else
                log_message "uv installed successfully via pip"
            fi
        else
            log_message "Error: pip3 not found. Cannot install uv. Some functionality may not work correctly."
        fi
    else
        log_message "uv installed successfully via Homebrew"
    fi
fi

# ====== Install Claude Desktop ======
log_message "Checking for Claude Desktop..."
install_claude_desktop
CLAUDE_INSTALLED=$?

if [ $CLAUDE_INSTALLED -eq 0 ]; then
    log_message "Claude Desktop is ready"
else
    log_message "Warning: Issue with Claude Desktop installation or update. MCP servers will still be installed."
fi

# ====== Install 1Password CLI if needed ======
log_message "Checking for 1Password CLI..."
if ! which op > /dev/null 2>&1; then
    log_message "Installing 1Password CLI..."
    brew install --cask 1password-cli

    if ! which op > /dev/null 2>&1; then
        log_message "Warning: Failed to install 1Password CLI. Proceeding without automatic credential retrieval."
    fi
fi

# Check if 1Password is properly set up
OP_AVAILABLE=true
if ! check_1password_cli; then
    log_message "Warning: 1Password CLI is not properly set up. Continuing without automatic credential retrieval."
    OP_AVAILABLE=false
fi

# Retrieve credentials from 1Password if available
if [ "$OP_AVAILABLE" = true ]; then
    log_message "Retrieving credentials from 1Password vault '$OP_VAULT'..."

    # Firecrawl credentials
    FIRECRAWL_API_KEY=$(set_credential "Firecrawl" "api_key")
    
    # Rootly credentials
    ROOTLY_API_TOKEN=$(set_credential "Rootly" "api_token")
    
    # Zendesk credentials
    ZENDESK_EMAIL=$(set_credential "Zendesk" "username")
    ZENDESK_API_KEY=$(set_credential "Zendesk" "api_token")
    ZENDESK_SUBDOMAIN=$(set_credential "Zendesk" "subdomain")
    
    if [ -z "$ZENDESK_API_KEY" ]; then
        log_message "Using default placeholder for Zendesk API key"
        ZENDESK_API_KEY="def"
    fi

    # Slack credentials
    SLACK_BOT_TOKEN=$(set_credential "Slack" "bot_token")
    SLACK_TEAM_ID=$(set_credential "Slack" "team_id")

    # Gmail credentials
    GMAIL_CLIENT_ID=$(set_credential "Gmail" "client_id")
    GMAIL_CLIENT_SECRET=$(set_credential "Gmail" "client_secret")

    # Atlassian credentials
    JIRA_URL=$(set_credential "Atlassian" "url")
    JIRA_USERNAME=$(set_credential "Atlassian" "username")
    JIRA_TOKEN=$(set_credential "Atlassian" "token")

    # Notion credentials
    NOTION_TOKEN=$(set_credential "Notion" "token")

    # Figma credentials
    FIGMA_API_KEY=$(set_credential "Figma" "api_key")

    # Sentry credentials
    SENTRY_AUTH_TOKEN=$(set_credential "Sentry" "auth_token")
    SENTRY_ORGANIZATION=$(set_credential "Sentry" "organization")
    SENTRY_PROJECT=$(set_credential "Sentry" "project")

    # Datadog credentials
    DATADOG_API_KEY=$(set_credential "Datadog" "api_key")
    DATADOG_APP_KEY=$(set_credential "Datadog" "app_key")
    DATADOG_SITE="datadoghq.com"
else
    # Set placeholders if 1Password is not available
    FIRECRAWL_API_KEY=""
    ROOTLY_API_TOKEN=""
    ZENDESK_EMAIL=""
    ZENDESK_API_KEY="def"
    ZENDESK_SUBDOMAIN=""
    SLACK_BOT_TOKEN=""
    SLACK_TEAM_ID=""
    GMAIL_CLIENT_ID=""
    GMAIL_CLIENT_SECRET=""
    JIRA_URL=""
    JIRA_USERNAME=""
    JIRA_TOKEN=""
    NOTION_TOKEN=""
    FIGMA_API_KEY=""
    SENTRY_AUTH_TOKEN=""
    SENTRY_ORGANIZATION=""
    SENTRY_PROJECT=""
    DATADOG_API_KEY=""
    DATADOG_APP_KEY=""
    DATADOG_SITE="datadoghq.com"  # Default site
fi

# ====== Install NVM if needed ======
if [ -s "$HOME/.nvm/nvm.sh" ] || which nvm > /dev/null 2>&1; then
    log_message "NVM is already installed"
    load_nvm
else
    log_message "Installing NVM using Homebrew..."

    # Install NVM via Homebrew
    brew install nvm

    # Create NVM directory
    mkdir -p "$HOME/.nvm"

    # Add NVM configuration to shell profiles
    NVM_CONFIG="export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"$BREW_PREFIX/opt/nvm/nvm.sh\" ] && . \"$BREW_PREFIX/opt/nvm/nvm.sh\"  # This loads nvm
[ -s \"$BREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm\" ] && . \"$BREW_PREFIX/opt/nvm/etc/bash_completion.d/nvm\"  # This loads nvm bash_completion"

    # Add to appropriate shell profile files
    for PROFILE in ".zshrc" ".bash_profile"; do
        if [ -f "$HOME/$PROFILE" ]; then
            if ! grep -q "NVM_DIR" "$HOME/$PROFILE"; then
                log_message "Adding NVM configuration to $PROFILE"
                echo "" >> "$HOME/$PROFILE"
                echo "# NVM Configuration" >> "$HOME/$PROFILE"
                echo "$NVM_CONFIG" >> "$HOME/$PROFILE"
            fi
        else
            log_message "Creating $PROFILE with NVM configuration"
            echo "# NVM Configuration" > "$HOME/$PROFILE"
            echo "$NVM_CONFIG" >> "$HOME/$PROFILE"
        fi
    done

    # Try to load NVM for the current script session
    export NVM_DIR="$HOME/.nvm"
    if load_nvm; then
        log_message "NVM loaded successfully"
    else
        log_message "Warning: Could not load NVM after installation"
        log_message "Attempting to source NVM directly from Homebrew location"
        if [ -s "$BREW_PREFIX/opt/nvm/nvm.sh" ]; then
            . "$BREW_PREFIX/opt/nvm/nvm.sh"
            log_message "Sourced NVM directly from $BREW_PREFIX/opt/nvm/nvm.sh"
        else
            log_message "Error: Could not find NVM installation to source"
            exit 1
        fi
    fi
fi

# ====== Check NVM is working ======
if ! command -v nvm > /dev/null 2>&1; then
    log_message "Error: NVM command not available after installation"
    exit 1
fi

# ====== Install Node.js using NVM ======
# Check if required version is already installed
NVM_LS_OUTPUT=$(nvm ls)
if echo "$NVM_LS_OUTPUT" | grep -q "v$NODE_MIN_VERSION"; then
    log_message "Node.js v$NODE_MIN_VERSION or higher is already installed via NVM"
else
    log_message "Installing latest Node.js v$NODE_MIN_VERSION.x via NVM..."
    nvm install $NODE_MIN_VERSION

    if [ $? -ne 0 ]; then
        log_message "Error: Failed to install Node.js v$NODE_MIN_VERSION.x"
        log_message "Trying to install latest LTS version..."
        nvm install --lts

        if [ $? -ne 0 ]; then
            log_message "Error: Failed to install Node.js LTS. Exiting."
            exit 1
        fi
    fi
fi

# ====== Set default Node.js version ======
log_message "Setting latest installed version as NVM default..."

# Get the latest installed version
LATEST_VERSION=$(nvm ls | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | sort -V | tail -1)

if [ -n "$LATEST_VERSION" ]; then
    log_message "Setting $LATEST_VERSION as default Node.js version"
    nvm alias default "$LATEST_VERSION"
    nvm use default
else
    log_message "Warning: Could not determine latest installed Node.js version"
    log_message "Using any available version that's v$NODE_MIN_VERSION or higher"

    # Try to use any version that meets the minimum requirement
    AVAILABLE_VERSIONS=$(nvm ls | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+")
    for VERSION in $AVAILABLE_VERSIONS; do
        MAJOR_VERSION=$(echo "$VERSION" | cut -d '.' -f1 | tr -d 'v')
        if [ "$MAJOR_VERSION" -ge "$NODE_MIN_VERSION" ]; then
            log_message "Setting $VERSION as default Node.js version"
            nvm alias default "$VERSION"
            nvm use default
            break
        fi
    done
fi

# ====== Verify Node.js installation ======
if ! which node > /dev/null 2>&1; then
    log_message "Error: Node.js is not available in PATH after installation"
    exit 1
fi

NODE_VERSION=$(node --version)
log_message "Node.js $NODE_VERSION is being used"

# ====== Install MCP servers via npm ======
log_message "Installing MCP servers via npm..."

# Install npx-based MCP servers
install_npx_mcp_server "firecrawl-mcp" "Firecrawl"
install_npx_mcp_server "@modelcontextprotocol/server-filesystem" "Filesystem"
install_npx_mcp_server "@modelcontextprotocol/server-slack" "Slack"
install_npx_mcp_server "@winor30/mcp-server-datadog" "Datadog"
install_npx_mcp_server "figma-developer-mcp" "Figma"
install_npx_mcp_server "@suekou/mcp-notion-server" "Notion"

# Install uv-based MCP servers
# Rootly MCP Server
rootly_env_content=$(cat << EOF
ROOTLY_API_TOKEN="$ROOTLY_API_TOKEN"
EOF
)
install_uv_mcp_server "$ROOTLY_REPO" "$ROOTLY_INSTALL_DIR" "Rootly" "$ROOTLY_ENV_FILE" "$rootly_env_content"

# Zendesk MCP Server
zendesk_env_content=$(cat << EOF
ZENDESK_EMAIL="$ZENDESK_EMAIL"
ZENDESK_API_KEY="$ZENDESK_API_KEY"
ZENDESK_SUBDOMAIN="$ZENDESK_SUBDOMAIN"
EOF
)
install_uv_mcp_server "$ZENDESK_REPO" "$ZENDESK_INSTALL_DIR" "Zendesk" "$ZENDESK_ENV_FILE" "$zendesk_env_content"

# Gmail MCP Server
install_uv_mcp_server "$GSUITE_REPO" "$GSUITE_INSTALL_DIR" "Gmail" "" ""

# Create auth files if they don't exist
log_message "Creating Gmail auth files if they don't exist..."
touch "$GSUITE_AUTH_FILE"
touch "$GSUITE_ACCOUNTS_FILE"

# Add credentials to credentials.json if they exist
if [ -n "$GMAIL_CLIENT_ID" ] && [ -n "$GMAIL_CLIENT_SECRET" ]; then
    log_message "Creating credentials.json with Gmail credentials..."
    cat > "$GSUITE_INSTALL_DIR/credentials.json" << CREDEOF
{
  "installed": {
    "client_id": "$GMAIL_CLIENT_ID",
    "client_secret": "$GMAIL_CLIENT_SECRET",
    "redirect_uris": ["http://localhost:4000"],
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token"
  }
}
CREDEOF
fi

# Atlassian MCP Server
atlassian_env_content=$(cat << EOF
JIRA_URL="$JIRA_URL"
JIRA_USERNAME="$JIRA_USERNAME"
JIRA_TOKEN="$JIRA_TOKEN"
EOF
)
install_uv_mcp_server "$ATLASSIAN_REPO" "$ATLASSIAN_INSTALL_DIR" "Atlassian" "$ATLASSIAN_ENV_FILE" "$atlassian_env_content"

# Sentry MCP Server
sentry_env_content=$(cat << EOF
SENTRY_AUTH_TOKEN="$SENTRY_AUTH_TOKEN"
SENTRY_ORGANIZATION="$SENTRY_ORGANIZATION"
EOF
)
install_uv_mcp_server "$SENTRY_REPO" "$SENTRY_INSTALL_DIR" "Sentry" "$SENTRY_ENV_FILE" "$sentry_env_content"


# Determine the absolute path to uv
UV_PATH=$(which uv 2>/dev/null)
if [ -z "$UV_PATH" ]; then
    log_message "Warning: Could not find uv in PATH. Using 'uv' as command which may not work if it's not in PATH."
    UV_PATH="uv"
else
    log_message "Found uv at: $UV_PATH"
fi

# Create directories for the configurations
mkdir -p "$MCP_CONFIG_DIR"

# ====== Check if Cursor is installed ======
CURSOR_INSTALLED=false
if [ -d "$CURSOR_APP_PATH" ]; then
    log_message "Cursor IDE is installed. Will create engineering MCP configuration."
    mkdir -p "$CURSOR_CONFIG_DIR"
    CURSOR_INSTALLED=true
else
    log_message "Cursor IDE is not installed. Skipping engineering MCP configuration."
fi

# ====== Create Claude Desktop configuration (Productivity MCPs) ======
log_message "Creating Claude Desktop configuration for productivity MCP servers..."

cat > "$MCP_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "firecrawl": {
      "command": "npx",
      "args": [
        "-y",
        "firecrawl-mcp"
      ],
      "env": {
        "FIRECRAWL_API_KEY": "$FIRECRAWL_API_KEY"
      }
    },
    "rootly": {
      "command": "$UV_PATH",
      "args": [
        "run",
        "--directory",
        "$ROOTLY_INSTALL_DIR",
        "rootly-mcp-server"
      ],
      "env": {
        "ROOTLY_API_TOKEN": "$ROOTLY_API_TOKEN"
      }
    },
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "$HOME/Documents"
      ]
    },
    "slack": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-slack"
      ],
      "env": {
        "SLACK_BOT_TOKEN": "$SLACK_BOT_TOKEN",
        "SLACK_TEAM_ID": "$SLACK_TEAM_ID"
      }
    },
    "zendesk": {
      "command": "$UV_PATH",
      "args": [
        "run",
        "--directory",
        "$ZENDESK_INSTALL_DIR",
        "zendesk"
      ]
    },
    "gmail": {
      "command": "$UV_PATH",
      "args": [
        "run",
        "--directory",
        "$GSUITE_INSTALL_DIR",
        "mcp-gsuite",
        "--gauth-file",
        "$GSUITE_AUTH_FILE",
        "--accounts-file",
        "$GSUITE_ACCOUNTS_FILE",
        "--credentials-file",
        "$GSUITE_INSTALL_DIR"
      ]
    },
    "notion": {
      "command": "npx",
      "args": [
        "-y",
        "@suekou/mcp-notion-server"
      ],
      "env": {
        "NOTION_API_TOKEN": "$NOTION_TOKEN"
      }
    }
  }
}
EOF

log_message "Claude Desktop productivity MCP configuration created at: $MCP_CONFIG_FILE"

# ====== Create Cursor configuration (Engineering MCPs) if Cursor is installed ======
if [ "$CURSOR_INSTALLED" = true ]; then
    log_message "Creating Cursor configuration for engineering MCP servers..."
    
    cat > "$CURSOR_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "rootly": {
      "command": "$UV_PATH",
      "args": [
        "run",
        "--directory",
        "$ROOTLY_INSTALL_DIR",
        "rootly-mcp-server"
      ],
      "env": {
        "ROOTLY_API_TOKEN": "$ROOTLY_API_TOKEN"
      }
    },
    "atlassian": {
      "command": "$UV_PATH",
      "args": [
        "run",
        "--directory",
        "$ATLASSIAN_INSTALL_DIR",
        "mcp-atlassian",
        "--jira-url",
        "$JIRA_URL",
        "--jira-username",
        "$JIRA_USERNAME",
        "--jira-token",
        "$JIRA_TOKEN"
      ]
    },
    "figma": {
      "command": "npx",
      "args": [
        "-y",
        "$FIGMA_PACKAGE_NAME",
        "--figma-api-key=$FIGMA_API_KEY",
        "--stdio"
      ]
    },
    "sentry": {
      "command": "$UV_PATH",
      "args": [
        "run",
        "--directory",
        "$SENTRY_INSTALL_DIR",
        "mcp-sentry",
        "--auth-token",
        "$SENTRY_AUTH_TOKEN",
        "--organization-slug",
        "$SENTRY_ORGANIZATION",
        "--project-slug",
        "$SENTRY_PROJECT"
      ]
    },
    "datadog": {
      "command": "npx",
      "args": [
        "-y",
        "$DATADOG_PACKAGE_NAME"
      ],
      "env": {
        "DATADOG_API_KEY": "$DATADOG_API_KEY",
        "DATADOG_APP_KEY": "$DATADOG_APP_KEY",
        "DATADOG_SITE": "$DATADOG_SITE"
      }
    }
  }
}
EOF

    log_message "Cursor engineering MCP configuration created at: $CURSOR_CONFIG_FILE"
fi

# Print the configurations to stdout for easy copy-paste
echo ""
echo "====== Claude Desktop Configuration (claude_desktop_config.json) ======"
cat "$MCP_CONFIG_FILE"
echo "======================================================================="
echo ""

if [ "$CURSOR_INSTALLED" = true ]; then
    echo "====== Cursor Configuration (mcp.json) ======="
    cat "$CURSOR_CONFIG_FILE"
    echo "=============================================="
    echo ""
fi

# ====== Final verification ======
log_message "========================= INSTALLATION SUMMARY ========================="
log_message "Homebrew: $(which brew)"
log_message "Node.js: $NODE_VERSION ($(which node))"
log_message "npm: $(npm --version) ($(which npm))"
log_message "NVM: Installed at $NVM_DIR"
log_message "Python: $(python3 --version 2>/dev/null || echo 'Not installed') ($(which python3 2>/dev/null || echo 'Not found'))"
log_message "uv: $(uv --version 2>/dev/null | head -n 1 || echo 'Not installed') ($(which uv 2>/dev/null || echo 'Not found'))"
log_message "1Password CLI: $(which op 2>/dev/null || echo 'Not installed')"
log_message "Claude Desktop: $([ -d "$CLAUDE_APP_PATH" ] && echo "Installed at $CLAUDE_APP_PATH" || echo "Not installed")"
log_message "Firecrawl MCP Server: $(npm list -g firecrawl-mcp | grep firecrawl-mcp || echo 'Not found')"
log_message "Rootly MCP Server: $([ -d "$ROOTLY_INSTALL_DIR" ] && echo "Installed at $ROOTLY_INSTALL_DIR" || echo "Not found")"
log_message "Rootly .env file: $([ -f "$ROOTLY_ENV_FILE" ] && echo "Created at $ROOTLY_ENV_FILE" || echo "Not created")"
log_message "Filesystem MCP Server: $(npm list -g @modelcontextprotocol/server-filesystem | grep server-filesystem || echo 'Not found')"
log_message "Slack MCP Server: $(npm list -g @modelcontextprotocol/server-slack | grep server-slack || echo 'Not found')"
log_message "Zendesk MCP Server: $([ -d "$ZENDESK_INSTALL_DIR" ] && echo "Installed at $ZENDESK_INSTALL_DIR" || echo "Not found")"
log_message "Zendesk .env file: $([ -f "$ZENDESK_ENV_FILE" ] && echo "Created at $ZENDESK_ENV_FILE" || echo "Not created")"
log_message "Claude Desktop config (productivity MCPs): $MCP_CONFIG_FILE"
if [ "$CURSOR_INSTALLED" = true ]; then
    log_message "Cursor IDE: Installed at $CURSOR_APP_PATH"
    log_message "Cursor config (engineering MCPs): $CURSOR_CONFIG_FILE"
else
    log_message "Cursor IDE: Not installed, engineering MCP configuration skipped"
fi
log_message "Credentials retrieved from 1Password: $([ "$OP_AVAILABLE" = true ] && echo 'Yes' || echo 'No')"
log_message "Sentry MCP Server: $([ -d "$SENTRY_INSTALL_DIR" ] && echo "Installed at $SENTRY_INSTALL_DIR" || echo "Not found")"
log_message "Sentry .env file: $([ -f "$SENTRY_ENV_FILE" ] && echo "Created at $SENTRY_ENV_FILE" || echo "Not created")"
log_message "======================================================================="

# ====== Check for Claude Code and add engineering MCP servers ======
log_message "Checking for Claude Code (claude-code npm package)..."
if npm list -g claude-code > /dev/null 2>&1; then
    CLAUDE_CODE_INSTALLED=true
    log_message "Claude Code is installed. Adding engineering MCP servers..."
    
    # Only proceed if we have a Cursor configuration to read from
    if [ "$CURSOR_INSTALLED" = true ] && [ -f "$CURSOR_CONFIG_FILE" ]; then
        # Add rootly MCP
        if [ -d "$ROOTLY_INSTALL_DIR" ]; then
            log_message "Adding Rootly MCP to Claude Code..."
            claude mcp add rootly \
                --command "$UV_PATH" \
                --args "run,--directory,$ROOTLY_INSTALL_DIR,rootly-mcp-server" \
                --env ROOTLY_API_TOKEN="$ROOTLY_API_TOKEN"
        fi
            
        # Add atlassian MCP
        if [ -d "$ATLASSIAN_INSTALL_DIR" ]; then
            log_message "Adding Atlassian MCP to Claude Code..."
            claude mcp add atlassian \
                --command "$UV_PATH" \
                --args "run,--directory,$ATLASSIAN_INSTALL_DIR,mcp-atlassian,--jira-url,$JIRA_URL,--jira-username,$JIRA_USERNAME,--jira-token,$JIRA_TOKEN"
        fi
        
        # Add figma MCP
        if npm list -g "$FIGMA_PACKAGE_NAME" > /dev/null 2>&1; then
            log_message "Adding Figma MCP to Claude Code..."
            claude mcp add figma \
                --command "npx" \
                --args "-y,$FIGMA_PACKAGE_NAME,--figma-api-key=$FIGMA_API_KEY,--stdio"
        fi
        
        # Add sentry MCP
        if [ -d "$SENTRY_INSTALL_DIR" ]; then
            log_message "Adding Sentry MCP to Claude Code..."
            claude mcp add sentry \
                --command "$UV_PATH" \
                --args "run,--directory,$SENTRY_INSTALL_DIR,mcp-sentry,--auth-token,$SENTRY_AUTH_TOKEN,--organization-slug,$SENTRY_ORGANIZATION,--project-slug,$SENTRY_PROJECT"
        fi
        
        # Add datadog MCP
        if npm list -g "$DATADOG_PACKAGE_NAME" > /dev/null 2>&1; then
            log_message "Adding Datadog MCP to Claude Code..."
            ENV_ARGS=""
            if [ -n "$DATADOG_API_KEY" ]; then
                ENV_ARGS="$ENV_ARGS --env DATADOG_API_KEY=$DATADOG_API_KEY"
            fi
            if [ -n "$DATADOG_APP_KEY" ]; then
                ENV_ARGS="$ENV_ARGS --env DATADOG_APP_KEY=$DATADOG_APP_KEY"
            fi
            if [ -n "$DATADOG_SITE" ]; then
                ENV_ARGS="$ENV_ARGS --env DATADOG_SITE=$DATADOG_SITE"
            fi
            
            claude mcp add datadog \
                --command "npx" \
                --args "-y,$DATADOG_PACKAGE_NAME" \
                $ENV_ARGS
        fi
        
        log_message "Finished adding engineering MCP servers to Claude Code"
    else
        log_message "No Cursor configuration found. Skipping adding engineering MCPs to Claude Code."
    fi
else
    log_message "Claude Code (claude-code npm package) is not installed. Skipping MCP server configuration for Claude Code."
fi

log_message "Installation complete!"
if [ "$OP_AVAILABLE" = false ]; then
    log_message "NOTE: 1Password CLI was not available or properly set up. You will need to manually update the Claude Desktop configuration file with your API tokens and credentials."
else
    log_message "API keys and credentials were retrieved from 1Password and have been added to the Claude Desktop configuration."
fi

if [ -d "$CLAUDE_APP_PATH" ]; then
    log_message "Claude Desktop is installed. You can start it from the Applications folder."
    log_message "After starting Claude Desktop, the MCP servers will be available."
else
    log_message "Warning: Claude Desktop could not be installed or found. The MCP servers have been installed, but you'll need to manually install Claude Desktop from https://claude.ai/download"
fi

if [ "$CLAUDE_CODE_INSTALLED" = true ]; then
    log_message "Claude Code is configured with engineering MCP servers. You can use them in your development workflow."
fi

exit 0
