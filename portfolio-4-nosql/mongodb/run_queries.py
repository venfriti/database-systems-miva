#!/usr/bin/env python3
"""
StitchLine — MongoDB queries with evidence (Portfolio 4)

Runs every query D1–D13 against the migrated database, prints the results
and, on a real server, the execution plan (index used, documents examined).
The same queries are in queries.js for mongosh.

Usage
  python3 run_queries.py                  # real server (MONGODB_URI)
  python3 run_queries.py --mock           # migrate into mongomock and run there
                                          # (checks query logic only: mongomock has
                                          #  no validators, explain or transactions)

Output is printed and saved to ../test-results/mongodb-queries[-mock].txt
"""

import argparse
import datetime as dt
import io
import os
import sys
from contextlib import redirect_stdout
from decimal import Decimal
from pathlib import Path

from bson import json_util
from bson.decimal128 import Decimal128

HERE = Path(__file__).resolve().parent
REF = dt.datetime(2026, 11, 15)
OPEN = ["received", "cutting", "sewing", "embroidery", "ready"]
USE_DECIMAL = True


def D(x):
    """Money/measurement literal: Decimal128 on a real server, float under mongomock."""
    return Decimal128(Decimal(x)) if USE_DECIMAL else float(x)


def show(title, docs, limit=8):
    docs = list(docs)
    print(f"\n=== {title}  ({len(docs)} result{'s' if len(docs) != 1 else ''})")
    for d in docs[:limit]:
        print("  " + json_util.dumps(d, json_options=json_util.RELAXED_JSON_OPTIONS))
    if len(docs) > limit:
        print(f"  … {len(docs) - limit} more")


def plan(cursor_or_cmd, label):
    """Summarise explain('executionStats'): winning stage, index, docs examined."""
    ex = cursor_or_cmd
    st = ex.get("executionStats", {})
    wp = ex.get("queryPlanner", {}).get("winningPlan", {})

    def stages(p):
        out = []
        while p:
            out.append(p.get("stage", "?") + (f"({p['indexName']})" if p.get("indexName") else ""))
            p = p.get("inputStage") or (p.get("inputStages") or [None])[0] or p.get("queryPlan")
        return " <- ".join(out)

    print(f"  plan [{label}]: {stages(wp)} | returned {st.get('nReturned')} | "
          f"docs examined {st.get('totalDocsExamined')} | keys examined {st.get('totalKeysExamined')} | "
          f"{st.get('executionTimeMillis')} ms")


