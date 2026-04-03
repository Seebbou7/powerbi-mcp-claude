# =============================================================================
# Claude + Power BI MCP + BigQuery DirectQuery - Windows Setup Script
# Run this in PowerShell as Administrator
# =============================================================================

param(
    [string]$DataverseOrgUrl = "",       # e.g. https://yourorg.crm.dynamics.com
    [string]$TenantId = "",              # Your Azure AD Tenant ID (GUID)
    [string]$BigQueryProject = "",       # Your GCP project ID
    [string]$BigQueryDataset = "",       # Your BigQuery dataset name
    [string]$DateTableName = "Date"      # Your date table name in the model
)

$ErrorActionPreference = "Stop"

function Write-Step  { param($msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host "    [FAIL] $msg" -ForegroundColor Red }

Write-Host "  Claude + Power BI MCP - Setup Script v1.0 - BigQuery DirectQuery Edition" -ForegroundColor Magenta

# =============================================================================
# STEP 1 - Check prerequisites
# =============================================================================
Write-Step "Step 1 - Checking prerequisites"

# Node.js
try {
    $nodeVer = node --version 2>$null
    $nodeMajor = [int]($nodeVer -replace 'v','').Split('.')[0]
    if ($nodeMajor -ge 18) {
        Write-OK "Node.js $nodeVer found"
    } else {
        Write-Fail "Node.js $nodeVer is too old. Need v18+. Install from https://nodejs.org"
        exit 1
    }
} catch {
    Write-Fail "Node.js not found. Install from https://nodejs.org then re-run this script."
    exit 1
}

# Git
try {
    $gitVer = git --version 2>$null
    Write-OK "$gitVer found"
} catch {
    Write-Warn "Git not found. Install from https://git-scm.com (optional but recommended)"
}

# VS Code
$vscodePath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
if (Test-Path $vscodePath) {
    Write-OK "VS Code found at $vscodePath"
} else {
    Write-Fail "VS Code not found. Install from https://code.visualstudio.com then re-run."
    exit 1
}

# Claude Desktop
$claudePath  = "$env:LOCALAPPDATA\AnthropicClaude\claude.exe"
$claudePath2 = "$env:LOCALAPPDATA\Programs\claude\claude.exe"
if ((Test-Path $claudePath) -or (Test-Path $claudePath2)) {
    Write-OK "Claude Desktop found"
} else {
    Write-Warn "Claude Desktop not found. Download from https://claude.ai/download"
    Write-Warn "Install it, then re-run this script from Step 3 onwards."
}

# =============================================================================
# STEP 2 - Install VS Code extension for PBI Modeling MCP
# =============================================================================
Write-Step "Step 2 - Installing Power BI Modeling MCP extension in VS Code"

try {
    & $vscodePath --install-extension "analysis-services.powerbi-modeling-mcp" --force 2>&1 | Out-Null
    Write-OK "PBI Modeling MCP extension installed"
} catch {
    Write-Warn "Could not auto-install extension. Install manually:"
    Write-Warn "  VS Code -> Extensions -> Search 'Power BI Modeling MCP' by Microsoft"
}

# =============================================================================
# STEP 3 - Find the MCP server executable
# =============================================================================
Write-Step "Step 3 - Locating powerbi-modeling-mcp.exe"

$extRoot = "$env:USERPROFILE\.vscode\extensions"
$mcpExe = Get-ChildItem $extRoot -Recurse -Filter "powerbi-modeling-mcp.exe" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTime -Descending |
          Select-Object -First 1 -ExpandProperty FullName

if ($mcpExe) {
    Write-OK "Found: $mcpExe"
} else {
    Write-Warn "powerbi-modeling-mcp.exe not found yet."
    Write-Warn "Open VS Code, install the extension, then re-run this script."
    Write-Warn "Or set the path manually in the config file created below."
    $mcpExe = "C:\\PATH\\TO\\powerbi-modeling-mcp.exe"
}

# =============================================================================
# STEP 4 - Build claude_desktop_config.json
# =============================================================================
Write-Step "Step 4 - Writing Claude Desktop config"

$claudeConfigDir  = "$env:APPDATA\Claude"
$claudeConfigPath = "$claudeConfigDir\claude_desktop_config.json"

if (-not (Test-Path $claudeConfigDir)) {
    New-Item -ItemType Directory -Path $claudeConfigDir | Out-Null
}

# Escape backslashes for JSON
$mcpExeJson = $mcpExe -replace '\\', '\\'

if ($DataverseOrgUrl -ne "") {
    $configJson = "{
  `"mcpServers`": {
    `"powerbi-modeling-mcp`": {
      `"type`": `"stdio`",
      `"command`": `"$mcpExeJson`",
      `"args`": [`"--start`"],
      `"env`": {}
    },
    `"dataverse`": {
      `"type`": `"stdio`",
      `"command`": `"npx`",
      `"args`": [`"@microsoft/dataverse`", `"mcp`", `"$DataverseOrgUrl`"]
    }
  }
}"
} else {
    $configJson = "{
  `"mcpServers`": {
    `"powerbi-modeling-mcp`": {
      `"type`": `"stdio`",
      `"command`": `"$mcpExeJson`",
      `"args`": [`"--start`"],
      `"env`": {}
    }
  }
}"
}

