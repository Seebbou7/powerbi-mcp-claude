# Power BI MCP — Claude Code Integration

Connect Claude Code directly to a live Power BI Desktop semantic model via the **Power BI Modeling MCP Server**. Write, validate, and deploy DAX measures using natural language — with full awareness of your model's tables, relationships, and constraints.

---

## What this repo provides

| File | Purpose |
|---|---|
| `connect_pbi_mcp.ps1` | One-shot script: registers the MCP server with Claude Code, locates the exe, and discovers running Power BI Desktop instances |
| `setup_claude_pbi_mcp.ps1` | Full first-time environment setup (Node.js check, VS Code extension install, Claude Desktop config, Claude Code CLI install) |
| `CLAUDE.md` | Project memory — auto-read by Claude Code at every session start. Contains model structure, known issues, DAX constraints, and conventions |
| `powerbi-mcp-ext/` | VS Code extension source for the Power BI Modeling MCP Server |
| `powerbi-modeling-mcp/` | Upstream MCP server reference |
| `PowerBI_Figma_Theme.json` | Figma theme file matching the Power BI report colour palette |

---

## Prerequisites

- [Power BI Desktop](https://powerbi.microsoft.com/desktop/) with a `.pbip` file open
- [Claude Code CLI](https://docs.anthropic.com/claude-code) — `npm install -g @anthropic-ai/claude-code`
- [Node.js v18+](https://nodejs.org)
- Windows (PowerShell 5+)

---

## Quick start

### 1. Clone the repo
```powershell
git clone https://github.com/YOUR_GITHUB_REPO
cd powerbi-mcp-claude
```

### 2. Register the MCP server
```powershell
.\connect_pbi_mcp.ps1
```

This will:
- Locate `powerbi-modeling-mcp.exe` (searches repo folder → VS Code extensions → PATH)
- Register it with Claude Code via `claude mcp add`
- Verify the registration
- List any running Power BI Desktop instances

### 3. Start a Claude Code session
```powershell
claude
```

Then say:
```
Connect to the open Power BI Desktop file through mcp.
```

Claude will connect, list all tables and measures, and be ready to help.

---

## Script options

```powershell
# Normal run (registers if not already registered)
.\connect_pbi_mcp.ps1

# Force re-registration (e.g. after moving the exe)
.\connect_pbi_mcp.ps1 -Force

# Point to a custom exe location
.\connect_pbi_mcp.ps1 -ExePath "C:\path\to\powerbi-modeling-mcp.exe"

# Remove the MCP server from Claude Code
.\connect_pbi_mcp.ps1 -Unregister
```

---

## First-time setup (full environment)

If you are setting up from scratch on a new machine:

```powershell
.\setup_claude_pbi_mcp.ps1 -BigQueryProject "your-gcp-project" -BigQueryDataset "your-dataset"
```

This installs the VS Code extension, configures Claude Desktop, installs Claude Code CLI, and writes a `CLAUDE.md` template.

---

## Model context (CLAUDE.md)

`CLAUDE.md` is automatically read by Claude Code at session start. It contains:

- Full table and measure inventory
- Relationship map with known issues flagged
- DAX constraints (allowed/forbidden functions)
- Time intelligence pattern in use (TI_Table)
- Performance targets and conventions
- Known issues from the last validation run

Update `CLAUDE.md` after each significant session to keep the memory current.

---

## DAX constraints (BigQuery DirectQuery)

| Rule | Detail |
|---|---|
| **Allowed functions** | SUM, COUNT, MIN, MAX, AVERAGE, DIVIDE, IF, SWITCH, COALESCE, CALCULATE, FILTER, ALL, ALLSELECTED, VALUES, CALCULATETABLE |
| **Forbidden** | TOTALYTD, DATEADD, SAMEPERIODLASTYEAR, DATESINPERIOD, PREVIOUSMONTH, PREVIOUSYEAR |
| **Forbidden** | SUMX over FILTER(ALL()) on DirectQuery tables |
| **Forbidden** | Calculated columns on DirectQuery tables |
| **Forbidden** | CTEs in native SQL queries |
| **LY comparisons** | Use TI_Table pattern or explicit `>= / <=` date range filters |
| **Validation** | Always run a DAX query to confirm a new measure executes without error |

---

## MCP connection flow

```
Claude Code
    │
    ▼
powerbi-modeling-mcp.exe  (stdio transport)
    │
    ▼
Power BI Desktop  (localhost XMLA endpoint)
    │
    ▼
Semantic model (DirectQuery → GCP BigQuery)
```

---

## Git workflow

```
feature/[area]-[description]   ← branch naming
```

1. Save `.pbip` file in Power BI Desktop before committing
2. Validate all new measures with a DAX query
3. Commit after each validated batch
4. Update `CLAUDE.md` with any new model discoveries

---

## License

See `powerbi-mcp-ext/extension/LICENSE.txt` for the extension license.
The Power BI Modeling MCP Server is developed by Microsoft — [source repo](https://github.com/microsoft/powerbi-modeling-mcp).
