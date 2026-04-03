#!/usr/bin/env node
/**
 * generate_page.js — Figma-to-PBIP Page Generator
 *
 * Reads a design specification JSON (produced by Claude Code from Figma extraction)
 * and generates a complete .pbip page folder with page.json + visuals/id/visual.json.
 *
 * Usage:
 *   node pipeline/generate_page.js --spec design_spec.json --output ./output_page
 *   node pipeline/generate_page.js --spec design_spec.json --output ./output_page --theme pipeline/theme.json
 *
 * The design_spec.json is created by Claude Code during the Figma extraction step.
 * See pipeline/figma_to_pbip.md for the full pipeline documentation.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// ── CLI Args ─────────────────────────────────────────────────────────────────
const args = process.argv.slice(2);
function getArg(name) {
  const idx = args.indexOf(`--${name}`);
  return idx >= 0 && args[idx + 1] ? args[idx + 1] : null;
}

const specPath   = getArg('spec');
const outputDir  = getArg('output');
const themePath  = getArg('theme');

if (!specPath || !outputDir) {
  console.error('Usage: node generate_page.js --spec <spec.json> --output <dir> [--theme <theme.json>]');
  process.exit(1);
}

// ── Load inputs ──────────────────────────────────────────────────────────────
const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
const templateDir = path.join(__dirname, 'templates');

// ── Defaults ─────────────────────────────────────────────────────────────────
const PBI_WIDTH  = spec.canvasWidth  || 1280;
const PBI_HEIGHT = spec.canvasHeight || 720;

const defaults = {
  TEXT_COLOR:       spec.theme?.textColor       || '#FFFFFF',
  ACCENT_COLOR:     spec.theme?.accentColor     || '#C5A028',
  VISUAL_BG_COLOR:  spec.theme?.visualBgColor   || '#2A2A2A',
  PAGE_BG_COLOR:    spec.theme?.pageBgColor     || '#1E1E1E',
  CARD_BG_COLOR:    spec.theme?.cardBgColor     || '#2D2D2D',
  AXIS_LABEL_COLOR: spec.theme?.axisLabelColor  || '#888888',
  GRIDLINE_COLOR:   spec.theme?.gridlineColor   || '#3A3A3A',
  DATA_LABEL_COLOR: spec.theme?.dataLabelColor  || '#CCCCCC',
  TITLE_COLOR:      spec.theme?.titleColor      || '#FFFFFF',
  FONT_FAMILY:      spec.theme?.fontFamily      || 'Segoe UI',
  VALUE_FONT_SIZE:  spec.theme?.valueFontSize   || '36',
  LABEL_FONT_SIZE:  spec.theme?.labelFontSize   || '11',
  AXIS_FONT_SIZE:   spec.theme?.axisFontSize    || '9',
  DISPLAY_UNITS:    '0',
  MEASURE_TABLE:    'KPIs',
  MEASURE_NAME:     'BLANK()',
  CATEGORY_TABLE:   'Dim_Calendar',
  CATEGORY_COLUMN:  'Calendar_date',
  TITLE_TEXT:       '',
};

// ── Helpers ──────────────────────────────────────────────────────────────────
function hexId(len = 20) {
  return crypto.randomBytes(Math.ceil(len / 2)).toString('hex').slice(0, len);
}

function loadTemplate(visualType) {
  const tplPath = path.join(templateDir, `visual_${visualType}.json`);
  if (fs.existsSync(tplPath)) {
    return fs.readFileSync(tplPath, 'utf8');
  }
  // Fallback: try generic chart types
  const fallbacks = {
    barChart: 'clusteredBarChart',
    hundredPercentStackedBarChart: 'clusteredBarChart',
    hundredPercentStackedColumnChart: 'columnChart',
    areaChart: 'lineChart',
    waterfallChart: 'columnChart',
    pieChart: 'donutChart',
    funnel: 'clusteredBarChart',
    scatterChart: 'lineChart',
    gauge: 'card',
    kpi: 'card',
    image: 'shape',
  };
  const fallback = fallbacks[visualType];
  if (fallback) {
    const fbPath = path.join(templateDir, `visual_${fallback}.json`);
    if (fs.existsSync(fbPath)) {
      let tpl = fs.readFileSync(fbPath, 'utf8');
      // Replace the visualType in the template
      tpl = tpl.replace(`"visualType": "${fallback}"`, `"visualType": "${visualType}"`);
      return tpl;
    }
  }
  console.warn(`  [WARN] No template for visualType "${visualType}", using shape fallback`);
  return fs.readFileSync(path.join(templateDir, 'visual_shape.json'), 'utf8');
}

function fillTemplate(template, vars) {
  let result = template;
  for (const [key, value] of Object.entries(vars)) {
    const placeholder = `{{${key}}}`;
    result = result.split(placeholder).join(String(value));
  }
  // Replace any remaining unfilled placeholders with empty string
  result = result.replace(/\{\{[A-Z_]+\}\}/g, '');
  return result;
}

function scaleCoord(figmaVal, figmaMax, pbiMax) {
  return Math.round((figmaVal / figmaMax) * pbiMax);
}

// ── Compute scale factors ────────────────────────────────────────────────────
const figmaW = spec.figmaWidth  || PBI_WIDTH;
const figmaH = spec.figmaHeight || PBI_HEIGHT;
const scaleX = PBI_WIDTH  / figmaW;
const scaleY = PBI_HEIGHT / figmaH;

// ── Generate page ID ─────────────────────────────────────────────────────────
const pageId = spec.pageId || `ReportSection${hexId(20)}`;
const pageDisplayName = spec.pageName || 'New Page';

// ── Create output directories ────────────────────────────────────────────────
const visualsDir = path.join(outputDir, 'visuals');
fs.mkdirSync(visualsDir, { recursive: true });

// ── Generate page.json ───────────────────────────────────────────────────────
const pageJson = {
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/1.0.0/schema.json",
  "name": pageId,
  "displayName": pageDisplayName,
  "displayOption": "FitToPage",
  "height": PBI_HEIGHT,
  "width": PBI_WIDTH,
  "background": {
    "color": { "value": defaults.PAGE_BG_COLOR },
    "transparency": 0
  },
  "wallpaper": {
    "color": { "value": defaults.PAGE_BG_COLOR },
    "transparency": 0
  },
  "ordinal": spec.ordinal || 0,
  "visualContainers": []
};

// ── Generate visuals ─────────────────────────────────────────────────────────
const visuals = spec.visuals || [];
let tabOrder = 0;

console.log(`\nGenerating page: "${pageDisplayName}" (${visuals.length} visuals)`);
console.log(`  Figma canvas: ${figmaW}x${figmaH} -> PBI canvas: ${PBI_WIDTH}x${PBI_HEIGHT}`);
console.log(`  Scale: x=${scaleX.toFixed(3)}, y=${scaleY.toFixed(3)}\n`);

for (const v of visuals) {
  const visualId = v.id || hexId(20);
  const visualType = v.visualType || 'shape';

  // Scale coordinates
  const x = Math.round((v.x || 0) * scaleX);
  const y = Math.round((v.y || 0) * scaleY);
  const w = Math.max(10, Math.round((v.width || 100) * scaleX));
  const h = Math.max(10, Math.round((v.height || 100) * scaleY));
  const z = v.z || (v.zLayer != null ? v.zLayer * 1000 : 2000);

  // Merge defaults with visual-specific overrides
  const vars = {
    ...defaults,
    VISUAL_ID: visualId,
    X: x,
    Y: y,
    Z: z,
    WIDTH: w,
    HEIGHT: h,
    TAB_ORDER: tabOrder,
    ...(v.overrides || {}),
  };

  // Fill data bindings if provided
  if (v.measure)        vars.MEASURE_NAME    = v.measure;
  if (v.measureTable)   vars.MEASURE_TABLE   = v.measureTable;
  if (v.category)       vars.CATEGORY_COLUMN = v.category;
  if (v.categoryTable)  vars.CATEGORY_TABLE  = v.categoryTable;
  if (v.title)          vars.TITLE_TEXT      = v.title;

  // Load and fill template
  const template = loadTemplate(visualType);
  const visualJson = fillTemplate(template, vars);

  // Write visual folder
  const visualDir = path.join(visualsDir, visualId);
  fs.mkdirSync(visualDir, { recursive: true });
  fs.writeFileSync(path.join(visualDir, 'visual.json'), visualJson, 'utf8');

  // Add to page's visualContainers
  pageJson.visualContainers.push({
    id: visualId,
    x: x, y: y, z: z,
    width: w, height: h,
    config: { singleVisual: { visualType: visualType } }
  });

  const bindingInfo = v.measure ? ` -> ${vars.MEASURE_TABLE}[${vars.MEASURE_NAME}]` : '';
  console.log(`  [${visualType.padEnd(22)}] ${(v.name || visualId).padEnd(30)} ${w}x${h} at (${x},${y})${bindingInfo}`);

  tabOrder += 10;
}

// ── Write page.json ──────────────────────────────────────────────────────────
fs.writeFileSync(path.join(outputDir, 'page.json'), JSON.stringify(pageJson, null, 2), 'utf8');

// ── Write theme if provided ──────────────────────────────────────────────────
if (spec.theme && !themePath) {
  const themeOut = path.join(outputDir, 'theme.json');
  const themeJson = {
    name: spec.pageName || 'Generated Theme',
    dataColors: [
      defaults.ACCENT_COLOR,
      defaults.TEXT_COLOR,
      '#6B6B6B',
      '#E8D080',
      '#A08020',
      '#4A4A4A',
      '#D4C060',
      '#808080'
    ],
    background: defaults.PAGE_BG_COLOR,
    foreground: defaults.TEXT_COLOR,
    tableAccent: defaults.ACCENT_COLOR,
    textClasses: {
      callout: { fontSize: parseInt(defaults.VALUE_FONT_SIZE) || 36, fontFace: defaults.FONT_FAMILY, color: defaults.TEXT_COLOR },
      title:   { fontSize: 13, fontFace: defaults.FONT_FAMILY, color: defaults.ACCENT_COLOR },
      header:  { fontSize: 12, fontFace: defaults.FONT_FAMILY, color: defaults.TEXT_COLOR },
      label:   { fontSize: 10, fontFace: defaults.FONT_FAMILY, color: defaults.AXIS_LABEL_COLOR }
    }
  };
  fs.writeFileSync(themeOut, JSON.stringify(themeJson, null, 2), 'utf8');
  console.log(`\n  Theme written to: ${themeOut}`);
}

// ── Summary ──────────────────────────────────────────────────────────────────
console.log(`\n  Page written to: ${path.resolve(outputDir)}/page.json`);
console.log(`  Visuals: ${visuals.length} files in ${path.resolve(visualsDir)}/`);
console.log(`\n  Done.\n`);
