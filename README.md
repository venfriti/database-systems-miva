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
| 2 | Query Processing and Optimisation | [`portfolio-2-query-optimisation/`](portfolio-2-query-optimisation/) | ✅ Complete |
| 3 | Transactions and Concurrency | [`portfolio-3-transactions-concurrency/`](portfolio-3-transactions-concurrency/) | ✅ Complete |
| 4 | NoSQL and Advanced Data Models | [`portfolio-4-nosql/`](portfolio-4-nosql/) | ✅ Complete |
| 5 | Distributed and Cloud Database Exercise | [`portfolio-5-distributed-cloud/`](portfolio-5-distributed-cloud/) | ✅ Complete |
| — | Final Documentation and Reflection | [`docs/`](docs/) | ⏳ Not started |

See [`CHANGELOG.md`](CHANGELOG.md) for what was added and when.

## Evidence Index

| Evidence | Portfolio 1 | Portfolio 2 | Portfolio 3 | Portfolio 4 | Portfolio 5 |
|---|---|---|---|---|---|
| SQL scripts | [`sql/`](portfolio-1-database-design/sql/) | [`sql/`](portfolio-2-query-optimisation/sql/) | [`sql/`](portfolio-3-transactions-concurrency/sql/), [`scenarios/`](portfolio-3-transactions-concurrency/scenarios/) | — | [`scripts/`](portfolio-5-distributed-cloud/scripts/) |
| Database schema | [`sql/schema.sql`](portfolio-1-database-design/sql/schema.sql) | [`sql/indexes.sql`](portfolio-2-query-optimisation/sql/indexes.sql), [`sql/redesign.sql`](portfolio-2-query-optimisation/sql/redesign.sql) | [`sql/00-setup.sql`](portfolio-3-transactions-concurrency/sql/00-setup.sql) | [`mongodb/setup.js`](portfolio-4-nosql/mongodb/setup.js) | [`partitioning.sql`](portfolio-5-distributed-cloud/scripts/partitioning.sql) |
| ER diagrams / models | [`er-diagram/`](portfolio-1-database-design/er-diagram/) | — | — | [`models/`](portfolio-4-nosql/models/) | [`config/architecture.png`](portfolio-5-distributed-cloud/config/architecture.png) |
| Query execution plans & performance results | — | [`execution-plans/`](portfolio-2-query-optimisation/execution-plans/), [`results/`](portfolio-2-query-optimisation/results/) | — | — | — |
| NoSQL implementations | — | — | — | [`mongodb/`](portfolio-4-nosql/mongodb/), [`redis/`](portfolio-4-nosql/redis/), [`sample-data/`](portfolio-4-nosql/sample-data/) | — |
| Test results | [`test-results/`](portfolio-1-database-design/test-results/) | [`results/`](portfolio-2-query-optimisation/results/) | [`test-results/`](portfolio-3-transactions-concurrency/test-results/) | [`test-results/`](portfolio-4-nosql/test-results/) | [`test-results/`](portfolio-5-distributed-cloud/test-results/) |
| Screenshots | [`screenshots/`](portfolio-1-database-design/screenshots/) | [`screenshots/`](portfolio-2-query-optimisation/screenshots/) | [`screenshots/`](portfolio-3-transactions-concurrency/screenshots/) | [`screenshots/`](portfolio-4-nosql/screenshots/) | [`screenshots/`](portfolio-5-distributed-cloud/screenshots/) |
| Technical documentation | [`README.md`](portfolio-1-database-design/README.md), [`normalisation.md`](portfolio-1-database-design/normalisation.md) | [`README.md`](portfolio-2-query-optimisation/README.md) | [`README.md`](portfolio-3-transactions-concurrency/README.md) | [`README.md`](portfolio-4-nosql/README.md) | [`README.md`](portfolio-5-distributed-cloud/README.md) |

## Technology

| Purpose | Tool |
|---|---|
| Relational DBMS | PostgreSQL 16 |
| ER modelling | dbdiagram.io (DBML), Graphviz |
| Benchmarking | Python 3 (standard library + matplotlib), `EXPLAIN ANALYZE` |
| Concurrency testing | Python 3 + psycopg 3 (two-session scenario runner) |
| Document store | MongoDB 7.0 (pymongo, mongosh) |
| Key-value store | Redis 7 (redis-py) |
| Distribution | PostgreSQL streaming replication, `pg_rewind`, `postgres_fdw`, two-phase commit |

## Quick Start

```bash
createdb stitchline
psql -d stitchline -f portfolio-1-database-design/sql/schema.sql
psql -d stitchline -f portfolio-1-database-design/sql/seed.sql
psql -d stitchline -f portfolio-1-database-design/sql/verify.sql

# Portfolio 2: large data volume, then indexes and redesign
psql -d stitchline -f portfolio-2-query-optimisation/data-generator/generate-data.sql
psql -d stitchline -f portfolio-2-query-optimisation/sql/indexes.sql
psql -d stitchline -f portfolio-2-query-optimisation/sql/redesign.sql

# Portfolio 3: transactional routines, then the demos and scenarios
psql -d stitchline -f portfolio-3-transactions-concurrency/sql/00-setup.sql
python3 portfolio-3-transactions-concurrency/run_scenarios.py

# Portfolio 4: MongoDB (MONGODB_URI) and Redis (REDIS_URL)
mongosh "$MONGODB_URI" --file portfolio-4-nosql/mongodb/setup.js
python3 portfolio-4-nosql/mongodb/migrate.py
python3 portfolio-4-nosql/mongodb/run_queries.py
python3 portfolio-4-nosql/redis/redis_demo.py

# Portfolio 5: local cluster (Linux/macOS/WSL, or a Linux container), then the demos
cd portfolio-5-distributed-cloud/scripts
./cluster.sh up
psql -h /tmp/stitchline-cluster/sock -p 5440 -d stitchline -e -f partitioning.sql
python3 sharding_demo.py && python3 replication_demo.py
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
