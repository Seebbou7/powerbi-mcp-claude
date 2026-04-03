# Figma-to-PBIP Pipeline — Claude Code Skill

## Overview
This pipeline converts a Figma dashboard design into a Power BI .pbip report page.
It runs inside Claude Code using the Figma MCP and Power BI MCP servers.

## Usage
Paste this command in Claude Code:
```
/figma-to-pbi https://figma.com/design/<fileKey>/<name>?node-id=<nodeId>
```
Or simply say:
```
Convert this Figma design to a Power BI page: <figma_url>
```

---

## Pipeline Steps

### STEP 1: EXTRACT — Figma Data Retrieval

Parse the Figma URL to extract `fileKey` and `nodeId`.
Call these Figma MCP tools **in parallel**:

1. `get_metadata(fileKey, nodeId)` — structural tree (names, positions, sizes)
2. `get_screenshot(fileKey, nodeId)` — visual reference image
3. `get_design_context(fileKey, nodeId)` — detailed properties
4. `get_variable_defs(fileKey, nodeId)` — design tokens (colors, fonts)

Store all results for subsequent steps.

### STEP 2: PARSE — Flatten the Figma Tree

From the metadata XML, extract the **direct children** of the root frame as visual candidates:

```
For each child of root frame:
  candidate = {
    figmaId, name, type,
    x, y, width, height,
    textContent: (extracted from TEXT children),
    childCount: (number of nested children)
  }
```

**Rules:**
- Groups containing multiple visual-like sub-frames → decompose into individual candidates
- Decorative rectangles with no text children → classify as `shape`
- Text-only elements → classify as `textbox`
- Ignore: masks, clips, auto-layout wrappers, unnamed frames

### STEP 3: CLASSIFY — Map to PBI Visual Types

**Tier 1: Name-based heuristics** — Match element name against `classification_rules.json`:

| Figma name contains | PBI visualType |
|---|---|
| kpi, card, metric, score, stat | card |
| line chart, trend, time series | lineChart |
| bar chart, horizontal bar | clusteredBarChart |
| column chart, vertical bar | columnChart |
| donut, doughnut | donutChart |
| pie | pieChart |
| table, grid, detail, data list | tableEx |
| matrix, pivot, cross tab | matrix |
| slicer, filter, dropdown | slicer |
| button, tab, nav | actionButton |
| header bg, background, divider | shape |
| text, title, label, branding | textbox |
| waterfall | waterfallChart |
| treemap | treemap |
| gauge, dial | gauge |
| map, geo | map |

**Tier 2: Vision-based** — For unclassified elements, analyze the screenshot:
- Single large number with label below → card
- Lines over a time axis → lineChart
- Horizontal bars → clusteredBarChart
- Vertical bars → columnChart
- Data grid with headers → tableEx or matrix
- Circle/ring → donutChart
- Small compact element in header → slicer or actionButton

**Tier 3: User confirmation** — Present the classified list and ask user to confirm or adjust.

### STEP 4: THEME — Extract Design Tokens

From `get_variable_defs` results, map Figma variables to PBI theme:

```
pageBgColor    ← background/primary or darkest fill color
visualBgColor  ← background/secondary or card fill color
accentColor    ← primary brand color (most prominent non-neutral)
textColor      ← primary text color (lightest text)
axisLabelColor ← secondary/muted text color
gridlineColor  ← subtle divider/border color
fontFamily     ← most-used font family
```

If no Figma variables exist, extract from the `get_design_context` CSS output.

Generate or update `PowerBI_Figma_Theme.json` with these tokens.

### STEP 5: LAYOUT — Coordinate Transformation

Scale Figma coordinates to PBI canvas (default 1280x720):

```
scaleX = 1280 / figma_frame_width
scaleY = 720  / figma_frame_height

pbi_x      = round(figma_x * scaleX)
pbi_y      = round(figma_y * scaleY)
pbi_width  = round(figma_width * scaleX)
pbi_height = round(figma_height * scaleY)
```

Assign z-order:
- Background shapes: z = 0
- Navigation/slicers: z = 1
- KPI cards/charts/tables: z = 2

### STEP 6: BIND — Map Figma Labels to PBI Measures

1. Extract text labels from each visual's Figma children
2. Fetch PBI measure catalog: `measure_operations({ operation: "List" })`
3. For each visual label, find the best-matching measure:
   - Exact name match (case-insensitive)
   - Fuzzy match (Levenshtein distance / keyword overlap)
   - Display folder context match
4. Present matches to user for confirmation
5. For unmatched labels, offer to create stub measures

### STEP 7: GENERATE — Create .pbip Files

