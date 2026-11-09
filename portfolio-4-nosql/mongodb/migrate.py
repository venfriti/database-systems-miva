#!/usr/bin/env python3
"""
StitchLine — migrate the relational database into the MongoDB document model
(Portfolio 4)

Reads the PostgreSQL database built in Portfolios 1–3 and writes six
collections: customers, orders, products, materials, stock_ledger, staff.

Usage
  python3 migrate.py                       # all orders (~100,000)
  python3 migrate.py --since 2024          # only orders from 2024 on (smaller,
                                           # fits comfortably in a free Atlas M0)
  python3 migrate.py --mock                # in-memory test run (mongomock)

Connections
  PostgreSQL: standard PG* environment variables, database "stitchline"
  MongoDB   : MONGODB_URI (default mongodb://localhost:27017), database "stitchline"

Run mongodb/setup.js FIRST so collections get their validators and indexes.
Re-running is safe: every collection is emptied before it is loaded.
"""

import argparse
import datetime as dt
import os
import sys
import time
from collections import defaultdict
from decimal import Decimal

import psycopg
from bson.decimal128 import Decimal128

BATCH = 2000
USE_DECIMAL = True    # mongomock cannot compare or add Decimal128, so --mock switches this off


def money(v):
    """NUMERIC -> Decimal128: exact decimal arithmetic in MongoDB, never float."""
    if v is None:
        return None
    v = Decimal(v).quantize(Decimal("0.01"))
    return Decimal128(v) if USE_DECIMAL else float(v)


def num(v):
    if v is None:
        return None
    return Decimal128(Decimal(v)) if USE_DECIMAL else float(v)


def day(d):
    """MongoDB has no DATE type: store dates as midnight UTC datetimes."""
    return None if d is None else dt.datetime(d.year, d.month, d.day)


def ts(t):
    """timestamptz -> naive UTC datetime (MongoDB stores dates in UTC)."""
    return None if t is None else t.astimezone(dt.timezone.utc).replace(tzinfo=None)


def fetch(pg, sql, params=None):
    with pg.cursor() as cur:
        cur.execute(sql, params)
        cols = [c.name for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]


def group(rows, key):
    out = defaultdict(list)
    for r in rows:
        out[r[key]].append(r)
    return out


def get_db(mock: bool):
    global USE_DECIMAL
    if mock:
        USE_DECIMAL = False
        import mongomock
        return mongomock.MongoClient()["stitchline"]
    from pymongo import MongoClient
    return MongoClient(os.environ.get("MONGODB_URI", "mongodb://localhost:27017"))["stitchline"]


def load(coll, docs):
    coll.delete_many({})
    for i in range(0, len(docs), BATCH):
        coll.insert_many(docs[i:i + BATCH], ordered=False)
    print(f"  {coll.name:<14} {coll.count_documents({}):>8,} documents")


