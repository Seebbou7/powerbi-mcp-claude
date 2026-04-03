# =============================================================================
# connect_pbi_mcp.ps1
# Automates the full Power BI MCP registration and connection workflow.
#
# Usage:
#   .\connect_pbi_mcp.ps1
#   .\connect_pbi_mcp.ps1 -ExePath "C:\custom\path\powerbi-modeling-mcp.exe"
#   .\connect_pbi_mcp.ps1 -Force       # Re-register even if already registered
#   .\connect_pbi_mcp.ps1 -Unregister  # Remove the MCP server from Claude Code
#
# Steps performed:
#   1. Verifies Claude Code CLI is installed
#   2. Locates powerbi-modeling-mcp.exe (local repo -> VS Code extensions -> PATH)
#   3. Checks if already registered with Claude Code
#   4. Registers the MCP server if needed
#   5. Verifies the registration
#   6. Scans for running Power BI Desktop instances
# =============================================================================

param(
    [string]$ExePath    = "",
    [switch]$Force      = $false,
    [switch]$Unregister = $false
)

$ErrorActionPreference = "Stop"

$MCP_SERVER_NAME = "powerbi-modeling-mcp"
$MCP_CLIENT_ID   = "ea0616ba-638b-4df5-95b9-636659ae5121"
$MCP_ARGS        = "--start"