Build a `design_spec.json` with all extracted data:

```json
{
  "pageName": "<from Figma frame name>",
  "figmaWidth": <original Figma width>,
  "figmaHeight": <original Figma height>,
  "theme": {
    "pageBgColor": "#1E1E1E",
    "visualBgColor": "#2A2A2A",
    "accentColor": "#C5A028",
    "textColor": "#FFFFFF",
    "axisLabelColor": "#888888",
    "gridlineColor": "#3A3A3A",
    "dataLabelColor": "#CCCCCC",
    "titleColor": "#FFFFFF",
    "cardBgColor": "#2D2D2D",
    "fontFamily": "Segoe UI",
    "valueFontSize": "36",
    "labelFontSize": "11",
    "axisFontSize": "9"
  },
  "visuals": [
    {
      "name": "KPI Card 1",
      "visualType": "card",
      "x": 16, "y": 72,
      "width": 280, "height": 120,
      "zLayer": 2,
      "measure": "Fact_Promo_Total_Promo_Cost",
      "measureTable": "KPIs",
      "title": "Total Promo Cost"
    },
    {
      "name": "Revenue Trend",
      "visualType": "lineChart",
      "x": 16, "y": 200,
      "width": 860, "height": 300,
      "zLayer": 2,
      "measure": "Fact_Promo_Incremental_Sales_Value",
      "measureTable": "KPIs",
      "category": "Calendar_date",
      "categoryTable": "Dim_Calendar",
      "title": "Revenue Trend"
    }
  ]
}
```

Run the generator:
```bash
node pipeline/generate_page.js --spec design_spec.json --output ./generated_page
```

### STEP 8: VALIDATE — Verify Measures Exist

For each measure referenced in the generated visuals:

1. Call `measure_operations({ operation: "Get", measureName: "<name>" })` to confirm existence
2. If missing, create a stub:
   ```
   measure_operations({
     operation: "Create",
     createDefinition: {
       name: "<measure_name>",
       expression: "BLANK()",
       tableName: "KPIs",
       displayFolder: "Figma Import"
     }
   })
   ```
3. Validate with DAX query: `EVALUATE { [<measure_name>] }`

---

## Output Structure

```
<output_dir>/
  page.json                    ← Page layout definition
  theme.json                   ← Generated PBI theme (optional)
  visuals/
    <hex_id_1>/visual.json     ← Card visual
    <hex_id_2>/visual.json     ← Line chart visual
    <hex_id_3>/visual.json     ← Bar chart visual
    ...
```

Copy this folder into your `.pbip` report's `definition/pages/` directory.

---

## Template Files

Located in `pipeline/templates/`:
- `page.template.json` — Page skeleton
- `visual_card.json` — KPI card
- `visual_lineChart.json` — Line chart
- `visual_clusteredBarChart.json` — Clustered bar chart
- `visual_columnChart.json` — Column chart
- `visual_tableEx.json` — Table
- `visual_matrix.json` — Matrix/pivot
- `visual_slicer.json` — Slicer/filter
- `visual_shape.json` — Background shape
- `visual_textbox.json` — Text box
- `visual_actionButton.json` — Button/tab
- `visual_donutChart.json` — Donut chart

---

## Classification Rules

Located in `pipeline/classification_rules.json`.
Contains regex patterns mapping Figma element names to PBI visual types.
Edit this file to customize classification for your naming conventions.

---

## Example — Full Run

```
User: Convert this Figma design to a Power BI page:
      https://figma.com/design/abc123/Dashboard?node-id=1-2

Claude:
  1. Extracting from Figma... (4 parallel MCP calls)
  2. Found 14 elements in the design
  3. Classified:
     - "Header BG"        → shape (1440x56)
     - "Year Filter"      → slicer (120x32)
     - "Region Filter"    → slicer (120x32)
     - "Total Revenue"    → card (280x120)
     - "Gross Margin"     → card (280x120)
     - "ROI %"            → card (280x120)
     - "Revenue Trend"    → lineChart (860x300)
     - "Top 10 Products"  → clusteredBarChart (400x300)
     - "Detail Table"     → tableEx (860x280)

  4. Theme extracted: dark mode (#1E1E1E bg, #C5A028 accent)

  5. Measure mapping:
     - "Total Revenue" → KPIs[Fact_Promo_Total_Promo_Cost] ✓
     - "Gross Margin"  → KPIs[Fact_Promo_Incremental_Gross_Margin] ✓
     - "ROI %"         → KPIs[Fact_Promo_%_ROI] ✓

  6. Generating .pbip page files... Done!

  Files created in ./generated_page/
  Copy to your .pbip report's definition/pages/ directory.
```