def migrate(db, since: int | None):
    pg = psycopg.connect(dbname=os.environ.get("PGDATABASE", "stitchline"))
    pg.execute("SET search_path TO stitchline")
    t0 = time.perf_counter()

    # ------------------------------------------------------------------ staff
    staff = fetch(pg, "SELECT staff_id, full_name, role, email, is_active FROM staff")
    staff_name = {s["staff_id"]: s["full_name"] for s in staff}
    load(db.staff, [{"_id": s["staff_id"], "name": s["full_name"], "role": s["role"],
                     "email": s["email"], "active": s["is_active"]} for s in staff])

    # -------------------------------------------------------------- customers
    # Supertype + two subtype tables + measurements + designs  ->  ONE document.
    custs = fetch(pg, """
        SELECT c.*, s.school_name, s.contact_person, s.contact_phone, s.credit_limit,
               ic.first_name, ic.last_name
        FROM customer c
        LEFT JOIN school s USING (customer_id)
        LEFT JOIN individual_customer ic USING (customer_id)""")
    meas = group(fetch(pg, "SELECT * FROM customer_measurement"), "customer_id")
    designs = group(fetch(pg, "SELECT * FROM embroidery_design WHERE customer_id IS NOT NULL"), "customer_id")

    cust_docs, cust_name = [], {}
    for c in custs:
        doc = {"_id": c["customer_id"], "type": c["customer_type"], "phone": c["phone"],
               "created_at": ts(c["created_at"])}
        if c["email"]:
            doc["email"] = c["email"]
        if c["address"]:
            doc["address"] = c["address"]
        if c["customer_type"] == "school":
            doc["name"] = c["school_name"]
            doc["contact"] = {"person": c["contact_person"], "phone": c["contact_phone"]}
            doc["credit_limit"] = money(c["credit_limit"])
        else:
            doc["name"] = f'{c["first_name"]} {c["last_name"]}'
            doc["first_name"], doc["last_name"] = c["first_name"], c["last_name"]
            m = meas.get(c["customer_id"])
            if m:
                # Relational name/value rows become one measurement profile.
                # New profiles (per garment style) can be added without schema change.
                doc["measurements"] = [{
                    "profile": "general", "unit": "cm",
                    "taken_on": day(max(x["recorded_at"] for x in m)),
                    "values": {x["measure_name"]: num(x["value_cm"]) for x in m},
                }]
        if c["customer_id"] in designs:
            doc["designs"] = [{"design_id": d["design_id"], "name": d["name"],
                               "file_url": d["file_url"], "stitch_count": d["stitch_count"]}
                              for d in designs[c["customer_id"]]]
        cust_docs.append(doc)
        cust_name[c["customer_id"]] = (c["customer_type"], doc["name"], c["phone"])
    load(db.customers, cust_docs)

    # --------------------------------------------------------------- products
    prods = fetch(pg, "SELECT * FROM product ORDER BY product_id")
    variants = group(fetch(pg, "SELECT * FROM product_variant ORDER BY variant_id"), "product_id")
    bom = group(fetch(pg, """SELECT pm.*, m.name AS material, m.unit
                              FROM product_material pm JOIN material m USING (material_id)"""), "variant_id")
    variant_info = {}
    prod_docs = []
    for p in prods:
        vs = []
        for v in variants.get(p["product_id"], []):
            vs.append({"variant_id": v["variant_id"], "size": v["size"], "colour": v["colour"],
                       "list_price": money(v["list_price"]),
                       "materials": [{"material_id": b["material_id"], "name": b["material"],
                                      "qty_per_unit": num(b["qty_per_unit"]), "unit": b["unit"]}
                                     for b in bom.get(v["variant_id"], [])]})
            variant_info[v["variant_id"]] = (p["name"], p["category"], v["size"], v["colour"])
        prod_docs.append({"_id": p["product_id"], "name": p["name"], "category": p["category"],
                          "variants": vs})
    load(db.products, prod_docs)

    # -------------------------------------------------------------- materials
    mats = fetch(pg, """SELECT m.*, s.name AS supplier, s.phone AS supplier_phone
                        FROM material m LEFT JOIN supplier s USING (supplier_id)""")
    load(db.materials, [{"_id": m["material_id"], "name": m["name"], "unit": m["unit"],
                         "stock_qty": num(m["stock_qty"]), "reorder_level": num(m["reorder_level"]),
                         "supplier": ({"supplier_id": m["supplier_id"], "name": m["supplier"],
                                       "phone": m["supplier_phone"]} if m["supplier_id"] else None)}
                        for m in mats])

    # Bucket pattern: one document per material per month (bounded array)
    moves = fetch(pg, """SELECT material_id, order_id, staff_id, change_qty, reason, moved_at,
                                to_char(moved_at, 'YYYY-MM') AS month
                         FROM stock_movement ORDER BY material_id, moved_at""")
    buckets = {}
    for mv in moves:
        key = f'{mv["material_id"]}:{mv["month"]}'
        b = buckets.setdefault(key, {"_id": key, "material_id": mv["material_id"],
                                     "month": mv["month"], "count": 0,
                                     "net_change": Decimal("0"), "movements": []})
        b["count"] += 1
        b["net_change"] += mv["change_qty"]
        entry = {"qty": num(mv["change_qty"]), "reason": mv["reason"],
                 "at": ts(mv["moved_at"]), "staff_id": mv["staff_id"]}
        if mv["order_id"]:
            entry["order_id"] = mv["order_id"]
        b["movements"].append(entry)
    for b in buckets.values():
        b["net_change"] = num(b["net_change"])
    load(db.stock_ledger, list(buckets.values()))

    # ----------------------------------------------------------------- orders
    # sales_order + order_item + order_item_design + order_stage_history +
    # invoice + payment  ->  ONE document per order.
    where = "WHERE o.order_date >= %s" if since else ""
    params = (dt.date(since, 1, 1),) if since else None
    orders = fetch(pg, f"SELECT o.* FROM sales_order o {where} ORDER BY o.order_id", params)
    ids = [o["order_id"] for o in orders]
    sub = "order_id = ANY(%s)"
    items = group(fetch(pg, f"SELECT * FROM order_item WHERE {sub} ORDER BY order_id, line_no", (ids,)), "order_id")
    oid = group(fetch(pg, f"""SELECT d.*, e.name AS design_name FROM order_item_design d
                              JOIN embroidery_design e USING (design_id) WHERE {sub}""", (ids,)), "order_id")
    hist = group(fetch(pg, f"SELECT * FROM order_stage_history WHERE {sub} ORDER BY order_id, changed_at, history_id", (ids,)), "order_id")
    invs = {r["order_id"]: r for r in fetch(pg, f"SELECT * FROM invoice WHERE {sub}", (ids,))}
    pays = group(fetch(pg, """SELECT p.* FROM payment p JOIN invoice i USING (invoice_id)
                              WHERE i.order_id = ANY(%s) ORDER BY paid_at""", (ids,)), "invoice_id")

    docs = []
    for o in orders:
        ctype, cname, cphone = cust_name[o["customer_id"]]
        designs_by_line = group(oid.get(o["order_id"], []), "line_no")
        doc = {
            "_id": o["order_id"],
            "order_number": o["order_number"],
            # Extended reference: a snapshot of what the order screen needs,
            # plus the id to fetch the full customer when required.
            "customer": {"id": o["customer_id"], "type": ctype, "name": cname, "phone": cphone},
            "taken_by": {"id": o["taken_by"], "name": staff_name[o["taken_by"]]},
            "order_date": day(o["order_date"]),
            "due_date": day(o["due_date"]),
            "status": o["status"],
            "items": [],
            "stages": [{"from": h["from_stage"], "to": h["to_stage"],
                        "by": staff_name[h["changed_by"]], "at": ts(h["changed_at"])}
                       for h in hist.get(o["order_id"], [])],
        }
        if o["notes"]:
            doc["notes"] = o["notes"]
        total_units = 0
        for it in items.get(o["order_id"], []):
            pname, cat, size, colour = variant_info[it["variant_id"]]
            line = {"line": it["line_no"],
                    "product": {"variant_id": it["variant_id"], "name": pname, "category": cat,
                                "size": size, "colour": colour},
                    "quantity": it["quantity"], "unit_price": money(it["unit_price"]),
                    "line_total": money(it["quantity"] * it["unit_price"])}
            emb = designs_by_line.get(it["line_no"])
            if emb:
                line["embroidery"] = [{k: v for k, v in {
                    "design_id": e["design_id"], "design": e["design_name"],
                    "placement": e["placement"], "thread_colour": e["thread_colour"],
                    "text": e["custom_text"]}.items() if v is not None} for e in emb]
            doc["items"].append(line)
            total_units += it["quantity"]
        doc["total_units"] = total_units
        inv = invs.get(o["order_id"])
        if inv:
            p = pays.get(inv["invoice_id"], [])
            doc["invoice"] = {
                "number": inv["invoice_number"],
                "issue_date": day(inv["issue_date"]),
                "due_date": day(inv["due_date"]),
                "total": money(inv["total_amount"]),
                "paid": money(inv["amount_paid"]),
                # Computed pattern: stored so "outstanding" can use an index
                "balance": money(inv["total_amount"] - inv["amount_paid"]),
                "payments": [{"amount": money(x["amount"]), "method": x["method"],
                              "reference": x["reference"], "paid_at": ts(x["paid_at"]),
                              "received_by": staff_name[x["received_by"]]} for x in p],
            }
        docs.append(doc)
    load(db.orders, docs)
    pg.close()
    print(f"  done in {time.perf_counter() - t0:.1f} s")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", type=int, help="only migrate orders from this year on")
    ap.add_argument("--mock", action="store_true", help="use in-memory mongomock instead of a server")
    args = ap.parse_args()
    db = get_db(args.mock)
    print(f"Migrating PostgreSQL -> MongoDB ({'mongomock' if args.mock else os.environ.get('MONGODB_URI', 'mongodb://localhost:27017')})")
    migrate(db, args.since)
    return db


if __name__ == "__main__":
    main()
