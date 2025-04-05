# MCP Server Installation Script

This script automates the installation and configuration of various Model Context Protocol (MCP) servers for use with Claude Desktop. It handles the installation of dependencies (Homebrew, Node.js, Python, uv) and sets up multiple MCP servers.

## Secrets Management

### 1Password Integration

The script integrates with 1Password to securely retrieve API keys and credentials. This approach avoids hardcoding sensitive information in the script or configuration files.

#### Requirements:

- 1Password CLI (`op`) must be installed and accessible
- You must be signed in to 1Password CLI
- A vault named `MCP` must exist in your 1Password account
- Required credentials must be stored in this vault as described below

If 1Password is not available or properly set up, the script will use empty placeholders and notify you to manually update the credentials later.

#### Required Credentials per MCP Server

Each MCP server requires specific credentials to be stored in the 1Password `MCP` vault:

1. **Firecrawl**
   - Item name: `Firecrawl`
   - Fields:
     - `api_key`: Your Firecrawl API key

2. **Zendesk**
   - Item name: `Zendesk`
   - Fields:
     - `username`: Your Zendesk email
     - `api_token`: Your Zendesk API token
     - `subdomain`: Your Zendesk subdomain (e.g., `company.zendesk.com`)

3. **Slack**
   - Item name: `Slack`
   - Fields:
     - `bot_token`: Your Slack bot token
     - `team_id`: Your Slack team ID

4. **Gmail**
   - Item name: `Gmail`
   - Fields:
     - `client_id`: Your Google API client ID
     - `client_secret`: Your Google API client secret

5. **Atlassian**
   - Item name: `Atlassian`
   - Fields:
     - `url`: Your Jira URL
     - `username`: Your Jira username/email
     - `token`: Your Jira API token

6. **Notion**
   - Item name: `Notion`
   - Fields:
     - `token`: Your Notion API token

### Manual Configuration

If you don't have 1Password or prefer to configure credentials manually:

1. Run the script without 1Password integration
2. Edit the generated `.env` files in each MCP server's directory
3. Edit the Claude Desktop configuration file at `~/Library/Application Support/Claude/claude_desktop_config.json`

## Running the Script

### Prerequisites

- macOS (works on both Intel and Apple Silicon)

### Installation Steps

1. Download the script to your local machine
   ```bash
   curl -o mcp.sh https://path/to/mcp.sh
   ```

2. Make the script executable
   ```bash
   chmod +x mcp.sh
   ```

3. Run the script
   ```bash
   ./mcp.sh
   ```

4. The script will:
   - Install or update Homebrew
   - Install Python 3.12+ and uv
   - Install Node.js v23+ via NVM
   - Download and install Claude Desktop (if not already installed)
   - Install 1Password CLI (if not already installed)
   - Install and configure all MCP servers
   - Create the necessary configuration files

5. Review the installation summary at the end for any warnings or issues

### Log File

The script logs all operations to `~/Library/Logs/mcp_installation_script.log`. Check this file if you encounter any issues.

### After Installation

1. Start Claude Desktop from the Applications folder
2. The MCP servers will be available for use with Claude
3. If any credentials were missing, update them in the appropriate `.env` files or in the Claude Desktop configuration

## Troubleshooting

- If the script fails to install any dependencies, try installing them manually
- Ensure you have proper permissions for directories being accessed
- Check the log file for specific error messages
- If a specific MCP server fails to install, you can try running that portion of the script manually 