$configJson | Set-Content -Path $claudeConfigPath -Encoding UTF8
Write-OK "Config written to: $claudeConfigPath"

# =============================================================================
# STEP 5 - Install Dataverse MCP proxy (if URL provided)
# =============================================================================
if ($DataverseOrgUrl -ne "") {
    Write-Step "Step 5 - Installing Dataverse MCP proxy"
    try {
        npm install -g @microsoft/dataverse 2>&1 | Out-Null
        Write-OK "@microsoft/dataverse installed globally"
    } catch {
        Write-Warn "Could not install @microsoft/dataverse. Run manually: npm install -g @microsoft/dataverse"
    }

    if ($TenantId -ne "") {
        Write-Host ""
        Write-Host "    Admin consent URL (open in browser as tenant admin - one-time only):" -ForegroundColor Yellow
        Write-Host "    https://login.microsoftonline.com/$TenantId/adminconsent?client_id=0c412cc3-0dd6-449b-987f-05b053db9457" -ForegroundColor White
    } else {
        Write-Warn "TenantId not provided. Run script with -TenantId to get the admin consent URL."
    }
} else {
    Write-Step "Step 5 - Skipping Dataverse MCP (no -DataverseOrgUrl provided)"
    Write-Warn "Re-run with -DataverseOrgUrl https://yourorg.crm.dynamics.com to add Dataverse"
}

# =============================================================================
# STEP 6 - Install Claude Code CLI
# =============================================================================
Write-Step "Step 6 - Installing Claude Code CLI"

try {
    npm install -g @anthropic-ai/claude-code 2>&1 | Out-Null
    Write-OK "Claude Code installed globally"
} catch {
    Write-Warn "Could not install Claude Code. Run manually: npm install -g @anthropic-ai/claude-code"
}

# =============================================================================
# STEP 7 - Create CLAUDE.md template in current directory
# =============================================================================
Write-Step "Step 7 - Creating CLAUDE.md model context file"

$bqProject = if ($BigQueryProject) { $BigQueryProject } else { "YOUR_GCP_PROJECT" }
$bqDataset = if ($BigQueryDataset) { $BigQueryDataset } else { "YOUR_DATASET" }
$dateTable = if ($DateTableName)   { $DateTableName   } else { "Date" }

$claudeMdLines = @(
    "# Model context - Claude instructions",
    "# Place this file in the root of your .pbip project folder.",
    "# Claude Code reads it automatically at session start.",
    "",
    "## Data source",
    "- Storage mode: DirectQuery on GCP BigQuery",
    "- BigQuery project: $bqProject",
    "- BigQuery dataset: $bqDataset",
    "- No import mode tables except the Date table",
    "- Date table: $dateTable (Dual storage mode)",
    "",
    "## DAX constraints - STRICT (BigQuery DirectQuery)",
    "- Allowed functions: SUM, COUNT, MIN, MAX, AVERAGE, DIVIDE, IF, SWITCH, COALESCE",
    "- NEVER use: TOTALYTD, DATEADD, SAMEPERIODLASTYEAR, DATESINPERIOD, PREVIOUSMONTH, PREVIOUSYEAR",
    "- For time intelligence: use CALCULATE with explicit FILTER and >= / <= operators on date columns",
    "- NEVER use CTEs in native SQL queries",
    "- NEVER use calculated columns on DirectQuery tables (they run in memory, not BigQuery)",
    "- After writing any measure, run it via DAX query to confirm it executes without error",
    "",
    "## Model conventions",
    "- Fact tables: DirectQuery mode",
    "- Dimension tables: Dual mode",
    "- All measures live in dedicated measure tables, not fact tables",
    "- Measure naming pattern: [Category]_[Metric] e.g. Sales_TotalRevenue, Sales_GrossMargin",
    "- Hide all foreign key columns from report view after creating relationships",
    "",
    "## Performance targets",
    "- Target visual refresh: under 5 seconds per visual",
    "- Flag any measure that triggers a Storage Engine hit instead of a DirectQuery",
    "- Prefer aggregation-aware measures grouped at the highest grain possible",
    "",
    "## Git workflow",
    "- Always save in .pbip format before committing",
    "- Branch naming: feature/[area]-[description]",
    "- Commit after each validated batch of measures",
    "",
    "## Session opener prompt (paste into Claude Desktop each session)",
    "Connect to the open Power BI Desktop file. The model uses DirectQuery",
    "on GCP BigQuery (project: $bqProject, dataset: $bqDataset).",
    "All DAX measures must fold to standard BigQuery SQL.",
    "No time intelligence functions - use explicit date filters instead.",
    "Confirm connection and list all tables and existing measures."
)

