# Claude Code — Project Memory
# Auto-read at session start. Keep this file updated after every significant session.
# Last updated: 2026-04-02

## Project identity
- Report name   : PEA import
- File format   : Power BI Desktop (.pbip)
- MCP server    : powerbi-modeling-mcp (registered as "powerbi-modeling-mcp" in Claude Code)
- Exe location  : powerbi-mcp-ext/extension/server/powerbi-modeling-mcp.exe
- GitHub repo   : https://github.com/Seebbou7/powerbi-mcp-claude

## How to connect at session start
1. Run: .\connect_pbi_mcp.ps1  (registers MCP + confirms PBI Desktop is running)
2. Open Claude Code: cd "C:\Users\SabihElMehdi\Desktop\Power bi MCP" && claude
3. Say: "Connect to the open Power BI Desktop file through mcp"

## MCP connection details (discovered 2026-04-02)
- Local instance port : 63181 (changes each PBI Desktop restart — always use ListLocalInstances)
- Connection string   : Data Source=localhost:<port>;Application Name=MCP-PBIModeling
- Database ID         : c525ae4a-c5cd-41e7-8e93-2d657ae9e12a
- Compatibility level : 1601
- Model state         : Unprocessed
- Estimated size      : ~203 MB

## Data source
- Storage mode    : DirectQuery on GCP BigQuery
- BigQuery project: YOUR_GCP_PROJECT   ← replace with real value
- BigQuery dataset: YOUR_DATASET       ← replace with real value
- Import tables   : none (all DirectQuery)
- Date table      : Dim_Calendar (connected via TI_Table pattern for LY comparisons)

## Model structure (59 tables total)

### Fact tables (DirectQuery)
- FACT_Promo_PNL            — 26 cols, 3 measures
- FACT_Post_Promo_PNL       — 34 cols
- FACT_Post_Event_Baseline  — 54 cols
- FACT_Sellin_PLP           — 17 cols  ⚠ no Calendar or Customer relationship
- FACT_Redemption_Rate      — 22 cols  ⚠ NO relationships at all — possibly orphaned
- FACT_Promo_PNL GANTT      — 26 cols
- FACT_Post_Promo_PNL GANTT — 34 cols

### Dimension tables
- Dim_Product_Hierarchy    — 31 cols
- Dim_Customer_Hierarchy   — 11 cols
- Dim_Calendar             — 14 cols, 1 hierarchy
- Dim_Promo_Headers        — 18 cols
- Dim_Promo_Lines          — 8 cols
- Dim_Depth_Of_Discount    — 11 cols
- Dim_Chanel_Type          — 2 cols  ⚠ TYPO: should be Dim_Channel_Type

### Measure tables
- KPIs          — 831 measures (main measure hub, ALL KPIs live here)
- FACT_Promo_PNL— 3 measures
- X-Axis, Y-Axis, X-Axis Min, Y-Axis Min — scatter chart helpers (1 measure each)

### Support / parameter tables
- TI_Table                  — time intelligence helper (LY date mapping)
- Filters_Headers_Table     — filter panel
- SwitchTable               — KPI switcher
- SwitchTable Profit Tool   — profit tool switcher
- VAT_Per_Country           — VAT rates by country
- In_Chart_Cluster          — cluster labels
- Permission table          — RLS source (RLS NOT YET IMPLEMENTED)
- FP_* tables               — field parameter tables for dynamic visuals
- PNL Baseline vs Promo*    — PNL waterfall parameter tables
- Promo_Baseline_KPIS, Country_Overview_waterfall_KPIs, etc.

### Auto-generated (hidden, ignore)
- 17 x LocalDateTable_* — auto-created by Power BI for each date column

## Measures (838 total)

### Naming convention: [Category]_[Metric]
- Compliant examples  : Fact_Promo_Total_Promo_Cost, Scorecard_Color_coding_ROI
- ⚠ 158 violations    : measures using spaces/dashes or starting with % (e.g. %Baseline PNL)
- ⚠ 5 scratch measures: New Measure 1-4, Blank measure — DELETE these

### Display folder structure (top-level groups in KPIs table)
- Promo PNL Fact             — base measures Before/During Event + PNL KPIs
- POST Promo PNL Fact        — post-event equivalents
- Gantt Promo PNL Fact       — Gantt chart measures
- POST Gantt Promo PNL Fact  — post-event Gantt
- Event Ranking              — ranking measures
- Filter Menu - Selected Filters — slicer selection text + titles
- KPI Scorecard / POST KPI Scorecard — color coding measures
- Country Overview / POST Country Overview — waterfall KPIs
- KPI Cards / POST KPI Cards — card visual measures
- Category Overview / POST Category Overview
- Performances Overview
- Time Series
- FACT_Redemption_Rate, FACT_Sellin_PLP — ⚠ misleading folder names (measures still in KPIs table)

### Time intelligence pattern (compliant)
Uses TI_Table instead of forbidden functions:
  VAR _myDates = CALCULATETABLE(VALUES(TI_Table[Dates]), TI_Table[Comp] = "LY")
  CALCULATE(SUM(...), FILTER(ALL(...), [event_start_date] IN _myDates))