def run(db, real: bool):
    o, c = db.orders, db.customers

    # D1 ── Customer history: one collection, no joins ─────────────────
    q1 = {"customer.id": 94}
    proj = {"order_number": 1, "order_date": 1, "status": 1, "invoice.number": 1,
            "invoice.total": 1, "invoice.paid": 1, "_id": 0}
    show("D1 Customer history (Bayside Primary School)", o.find(q1, proj).sort("order_date", -1), 5)
    if real:
        plan(o.find(q1, proj).sort("order_date", -1).explain(), "with index")
        plan(o.find(q1, proj).sort("order_date", -1).hint([("$natural", 1)]).explain(), "forced collection scan")

    # D2 ── The full order screen: ONE document read ───────────────────
    show("D2 Full order view (replaces the 7-table join of Portfolio 1 verify.sql #6)",
         [o.find_one({"order_number": "SL-2026-0003"})], 1)

    # D3 ── Overdue balances ───────────────────────────────────────────
    q3 = {"invoice.balance": {"$gt": D("0")}, "invoice.due_date": {"$lt": REF}}
    p3 = {"order_number": 1, "customer.name": 1, "customer.phone": 1, "invoice.total": 1,
          "invoice.paid": 1, "invoice.balance": 1, "invoice.due_date": 1, "_id": 0}
    show("D3 Overdue balances (top 50 oldest)", o.find(q3, p3).sort("invoice.due_date", 1).limit(50), 5)
    if real:
        plan(o.find(q3, p3).sort("invoice.due_date", 1).limit(50).explain(), "partial index unpaid_by_due")

    # D4 ── Production board ───────────────────────────────────────────
    q4 = {"status": {"$in": OPEN}}
    show("D4 Production board", o.find(q4, {"order_number": 1, "customer.name": 1, "status": 1,
                                            "due_date": 1, "_id": 0}).sort("due_date", 1), 5)
    if real:
        plan(o.find(q4).sort("due_date", 1).explain(), "partial index open_by_due")

    # D5 ── Monthly revenue by category (aggregation pipeline) ─────────
    pipe5 = [
        {"$match": {"order_date": {"$gte": dt.datetime(2025, 1, 1), "$lt": dt.datetime(2026, 1, 1)},
                    "status": {"$ne": "cancelled"}}},
        {"$unwind": "$items"},
        {"$group": {"_id": {"month": {"$dateToString": {"format": "%Y-%m", "date": "$order_date"}},
                            "category": "$items.product.category"},
                    "orders": {"$addToSet": "$_id"},
                    "units": {"$sum": "$items.quantity"},
                    "revenue": {"$sum": "$items.line_total"}}},
        {"$project": {"_id": 0, "month": "$_id.month", "category": "$_id.category",
                      "orders": {"$size": "$orders"}, "units": 1, "revenue": 1}},
        {"$sort": {"month": 1, "category": 1}},
    ]
    show("D5 Monthly revenue by category, 2025 (first rows)", o.aggregate(pipe5), 6)

    # D6 ── Stuck orders: last stage change older than 7 days ──────────
    pipe6 = [
        {"$match": {"status": {"$in": OPEN}}},
        {"$set": {"last_move": {"$arrayElemAt": ["$stages.at", -1]}}},
        {"$match": {"last_move": {"$lt": REF - dt.timedelta(days=7)}}},
        {"$sort": {"due_date": 1}},
        {"$project": {"_id": 0, "order_number": 1, "status": 1, "due_date": 1, "last_move": 1}},
    ]
    show("D6 Stuck orders (no stage change for 7+ days)", o.aggregate(pipe6), 5)

    # D7 ── Measurement search inside embedded profiles ────────────────
    q7 = {"measurements": {"$elemMatch": {"profile": "general",
                                          "values.waist": {"$gte": D("70"), "$lte": D("75")}}}}
    show("D7 Individuals with a waist of 70–75 cm", c.find(q7, {"name": 1, "measurements.values.waist": 1, "_id": 0}), 5)

    # D8 ── Flexible Ankara specifications (schema-flexible documents) ─
    base = {"customer": {"id": 4, "type": "individual", "name": "Ngozi Adeyemi"},
            "taken_by": {"id": 2, "name": "Daniel Mensah"},
            "order_date": REF, "due_date": REF + dt.timedelta(days=21), "status": "received",
            "items": [{"line": 1, "product": {"variant_id": 9, "name": "Custom Ankara outfit",
                                              "category": "ankara_custom", "size": "CUSTOM", "colour": "Multi"},
                       "quantity": 1, "unit_price": D("120.00"), "line_total": D("120.00")}],
            "stages": [{"from": None, "to": "received", "by": "Daniel Mensah", "at": REF}]}
    o.delete_many({"order_number": {"$regex": "^SL-P4-"}})
    agbada = {**base, "_id": 900001, "order_number": "SL-P4-AGBADA",
              "custom_spec": {"style": "agbada", "fabric": {"type": "wax print", "yards": 10, "colourway": "indigo/gold"},
                              "measurements": {"chest": D("104"), "shoulder": D("48"), "sleeve": D("64"),
                                               "agbada_length": D("150"), "trouser_length": D("102"), "waist": D("88")},
                              "options": {"cap": True, "neck_embroidery": "gold, traditional motif"}}}
    gown = {**base, "_id": 900002, "order_number": "SL-P4-GOWN",
            "custom_spec": {"style": "gown", "fabric": {"type": "wax print", "yards": 6},
                            "measurements": {"bust": D("92"), "waist": D("74"), "hip": D("101"), "gown_length": D("140")},
                            "options": {"neckline": "sweetheart", "sleeve": "puff", "slit": "left, 30 cm"}}}
    bad = {**base, "_id": 900003, "order_number": "SL-P4-BAD",
           "custom_spec": {"style": "gown", "fabric": {"type": "wax print", "yards": 6},
                           "measurements": {"bust": D("92"), "waist": D("74")}}}          # hip & length missing
    o.insert_many([agbada, gown])
    show("D8 Two Ankara orders with DIFFERENT specification shapes, same collection",
         o.find({"order_number": {"$in": ["SL-P4-AGBADA", "SL-P4-GOWN"]}},
                {"order_number": 1, "custom_spec.style": 1, "custom_spec.measurements": 1, "custom_spec.options": 1, "_id": 0}))
    try:
        o.insert_one(bad)
        print("  invalid gown spec ACCEPTED" + ("  (expected under --mock: mongomock does not enforce validators)" if not real else "  ⚠ validator not active"))
    except Exception as e:
        print(f"  invalid gown spec REJECTED by validator: {type(e).__name__}: {str(e)[:160]}")
    o.delete_many({"order_number": {"$regex": "^SL-P4-"}})

    # D9 ── Atomic conditional payment (single-document atomicity) ─────
    oid = o.find_one({"order_number": "SL-2026-0004"}, {"_id": 1})["_id"]

    def pay(amount, who):
        amt = D(amount)
        r = o.update_one(
            {"_id": oid, "$expr": {"$lte": [{"$add": ["$invoice.paid", amt]}, "$invoice.total"]}},
            {"$inc": {"invoice.paid": amt, "invoice.balance": D("-" + amount)},
             "$push": {"invoice.payments": {"amount": amt, "method": "cash", "reference": "P4-TEST",
                                            "paid_at": REF, "received_by": who}}})
        return r.modified_count

    before = o.find_one({"_id": oid}, {"invoice.total": 1, "invoice.paid": 1, "invoice.balance": 1, "_id": 0})
    print(f"\n=== D9 Atomic conditional payment on SL-2026-0004\n  before: {json_util.dumps(before)}")
    print(f"  pay 50 (Daniel): modified={pay('50.00', 'Daniel Mensah')}")
    print(f"  pay 50 (Mei)   : modified={pay('50.00', 'Mei Chen')}   ← refused: would exceed the total")
    after = o.find_one({"_id": oid}, {"invoice.total": 1, "invoice.paid": 1, "invoice.balance": 1, "_id": 0})
    print(f"  after : {json_util.dumps(after)}")
    o.update_one({"_id": oid}, {"$inc": {"invoice.paid": D("-50.00"), "invoice.balance": D("50.00")},
                                "$pull": {"invoice.payments": {"reference": "P4-TEST"}}})   # undo

    # D10 ── Optimistic stage move ─────────────────────────────────────
    sid = o.find_one({"order_number": "SL-2026-0005"}, {"_id": 1})["_id"]

    def move(expected, new, who):
        return o.update_one({"_id": sid, "status": expected},
                            {"$set": {"status": new},
                             "$push": {"stages": {"from": expected, "to": new, "by": who, "at": REF}}}).modified_count

    print("\n=== D10 Optimistic stage move on SL-2026-0005 (status 'cutting')")
    print(f"  Aisha: cutting → sewing    modified={move('cutting', 'sewing', 'Aisha Bello')}")
    print(f"  Liam : cutting → cancelled modified={move('cutting', 'cancelled', 'Liam Carter')}   ← refused: no longer at 'cutting'")
    print(f"  status now: {o.find_one({'_id': sid})['status']}")
    o.update_one({"_id": sid}, {"$set": {"status": "cutting"}, "$pop": {"stages": 1}})      # undo

    # D11 ── Bucket pattern: recent stock ledger for one material ───────
    show("D11 Stock ledger buckets, White poplin (latest 3 months)",
         db.stock_ledger.find({"material_id": 1}, {"_id": 1, "count": 1, "net_change": 1})
           .sort("month", -1).limit(3))

    # D12 ── Document size (real server only: $bsonSize) ──────────────
    if real:
        show("D12 Document sizes", o.aggregate([{"$group": {"_id": None,
             "orders": {"$sum": 1}, "avg_bytes": {"$avg": {"$bsonSize": "$$ROOT"}},
             "max_bytes": {"$max": {"$bsonSize": "$$ROOT"}}}}]))

    # D13 ── Multi-document transaction (needs a replica set, e.g. Atlas)
    if real:
        print("\n=== D13 Multi-document ACID transaction: new order + stock deduction")
        client = db.client
        try:
            with client.start_session() as sess:
                def txn(session):
                    db.materials.update_one({"_id": 1, "stock_qty": {"$gte": D("14")}},
                                            {"$inc": {"stock_qty": D("-14")}}, session=session)
                    db.orders.insert_one({**base, "_id": 900010, "order_number": "SL-P4-TXN",
                                          "items": [{**base["items"][0], "product": {"variant_id": 2, "name": "School shirt",
                                                     "category": "uniform", "size": "M", "colour": "White"},
                                                     "quantity": 10, "unit_price": D("20.00"), "line_total": D("200.00")}]},
                                         session=session)
                    raise RuntimeError("simulated failure after both writes")      # forces abort
                try:
                    sess.with_transaction(txn)
                except RuntimeError as e:
                    print(f"  transaction aborted: {e}")
            print(f"  order saved? {db.orders.count_documents({'order_number': 'SL-P4-TXN'}) == 1}  "
                  f"| poplin stock unchanged? {db.materials.find_one({'_id': 1})['stock_qty']}")
        except Exception as e:
            print(f"  transactions unavailable on this server ({type(e).__name__}): {str(e)[:120]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mock", action="store_true")
    ap.add_argument("--since", type=int, default=2025, help="(mock only) years to migrate")
    args = ap.parse_args()

    global USE_DECIMAL
    if args.mock:
        sys.path.insert(0, str(HERE))
        import migrate
        import mongomock
        USE_DECIMAL = migrate.USE_DECIMAL = False
        db = mongomock.MongoClient()["stitchline"]
        with redirect_stdout(io.StringIO()):
            migrate.migrate(db, args.since)
    else:
        from pymongo import MongoClient
        db = MongoClient(os.environ.get("MONGODB_URI", "mongodb://localhost:27017"))["stitchline"]

    buf = io.StringIO()
    with redirect_stdout(buf):
        print(f"StitchLine MongoDB queries — {'mongomock (logic check only)' if args.mock else 'MongoDB server'}"
              f" — run {dt.datetime.now():%Y-%m-%d %H:%M}")
        run(db, real=not args.mock)
    out = buf.getvalue()
    print(out)
    dest = HERE.parent / "test-results" / f"mongodb-queries{'-mock' if args.mock else ''}.txt"
    dest.parent.mkdir(exist_ok=True)
    dest.write_text(out)


if __name__ == "__main__":
    main()
