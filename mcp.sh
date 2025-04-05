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
OP_VAULT="MCP"  # The name of the 1Password vault containing MCP credentials
CLAUDE_DESKTOP_URL="https://claude.ai/download"
CLAUDE_DOWNLOAD_DIR="$HOME/Downloads"
CLAUDE_APP_PATH="/Applications/Claude.app"

# Zendesk MCP server configuration
ZENDESK_REPO="https://github.com/reminia/zendesk-mcp-server.git"
ZENDESK_INSTALL_DIR="$HOME/zendesk-mcp-server"
ZENDESK_ENV_FILE="$ZENDESK_INSTALL_DIR/.env"

# GSuite MCP server configuration
GSUITE_REPO="https://github.com/MarkusPfundstein/mcp-gsuite.git"
GSUITE_INSTALL_DIR="$HOME/mcp-gsuite"
GSUITE_AUTH_FILE="$GSUITE_INSTALL_DIR/.gauth.json"
GSUITE_ACCOUNTS_FILE="$GSUITE_INSTALL_DIR/.accounts.json"

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

    # Get Firecrawl API Key
    FIRECRAWL_API_KEY=$(get_1password_item "Firecrawl" "api_key")
    if [ -n "$FIRECRAWL_API_KEY" ]; then
        log_message "Retrieved Firecrawl API key successfully"
    else
        log_message "Could not retrieve Firecrawl API key. A placeholder will be used in the configuration."
        FIRECRAWL_API_KEY=""
    fi

    # Get Zendesk credentials
    ZENDESK_EMAIL=$(get_1password_item "Zendesk" "username")
    ZENDESK_API_KEY=$(get_1password_item "Zendesk" "api_token")
    ZENDESK_SUBDOMAIN=$(get_1password_item "Zendesk" "subdomain")

    if [ -n "$ZENDESK_API_KEY" ]; then
        log_message "Retrieved Zendesk credentials successfully"
    else
        log_message "Could not retrieve Zendesk credentials. Placeholders will be used in the configuration."
        ZENDESK_EMAIL="abc"
        ZENDESK_API_KEY="def"
        ZENDESK_SUBDOMAIN="wealthsimple.zendesk.com"
    fi

    # Get Slack credentials
    SLACK_BOT_TOKEN=$(get_1password_item "Slack" "bot_token")
    SLACK_TEAM_ID=$(get_1password_item "Slack" "team_id")

    if [ -n "$SLACK_BOT_TOKEN" ]; then
        log_message "Retrieved Slack credentials successfully"
    else
        log_message "Could not retrieve Slack credentials. Placeholders will be used in the configuration."
        SLACK_BOT_TOKEN=""
        SLACK_TEAM_ID=""
    fi

    # Get Gmail credentials
    GMAIL_CLIENT_ID=$(get_1password_item "Gmail" "client_id")
    GMAIL_CLIENT_SECRET=$(get_1password_item "Gmail" "client_secret")

    if [ -n "$GMAIL_CLIENT_ID" ] && [ -n "$GMAIL_CLIENT_SECRET" ]; then
        log_message "Retrieved Gmail credentials successfully"
    else
        log_message "Could not retrieve Gmail credentials. Empty placeholders will be used."
        GMAIL_CLIENT_ID=""
        GMAIL_CLIENT_SECRET=""
    fi
else
    # Set placeholders if 1Password is not available
    FIRECRAWL_API_KEY=""
    ZENDESK_EMAIL=""
    ZENDESK_API_KEY="def"
    ZENDESK_SUBDOMAIN=""
    SLACK_BOT_TOKEN=""
    SLACK_TEAM_ID=""
    GMAIL_CLIENT_ID=""
    GMAIL_CLIENT_SECRET=""
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

# Install @smithery/cli first
log_message "Installing @smithery/cli..."
npm install -g @smithery/cli

# Check @smithery/cli installation
if npm list -g @smithery/cli > /dev/null 2>&1; then
    log_message "@smithery/cli installed successfully"
else
    log_message "Warning: @smithery/cli installation may have failed"
fi

# Install Firecrawl MCP Server
log_message "Installing Firecrawl MCP Server from GitHub..."
npm install -g firecrawl-mcp

# Check Firecrawl MCP Server installation
if npm list -g firecrawl-mcp > /dev/null 2>&1; then
    log_message "Firecrawl MCP Server installed successfully"
else
    log_message "Warning: Firecrawl MCP Server installation may have failed"
fi

# Install Filesystem MCP Server
log_message "Installing Filesystem MCP Server..."
npm install -g @modelcontextprotocol/server-filesystem

# Check Filesystem MCP Server installation
if npm list -g @modelcontextprotocol/server-filesystem > /dev/null 2>&1; then
    log_message "Filesystem MCP Server installed successfully"
else
    log_message "Warning: Filesystem MCP Server installation may have failed"
fi

# Install Slack MCP Server
log_message "Installing Slack MCP Server..."
npm install -g @modelcontextprotocol/server-slack

# Check Slack MCP Server installation
if npm list -g @modelcontextprotocol/server-slack > /dev/null 2>&1; then
    log_message "Slack MCP Server installed successfully"
else
    log_message "Warning: Slack MCP Server installation may have failed"
fi

# Install Zendesk MCP Server from GitHub
log_message "Installing Zendesk MCP Server from GitHub..."

# Clone the repository
if [ -d "$ZENDESK_INSTALL_DIR" ]; then
    log_message "Zendesk MCP Server directory already exists, updating..."
    cd "$ZENDESK_INSTALL_DIR"
    git pull