⚠ Performance risk: IN _myDates may generate large IN(...) clauses in BigQuery SQL

## Relationships (41 total)
- Active      : 40
- Inactive    : 1  →  FACT_Promo_PNL[ean] → Dim_Depth_Of_Discount[ean_event_id]
- Bidirectional: 2 →  Dim_Product_Hierarchy↔VAT_Per_Country, PNL Baseline vs Promo TWWT 2↔Filters_Headers_Table
- All standard relationships use OneDirection Many→One pattern

## Known issues (from validation 2026-04-02)

### CRITICAL
1. SUMX over FILTER(ALL()) on DirectQuery tables — 14 confirmed measures (full extent unknown)
   Pattern: SUMX(FILTER(ALL(FACT_Promo_PNL), ...), CALCULATE(...))
   Fix: replace with CALCULATE(SUM(...), FILTER(...)) using >= / <= date range filters
   Affected: Fact_Promo_Promo Allow on Invoice excl Rollback_Before/During_Event (and _LY variants),
             Fact_Promo_Promo Allow applied Separately_Before/During_Event (and _LY),
             Fact_Promo_Other prom deducted from sales_Before/During_Event (and _LY),
             Fact_Promo_Oca deducted from sales_Before_Event (and _LY),
             Fact_Promo_Sell Out Value_Before_Event (and _LY)

2. Zero RLS roles defined — Permission table exists but no roles implemented
   Fix: create at least one security role using Permission table before publishing

### HIGH
3. 158 measures violate Category_Metric naming convention
4. 5 scratch/temp measures: New Measure 1, New Measure 2, New Measure 3, New Measure 4, Blank measure
5. Only 7% of TMDL scanned — full forbidden function audit pending

### MEDIUM
6. Bidirectional relationships (see above) — change to OneDirection
7. CALCULATE+IN pattern (27 occurrences) — test BigQuery folding behavior
8. Inactive relationship FACT_Promo_PNL→Dim_Depth_Of_Discount — confirm or delete
9. FACT_Redemption_Rate has no relationships — verify if orphaned

### LOW
10. 6 measure names with trailing spaces (cause silent reference failures)
    Filters Menu - Slicer Brand Selection , Filters Menu - Slicer Sub_Brand Selection ,
    %ROI Title - Perf Scorecard , Post End Date , Incremental Unit , Post Incremental TWWT
11. 7 measures have no display folder: Selected_Filters, Titre_Two_metric_analysis,
    Selected_Filter_Text, X-Axis Value, Y-Axis Value, X-Axis Min Value, Y-Axis Min Value
12. Dim_Chanel_Type — typo (should be Dim_Channel_Type)
13. "PNL Baseline vs Promo" table contains Unicode U+200B zero-width space at end of name

## DAX constraints — STRICT (BigQuery DirectQuery)
- Allowed  : SUM, COUNT, MIN, MAX, AVERAGE, DIVIDE, IF, SWITCH, COALESCE, CALCULATE, FILTER, ALL, ALLSELECTED, VALUES, CALCULATETABLE
- FORBIDDEN: TOTALYTD, DATEADD, SAMEPERIODLASTYEAR, DATESINPERIOD, PREVIOUSMONTH, PREVIOUSYEAR
- FORBIDDEN: SUMX over FILTER(ALL()) on DirectQuery tables
- FORBIDDEN: CTEs in native SQL queries
- FORBIDDEN: Calculated columns on DirectQuery tables
- For LY comparisons: use TI_Table pattern (already in use) or explicit >= / <= date range filters
- After writing any measure: validate with DAX query before committing

## Performance targets
- Target visual refresh : under 5 seconds per visual
- Flag any SUMX on DirectQuery tables — these cannot fold to BigQuery SQL
- Prefer CALCULATE(SUM(...), FILTER(...)) over SUMX(FILTER(...), CALCULATE(...))
- Prefer aggregation-aware measures grouped at the highest grain possible

## Model conventions
- All measures live in the KPIs table (do NOT add measures to fact tables)
- Measure naming: [Category]_[Metric] e.g. Sales_TotalRevenue, Scorecard_Color_coding_ROI
- Hide all foreign key columns from report view after creating relationships
- Use display folders to organize measures (avoid FACT_ prefix in folder names)

## Git workflow
- Repo    : https://github.com/Seebbou7/powerbi-mcp-claude
- Branch  : feature/[area]-[description]
- Always save .pbip before committing
- Commit after each validated batch of measures
- Run .\connect_pbi_mcp.ps1 before each session to ensure MCP is registered

## Files in this repo
- CLAUDE.md                   — this file (project memory)
- connect_pbi_mcp.ps1         — one-shot MCP registration + PBI Desktop discovery script
- setup_claude_pbi_mcp.ps1    — full environment setup script (first-time use)
- powerbi-mcp-ext/            — VS Code extension source for Power BI Modeling MCP
- powerbi-modeling-mcp/       — upstream MCP server reference (submodule)
- PowerBI_Figma_Theme.json    — Figma theme for Power BI report styling
