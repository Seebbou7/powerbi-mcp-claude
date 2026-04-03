# Model context - Claude instructions
# Place this file in the root of your .pbip project folder.
# Claude Code reads it automatically at session start.

## Data source
- Storage mode: DirectQuery on GCP BigQuery
- BigQuery project: YOUR_GCP_PROJECT
- BigQuery dataset: YOUR_DATASET
- No import mode tables except the Date table
- Date table: Date (Dual storage mode)

## DAX constraints - STRICT (BigQuery DirectQuery)
- Allowed functions: SUM, COUNT, MIN, MAX, AVERAGE, DIVIDE, IF, SWITCH, COALESCE
- NEVER use: TOTALYTD, DATEADD, SAMEPERIODLASTYEAR, DATESINPERIOD, PREVIOUSMONTH, PREVIOUSYEAR
- For time intelligence: use CALCULATE with explicit FILTER and >= / <= operators on date columns
- NEVER use CTEs in native SQL queries
- NEVER use calculated columns on DirectQuery tables (they run in memory, not BigQuery)
- After writing any measure, run it via DAX query to confirm it executes without error

## Model conventions
- Fact tables: DirectQuery mode
- Dimension tables: Dual mode
- All measures live in dedicated measure tables, not fact tables
- Measure naming pattern: [Category]_[Metric] e.g. Sales_TotalRevenue, Sales_GrossMargin
- Hide all foreign key columns from report view after creating relationships

## Performance targets
- Target visual refresh: under 5 seconds per visual
- Flag any measure that triggers a Storage Engine hit instead of a DirectQuery
- Prefer aggregation-aware measures grouped at the highest grain possible

## Git workflow
- Always save in .pbip format before committing
- Branch naming: feature/[area]-[description]
- Commit after each validated batch of measures

## Session opener prompt (paste into Claude Desktop each session)
Connect to the open Power BI Desktop file. The model uses DirectQuery
on GCP BigQuery (project: YOUR_GCP_PROJECT, dataset: YOUR_DATASET).
All DAX measures must fold to standard BigQuery SQL.
No time intelligence functions - use explicit date filters instead.
Confirm connection and list all tables and existing measures.
