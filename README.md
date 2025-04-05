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

## Token Generation Guide

This section provides detailed instructions on how to obtain API tokens and credentials for each MCP server.

### Quick Reference

| MCP Server | Token Creation Method | Token Type | API Documentation |
|------------|----------------------|------------|-------------------|
| Firecrawl | Manual via Dashboard | API Key | [Docs](https://firecrawl.dev/docs/api) |
| Slack | Manual via Developer Portal | Bot Token (OAuth) | [Docs](https://api.slack.com/authentication/oauth-v2) |
| Zendesk | Manual via Admin Console | API Token | [Docs](https://developer.zendesk.com/api-reference/introduction/security-and-auth/) |
| Gmail | Manual via Google Cloud Console | OAuth Client ID/Secret | [Docs](https://developers.google.com/gmail/api/auth/about-auth) |
| Atlassian | Manual via Account Settings | API Token | [Docs](https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/#authentication) |
| Figma | Manual via User Settings | Personal Access Token | [Docs](https://www.figma.com/developers/api#access-tokens) |
| Notion | Manual via Integrations Portal | Integration Token | [Docs](https://developers.notion.com/docs/authorization) |
| Sentry | Manual or API | Auth Token | [Docs](https://docs.sentry.io/api/auth/) |
| Datadog | Manual or API | API Key & App Key | [Docs](https://docs.datadoghq.com/account_management/api-app-keys/) |

### Firecrawl

1. Sign in to your Firecrawl account at [https://firecrawl.dev](https://firecrawl.dev)
2. Navigate to Account Settings → API Keys
3. Click "Create New API Key"
4. Enter a name for your key (e.g., "Claude MCP")
5. Select the appropriate permissions based on your needs
6. Copy the generated API key and store it securely (it will only be shown once)
7. Add the key to your 1Password vault with item name "Firecrawl" and field name "api_key"

### Slack

1. Go to [https://api.slack.com/apps](https://api.slack.com/apps)
2. Click "Create New App" and select "From scratch"
3. Name your app (e.g., "Claude MCP") and select your workspace
4. Click "Create App"
5. In the left sidebar, navigate to "OAuth & Permissions"
6. Under "Bot Token Scopes", add the following scopes:
   - `channels:history`
   - `channels:read`
   - `chat:write`
   - `files:read`
   - `groups:history`
   - `groups:read`
   - `im:history`
   - `im:read`
   - `mpim:history`
   - `mpim:read`
   - `team:read`
   - `users:read`
7. Scroll to the top and click "Install to Workspace"
8. After installing, copy the "Bot User OAuth Token" (starts with `xoxb-`)
9. To get your Team ID, right-click on your workspace name in Slack and select "Copy link"
   - The link will look like `https://app.slack.com/client/T01234ABCDE/...`
   - Your Team ID is the part that starts with T (e.g., `T01234ABCDE`)
10. Add these to your 1Password vault with item name "Slack" and field names "bot_token" and "team_id"

### Zendesk

1. Sign in to your Zendesk account as an admin
2. Click on the Admin icon (gear) in the sidebar
3. Under "Channels", select "API"
4. Click the "Add API Token" button
5. Enter a descriptive name for the token (e.g., "Claude MCP")
6. Copy the generated token (it will only be shown once)
7. Note your Zendesk subdomain from your URL (e.g., `company.zendesk.com`)
8. Add these to your 1Password vault with item name "Zendesk" and field names "api_token", "username" (your Zendesk email), and "subdomain"

### Gmail (Google API)

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable the Gmail API for your project:
   - Navigate to "APIs & Services" → "Library"
   - Search for "Gmail API" and enable it
4. Set up OAuth consent screen:
   - Go to "APIs & Services" → "OAuth consent screen"
   - Select "User Type" (Internal or External)
   - Fill in the required information
   - Add necessary scopes for Gmail (e.g., `https://www.googleapis.com/auth/gmail.readonly`)
   - Add test users if using External
5. Create OAuth client ID:
   - Go to "APIs & Services" → "Credentials"
   - Click "Create Credentials" → "OAuth client ID"
   - Select "Web application" as the application type
   - Add authorized redirect URIs (e.g., `http://localhost:4100/code`)
   - Click "Create"
6. Download the JSON file containing your client ID and client secret
7. Add these to your 1Password vault with item name "Gmail" and field names "client_id" and "client_secret"

### Atlassian (Jira/Confluence)

1. Sign in to your Atlassian account
2. Go to [https://id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
3. Click "Create API token"
4. Enter a label for your token (e.g., "Claude MCP")
5. Click "Create"
6. Copy the generated token (it will only be shown once)
7. Note your Jira URL (e.g., `https://your-company.atlassian.net`)
8. Add these to your 1Password vault with item name "Atlassian" and field names "url", "username" (your Atlassian email), and "token"

### Figma

1. Log in to your Figma account
2. Click on your profile picture in the top-right corner
3. Select "Settings"
4. Scroll to the "Personal access tokens" section
5. Click "Generate new token"
6. Enter a name for your token (e.g., "Claude MCP")
7. Click "Generate token"
8. Copy the generated token (it will only be shown once)
9. Add the token to your 1Password vault with item name "Figma" and field name "api_key"

### Notion

1. Log in to your Notion account
2. Go to [https://www.notion.so/my-integrations](https://www.notion.so/my-integrations)
3. Click "New integration"
4. Fill in the following information:
   - Name your integration (e.g., "Claude MCP")
   - Select the workspace to associate with this integration
   - Upload an icon (optional)
5. Click "Submit"
6. On the next page, find your "Internal Integration Token"
7. Copy the token
8. Important: You will need to share any Notion pages/databases with your integration for it to access them
   - Open the Notion page you want to share
   - Click "Share" in the top-right corner
   - Use the "@" symbol to mention your integration and invite it
9. Add the token to your 1Password vault with item name "Notion" and field name "token"

### Sentry

1. Sign in to your Sentry account
2. Navigate to Settings (the gear icon) → Account → API Keys
3. Click "Create New API Key"
4. Enter a name for the key (e.g., "Claude MCP")
5. Select the appropriate scopes based on your needs
6. Click "Create Key"
7. Copy the generated auth token (it will only be shown once)
8. Add the token to your 1Password vault with item name "Sentry" and field names "auth_token", "project" and "organization" (your Sentry organization slug)

### Datadog

1. Sign in to your Datadog account
2. Navigate to Organization Settings → API Keys
3. Click "New Key"
4. Enter a name for the key (e.g., "Claude MCP API Key")
5. Click "Create"
6. Copy the generated API key
7. Navigate to Organization Settings → Application Keys
8. Click "New Key"
9. Enter a name for the key (e.g., "Claude MCP Application Key")
10. Click "Create"
11. Copy the generated Application key
12. Add these to your 1Password vault with item name "Datadog" and field names "api_key" and "app_key"

### Alternative Storage for Tokens (Without 1Password)

If you're not using 1Password, you can store your tokens in the following locations:

1. **For Productivity MCPs** (Claude Desktop):
   - Edit `~/Library/Application Support/Claude/claude_desktop_config.json`
   - Update the environment variables in each MCP server's configuration
   
   Example for Slack:
   ```json
   "slack": {
     "command": "npx",
     "args": [
       "-y",
       "@modelcontextprotocol/server-slack"
     ],
     "env": {
       "SLACK_BOT_TOKEN": "xoxb-your-token-here",
       "SLACK_TEAM_ID": "T01234ABCDE"
     }
   }
   ```

2. **For Engineering MCPs** (Cursor IDE):
   - Edit `~/.cursor/mcp.json`
   - Update the environment variables in each MCP server's configuration
   
   Example for Figma:
   ```json
   "figma": {
     "command": "npx",
     "args": [
       "-y",
       "figma-developer-mcp",
       "--figma-api-key=your-api-key-here",
       "--stdio"
     ]
   }
   ```

3. **For Repository-based MCP servers**:
   - Update the `.env` file in the server's directory
   
   Example for Atlassian (`~/mcp-atlassian/.env`):
   ```
   JIRA_URL="https://your-company.atlassian.net"
   JIRA_USERNAME="your.email@example.com"
   JIRA_TOKEN="your-api-token"
   ```

Remember to keep your tokens secure and never share them publicly.

## Running the Script

### Prerequisites

- macOS (works on both Intel and Apple Silicon)

### Installation Steps

1. Download the script to your local machine
   ```bash
   curl -s https://raw.githubusercontent.com/drdee/mcp-installer/refs/heads/main/mcp.sh | bash
   ```

2. The script will:
   - Install or update Homebrew
   - Install Python 3.12+ and uv
   - Install Node.js v23+ via NVM
   - Download and install Claude Desktop (if not already installed)
   - Install 1Password CLI (if not already installed)
   - Install and configure all MCP servers
   - Create the necessary configuration files

3. Review the installation summary at the end for any warnings or issues

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