$claudeMdLines | Set-Content -Path ".\CLAUDE.md" -Encoding UTF8
Write-OK "CLAUDE.md written to current directory"

# =============================================================================
# STEP 8 - Add PBI MCP to Claude Code
# =============================================================================
Write-Step "Step 8 - Registering PBI MCP with Claude Code"

if ($mcpExe -and (Test-Path $mcpExe)) {
    try {
        $mcpExeEscaped = $mcpExe
        claude mcp add --transport stdio powerbi-modeling-mcp `
            --env PBI_MODELING_MCP_CLIENT_ID=ea0616ba-638b-4df5-95b9-636659ae5121 `
            -- $mcpExeEscaped --start 2>&1 | Out-Null
        Write-OK "PBI MCP registered with Claude Code"
    } catch {
        Write-Warn "Could not auto-register. Run manually after install:"
        Write-Warn "  claude mcp add --transport stdio powerbi-modeling-mcp ``"
        Write-Warn "    --env PBI_MODELING_MCP_CLIENT_ID=ea0616ba-638b-4df5-95b9-636659ae5121 ``"
        Write-Warn "    -- `"$mcpExe`" --start"
    }
} else {
    Write-Warn "Skipping Claude Code MCP registration - exe not found yet."
}

# =============================================================================
# STEP 9 - Power BI Desktop checklist reminder
# =============================================================================
Write-Step "Step 9 - Manual steps required in Power BI Desktop"

Write-Host ""
Write-Host "    Do these manually in Power BI Desktop (File -> Options -> Preview features):" -ForegroundColor White
Write-Host ""
Write-Host "    [_] Enable: Power BI Project (.pbip) save format" -ForegroundColor White
Write-Host "    [_] Enable: XMLA endpoint" -ForegroundColor White
Write-Host "    [_] Enable: Use new Google BigQuery connector implementation (ADBC)" -ForegroundColor White
Write-Host "    [_] Restart Power BI Desktop after enabling" -ForegroundColor White
Write-Host "    [_] Resave your model as File -> Save as -> Power BI Project (.pbip)" -ForegroundColor White
Write-Host ""

# =============================================================================
# DONE
# =============================================================================
Write-Host ""
Write-Host "=============================================================================" -ForegroundColor Green
Write-Host "  SETUP COMPLETE" -ForegroundColor Green
Write-Host "=============================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "  1. Open Power BI Desktop and enable the preview features listed above" -ForegroundColor White
Write-Host "  2. Open your .pbip model file in Power BI Desktop" -ForegroundColor White
Write-Host "  3. Fully exit and reopen Claude Desktop (tray icon -> Exit)" -ForegroundColor White
Write-Host "  4. Paste the Session Opener prompt from CLAUDE.md into Claude Desktop" -ForegroundColor White
Write-Host "  5. Claude should list your model tables - you are live!" -ForegroundColor White
Write-Host ""
Write-Host "  Config file : $claudeConfigPath" -ForegroundColor White
Write-Host "  CLAUDE.md   : $((Get-Item .\CLAUDE.md).FullName)" -ForegroundColor White
Write-Host ""
Write-Host "  To add Dataverse later, re-run:" -ForegroundColor White
Write-Host "  .\setup_claude_pbi_mcp.ps1 -DataverseOrgUrl https://yourorg.crm.dynamics.com -TenantId YOUR_TENANT_ID" -ForegroundColor White
Write-Host "=============================================================================" -ForegroundColor Green