function Write-Step { param($msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "    [OK]   $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "    [WARN] $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "    [FAIL] $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "    [INFO] $msg" -ForegroundColor Gray }

Write-Host ""
Write-Host "  Power BI MCP -- Claude Code Connection Script" -ForegroundColor Magenta
Write-Host "  ==============================================" -ForegroundColor Magenta
Write-Host ""

# =============================================================================
# STEP 1 -- Verify Claude Code CLI is installed
# =============================================================================
Write-Step "Step 1 -- Checking Claude Code CLI"

try {
    $claudeVersion = & claude --version 2>&1
    Write-OK "Claude Code found: $claudeVersion"
} catch {
    Write-Err "Claude Code CLI not found. Install with: npm install -g @anthropic-ai/claude-code"
    exit 1
}

# =============================================================================
# STEP 2 -- Handle -Unregister flag
# =============================================================================
if ($Unregister) {
    Write-Step "Step 2 -- Unregistering Power BI MCP server"
    try {
        & claude mcp remove $MCP_SERVER_NAME 2>&1 | Out-Null
        Write-OK "MCP server '$MCP_SERVER_NAME' removed from Claude Code."
    } catch {
        Write-Warn "Could not remove '$MCP_SERVER_NAME' (may not have been registered)."
    }
    exit 0
}

# =============================================================================
# STEP 3 -- Locate powerbi-modeling-mcp.exe
# =============================================================================
Write-Step "Step 3 -- Locating powerbi-modeling-mcp.exe"

$resolvedExe = $null

# Priority 1: Explicit -ExePath parameter
if ($ExePath -ne "" -and (Test-Path $ExePath)) {
    $resolvedExe = $ExePath
    Write-OK "Using provided path: $resolvedExe"
}

# Priority 2: Sibling directory in this repo (powerbi-mcp-ext\extension\server\)
if (-not $resolvedExe) {
    $siblingPath = Join-Path $PSScriptRoot "powerbi-mcp-ext\extension\server\powerbi-modeling-mcp.exe"
    if (Test-Path $siblingPath) {
        $resolvedExe = $siblingPath
        Write-OK "Found in repo folder: $resolvedExe"
    }
}

# Priority 3: VS Code extensions folder (installed via Marketplace)
if (-not $resolvedExe) {
    $extRoot = "$env:USERPROFILE\.vscode\extensions"
    if (Test-Path $extRoot) {
        $found = Get-ChildItem $extRoot -Recurse -Filter "powerbi-modeling-mcp.exe" -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending |
                 Select-Object -First 1 -ExpandProperty FullName
        if ($found) {
            $resolvedExe = $found
            Write-OK "Found in VS Code extensions: $resolvedExe"
        }
    }
}

# Priority 4: System PATH
if (-not $resolvedExe) {
    $inPath = Get-Command "powerbi-modeling-mcp.exe" -ErrorAction SilentlyContinue
    if ($inPath) {
        $resolvedExe = $inPath.Source
        Write-OK "Found in PATH: $resolvedExe"
    }
}

if (-not $resolvedExe) {
    Write-Err "powerbi-modeling-mcp.exe not found."
    Write-Warn "Options:"
    Write-Warn "  1. Run: .\connect_pbi_mcp.ps1 -ExePath 'C:\full\path\to\powerbi-modeling-mcp.exe'"
    Write-Warn "  2. Install the VS Code extension 'Power BI Modeling MCP' (by Microsoft), then re-run."
    Write-Warn "  3. Download the .vsix from: https://github.com/microsoft/powerbi-modeling-mcp"
    exit 1
}

# =============================================================================
# STEP 4 -- Check existing registration
# =============================================================================
Write-Step "Step 4 -- Checking Claude Code MCP registry"

$mcpList = & claude mcp list 2>&1
$alreadyRegistered = ($mcpList | Out-String) -match [regex]::Escape($MCP_SERVER_NAME)

if ($alreadyRegistered -and -not $Force) {
    Write-OK "MCP server '$MCP_SERVER_NAME' is already registered."
    Write-Info "Use -Force to re-register with updated settings."
} else {
    # =========================================================================
    # STEP 5 -- Register the MCP server
    # =========================================================================
    Write-Step "Step 5 -- Registering Power BI MCP server with Claude Code"

    if ($alreadyRegistered -and $Force) {
        Write-Info "Removing existing registration before re-registering..."
        try { & claude mcp remove $MCP_SERVER_NAME 2>&1 | Out-Null } catch {}
    }

    $envArg = "PBI_MODELING_MCP_CLIENT_ID=$MCP_CLIENT_ID"
    $result = & claude mcp add --transport stdio $MCP_SERVER_NAME --env $envArg -- $resolvedExe $MCP_ARGS 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-OK "MCP server registered successfully."
    } else {
        Write-Err "Failed to register MCP server: $result"
        exit 1
    }
}

# =============================================================================
# STEP 6 -- Verify registration
# =============================================================================
Write-Step "Step 6 -- Verifying registration"

$verifyList = (& claude mcp list 2>&1) | Out-String
if ($verifyList -match [regex]::Escape($MCP_SERVER_NAME)) {
    Write-OK "Verified: '$MCP_SERVER_NAME' is active in Claude Code."
} else {
    Write-Err "Registration verification failed. Run 'claude mcp list' to diagnose."
    exit 1
}

# =============================================================================
# STEP 7 -- Discover running Power BI Desktop instances
# =============================================================================
Write-Step "Step 7 -- Scanning for running Power BI Desktop instances"

$pbiProcesses = Get-Process -Name "PBIDesktop" -ErrorAction SilentlyContinue
if ($pbiProcesses) {
    Write-OK "Found $($pbiProcesses.Count) Power BI Desktop instance(s) running:"
    foreach ($p in $pbiProcesses) {
        Write-Info "  PID $($p.Id) -- Title: '$($p.MainWindowTitle)'"
    }
} else {
    Write-Warn "No Power BI Desktop processes found."
    Write-Warn "Open a .pbip file in Power BI Desktop, then re-run this script or start Claude Code."
}

# =============================================================================
# DONE
# =============================================================================
Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "  SETUP COMPLETE -- Ready to use in Claude Code" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  MCP Server : $MCP_SERVER_NAME" -ForegroundColor White
Write-Host "  Executable : $resolvedExe" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "  1. Make sure your .pbip file is open in Power BI Desktop" -ForegroundColor White
Write-Host "  2. Start a new Claude Code session in this folder:" -ForegroundColor White
Write-Host "       cd ""$PSScriptRoot""" -ForegroundColor Gray
Write-Host "       claude" -ForegroundColor Gray
Write-Host "  3. Paste this session opener prompt into Claude Code:" -ForegroundColor White
Write-Host ""
Write-Host "     Connect to the open Power BI Desktop file through mcp." -ForegroundColor Yellow
Write-Host ""
Write-Host "  To unregister later:" -ForegroundColor White
Write-Host "       .\connect_pbi_mcp.ps1 -Unregister" -ForegroundColor Gray
Write-Host ""
