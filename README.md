# Advanced Database Systems Portfolio

**Student:** Tolu Sanusi · Miva Open University
**Case study:** StitchLine Uniforms & Embroidery

This repository contains five portfolio activities and the final documentation. All of them are built on a single case study: the order, invoicing and stock database for a uniform and embroidery business.

## Case Study

**StitchLine Uniforms & Embroidery** makes school uniforms, embroidered badges and sportswear in bulk for schools, and custom Ankara garments for individual customers. The database replaces paper order sheets and supports an internal order-management app.

| | |
|---|---|
| **Users** | Owner/admin, front-desk staff, production staff, accounts |
| **Major data** | Customers (schools and individuals), measurements, products and variants, materials and suppliers, embroidery designs, orders and order lines, production stages, invoices, payments, stock movements |
| **Key operations** | Take orders with embroidery placements, deduct material stock, move orders through production, invoice, record part-payments, track outstanding balances, restock |

The full description is in [Portfolio 1](portfolio-1-database-design/README.md#1-case-study-description).

## Portfolio Progress

| # | Activity | Folder | Status |
|---|---|---|---|
| 1 | Database Design and Modelling | [`portfolio-1-database-design/`](portfolio-1-database-design/) | ✅ Complete |
| 2 | Query Processing and Optimisation | [`portfolio-2-query-optimisation/`](portfolio-2-query-optimisation/) | ⏳ Not started |
| 3 | Transactions and Concurrency | [`portfolio-3-transactions-concurrency/`](portfolio-3-transactions-concurrency/) | ⏳ Not started |
| 4 | NoSQL and Advanced Data Models | [`portfolio-4-nosql/`](portfolio-4-nosql/) | ⏳ Not started |
| 5 | Distributed and Cloud Database Exercise | [`portfolio-5-distributed-cloud/`](portfolio-5-distributed-cloud/) | ⏳ Not started |
| — | Final Documentation and Reflection | [`docs/`](docs/) | ⏳ Not started |

See [`CHANGELOG.md`](CHANGELOG.md) for what was added and when.

## Evidence Index

| Evidence | Portfolio 1 |
|---|---|
| SQL scripts | [`sql/`](portfolio-1-database-design/sql/) |
| Database schema | [`sql/schema.sql`](portfolio-1-database-design/sql/schema.sql) |
| ER diagrams / models | [`er-diagram/`](portfolio-1-database-design/er-diagram/) |
| Test results | [`test-results/`](portfolio-1-database-design/test-results/) |
| Screenshots | [`screenshots/`](portfolio-1-database-design/screenshots/) |
| Technical documentation | [`README.md`](portfolio-1-database-design/README.md), [`normalisation.md`](portfolio-1-database-design/normalisation.md) |

*Further columns are added as each portfolio is completed.*

## Technology

| Purpose | Tool |
|---|---|
| Relational DBMS | PostgreSQL 16 |
| ER modelling | dbdiagram.io (DBML), Graphviz |

## Quick Start

```bash
createdb stitchline
psql -d stitchline -f portfolio-1-database-design/sql/schema.sql
psql -d stitchline -f portfolio-1-database-design/sql/seed.sql
psql -d stitchline -f portfolio-1-database-design/sql/verify.sql
```

## Repository Structure

```
advanced-database-portfolio/
├── portfolio-1-database-design/
├── portfolio-2-query-optimisation/
├── portfolio-3-transactions-concurrency/
├── portfolio-4-nosql/
├── portfolio-5-distributed-cloud/
├── docs/                 final documentation
├── CHANGELOG.md
└── README.md
```
