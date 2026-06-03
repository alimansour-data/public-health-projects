# public-health-projects
Analytical public health projects — R, SAS, SQL, Python

# Hospital Operations Management Database

A relational database (MySQL) modeling the operations of a district hospital in a resource-constrained setting, with a reporting layer and stored procedure that automate recurring quality-indicator reporting. Built and iteratively expanded across three design phases, then extended with an R visualization layer.

> All data in this project is synthesized for demonstration.
> No real patient information is used.

## Overview

District hospitals often lack centralized information systems for tracking operations, supplies, and performance. This database models that environment and supports three user roles — a supply and pharmacy manager, an infection control officer, and a regional health department supervisor — through analytical queries and an automated reporting layer used for accreditation.

## Schema

The database contains **9 tables**: `departments`, `staff`, `supplies`, `patients`, `encounters`, and `referrals` (core operations), `billing_claims` and `satisfaction_surveys` (added to support revenue-cycle and patient-experience reporting), and `quality_indicators` (a reporting layer populated by the stored procedure).

Derived fields support performance measures at the source level: `LengthOfStayDays` and `IsReadmission` on `encounters`, and `CatchmentArea` (ZIP mapped to health service areas) on `patients`.

![Entity Relationship Diagram](erd.png)

## What this project demonstrates

- **Relational design:** a normalized multi-table schema with defined primary and foreign keys, entity relationships, and an ERD; iteratively expanded across phases as new reporting needs emerged.
- **Derived clinical and operational measures:** length of stay, 30-day readmission flags (computed via a date-windowed self-join), claim-denial and revenue-loss metrics, and patient-satisfaction gaps.
- **Advanced querying:** aggregation with `CASE`, multi-table joins, a `RANK()` window function for per-department cost ranking, and a multi-stage common table expression (CTE) query that classifies patients into chronic-disease risk tiers.
- **Automation:** a parameterized stored procedure (`ComputeQualityIndicators`) that validates a reporting period, clears prior results to support reruns, and computes four indicators — 30-day readmission rate, first-encounter complication rate, bed-utilization rate, and provider-workload index — writing them to the reporting table for consistent, auditable accreditation reporting.

## Files

| File | Contents |
|------|----------|
| `schema.sql` | Table definitions, foreign keys, and synthesized data (9 tables) |
| `queries.sql` | Role-based analytical queries (supply/pharmacy, infection control, supervisor) |
| `advanced_queries.sql` | Schema extensions, aggregate and window-function queries, and the CTE risk-classification query |
| `stored_procedure.sql` | `ComputeQualityIndicators` procedure, execution call, and results query |
| `erd.png` | Entity relationship diagram |

## Running it

Load `schema.sql` first (creates tables and data), then run the query and procedure files. The query and procedure files reference the working database via `USE`; adjust the database name to match your environment if needed.

## Tools

MySQL, MySQL Workbench. An R layer (tidyverse, ggplot2, patchwork; database connection via DBI/RMariaDB) was used to visualize the computed indicators as an accreditation dashboard and a chronic-disease priority map.