else
    log_message "Cloning Zendesk MCP Server repository..."
    git clone "$ZENDESK_REPO" "$ZENDESK_INSTALL_DIR"
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to clone Zendesk MCP Server repository"
    else
        log_message "Zendesk MCP Server repository cloned successfully"
        cd "$ZENDESK_INSTALL_DIR"
    fi
fi

# Build using uv
if [ -d "$ZENDESK_INSTALL_DIR" ]; then
    log_message "Building Zendesk MCP Server using uv..."
    cd "$ZENDESK_INSTALL_DIR"
    uv build

    if [ $? -ne 0 ]; then
        log_message "Error: Failed to build Zendesk MCP Server using uv"
    else
        log_message "Zendesk MCP Server built successfully using uv"

        # Create .env file with Zendesk credentials
        log_message "Creating .env file with Zendesk credentials..."
        cat > "$ZENDESK_ENV_FILE" << ENVEOF
ZENDESK_EMAIL="$ZENDESK_EMAIL"
ZENDESK_API_KEY="$ZENDESK_API_KEY"
ZENDESK_SUBDOMAIN="$ZENDESK_SUBDOMAIN"
ENVEOF

        log_message "Zendesk .env file created at $ZENDESK_ENV_FILE"
    fi
fi

# Install Gmail MCP Server from GitHub using uv
log_message "Installing Gmail MCP Server from GitHub using uv..."

# Clone the repository
if [ -d "$GSUITE_INSTALL_DIR" ]; then
    log_message "Gmail MCP Server directory already exists, updating..."
    cd "$GSUITE_INSTALL_DIR"
    git pull
else
    log_message "Cloning Gmail MCP Server repository..."
    git clone "$GSUITE_REPO" "$GSUITE_INSTALL_DIR"
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to clone Gmail MCP Server repository"
    else
        log_message "Gmail MCP Server repository cloned successfully"
        cd "$GSUITE_INSTALL_DIR"
    fi
fi

# Create auth files if they don't exist
log_message "Creating Gmail auth files if they don't exist..."
touch "$GSUITE_AUTH_FILE"
touch "$GSUITE_ACCOUNTS_FILE"

# Build using uv
if [ -d "$GSUITE_INSTALL_DIR" ]; then
    log_message "Building Gmail MCP Server using uv..."
    cd "$GSUITE_INSTALL_DIR"

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

    # Install dependencies using uv
    uv build

    if [ $? -ne 0 ]; then
        log_message "Error: Failed to build Gmail MCP Server using uv"
    else
        log_message "Gmail MCP Server built successfully using uv"
    fi
fi

# Create a directory for the Claude Desktop configuration
mkdir -p "$MCP_CONFIG_DIR"

# ====== Create Claude Desktop configuration ======
log_message "Creating Claude Desktop configuration..."

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
      "command": "/Users/dvanliere/.local/bin/uv",
      "args": [
        "run",
        "--directory",
        "$ZENDESK_INSTALL_DIR",
        "zendesk"
      ]
    },
    "gmail": {
      "command": "/Users/dvanliere/.local/bin/uv",
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
    }
  }
}
EOF

# Print the configuration to stdout for easy copy-paste
log_message "Claude Desktop configuration created at: $MCP_CONFIG_FILE"
echo ""
echo "====== Claude Desktop Configuration (claude_desktop_config.json) ======"
cat "$MCP_CONFIG_FILE"
echo "======================================================================"
echo ""
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
log_message "Filesystem MCP Server: $(npm list -g @modelcontextprotocol/server-filesystem | grep server-filesystem || echo 'Not found')"
log_message "Slack MCP Server: $(npm list -g @modelcontextprotocol/server-slack | grep server-slack || echo 'Not found')"
log_message "@smithery/cli: $(npm list -g @smithery/cli | grep @smithery/cli || echo 'Not found')"
log_message "Zendesk MCP Server: $([ -d "$ZENDESK_INSTALL_DIR" ] && echo "Installed at $ZENDESK_INSTALL_DIR" || echo "Not found")"
log_message "Zendesk .env file: $([ -f "$ZENDESK_ENV_FILE" ] && echo "Created at $ZENDESK_ENV_FILE" || echo "Not created")"
log_message "Gmail MCP Server: $([ -d "$GSUITE_INSTALL_DIR" ] && echo "Installed at $GSUITE_INSTALL_DIR" || echo "Not found")"
log_message "Gmail auth files: $([ -f "$GSUITE_AUTH_FILE" ] && echo "Created at $GSUITE_AUTH_FILE" || echo "Not created")"
log_message "Claude Desktop config: $MCP_CONFIG_FILE"
log_message "Credentials retrieved from 1Password: $([ "$OP_AVAILABLE" = true ] && echo 'Yes' || echo 'No')"
log_message "======================================================================="
log_message "Installation complete!"
if [ "$OP_AVAILABLE" = false ]; then
    log_message "NOTE: 1Password CLI was not available or properly set up. You will need to manually update the Claude Desktop configuration file with your API tokens and credentials."
    log_message "You should also update the Zendesk .env file at $ZENDESK_ENV_FILE with your Zendesk credentials."
else
    log_message "API keys and credentials were retrieved from 1Password and have been added to the Claude Desktop configuration."
    log_message "Zendesk credentials have been added to $ZENDESK_ENV_FILE"
fi

if [ -d "$CLAUDE_APP_PATH" ]; then
    log_message "Claude Desktop is installed. You can start it from the Applications folder."
    log_message "After starting Claude Desktop, the MCP servers will be available."
else
    log_message "Warning: Claude Desktop could not be installed or found. The MCP servers have been installed, but you'll need to manually install Claude Desktop from https://claude.ai/download"
fi

exit 0
