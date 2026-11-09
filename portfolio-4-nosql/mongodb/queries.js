// =====================================================================
// StitchLine — MongoDB queries for mongosh (Portfolio 4)
// The same queries as run_queries.py, for running interactively and
// taking screenshots. Paste section by section into mongosh, or:
//   mongosh "$MONGODB_URI" --file queries.js
// =====================================================================

const s = db.getSiblingDB("stitchline");
const REF = ISODate("2026-11-15");
const OPEN = ["received", "cutting", "sewing", "embroidery", "ready"];

// D1 ── Customer history: one collection, no joins ────────────────────
print("\nD1 Customer history");
s.orders.find({ "customer.id": 94 },
              { _id: 0, order_number: 1, order_date: 1, status: 1, "invoice.number": 1, "invoice.total": 1, "invoice.paid": 1 })
        .sort({ order_date: -1 }).limit(5).forEach(printjson);

// explain: index scan vs forced collection scan
const ex1 = s.orders.find({ "customer.id": 94 }).sort({ order_date: -1 }).explain("executionStats");
const ex1n = s.orders.find({ "customer.id": 94 }).sort({ order_date: -1 }).hint({ $natural: 1 }).explain("executionStats");
print("  with index      : docs examined", ex1.executionStats.totalDocsExamined, "| ms", ex1.executionStats.executionTimeMillis);
print("  collection scan : docs examined", ex1n.executionStats.totalDocsExamined, "| ms", ex1n.executionStats.executionTimeMillis);

// D2 ── Full order screen: ONE read instead of a 7-table join ─────────
print("\nD2 Full order view");
printjson(s.orders.findOne({ order_number: "SL-2026-0003" }));

// D3 ── Overdue balances (partial index unpaid_by_due) ────────────────
print("\nD3 Overdue balances");
s.orders.find({ "invoice.balance": { $gt: NumberDecimal("0") }, "invoice.due_date": { $lt: REF } },
              { _id: 0, order_number: 1, "customer.name": 1, "customer.phone": 1, "invoice.balance": 1, "invoice.due_date": 1 })
        .sort({ "invoice.due_date": 1 }).limit(5).forEach(printjson);

// D4 ── Production board (partial index open_by_due) ──────────────────
print("\nD4 Production board");
s.orders.find({ status: { $in: OPEN } }, { _id: 0, order_number: 1, "customer.name": 1, status: 1, due_date: 1 })
        .sort({ due_date: 1 }).limit(5).forEach(printjson);

// D5 ── Monthly revenue by category, 2025 ─────────────────────────────
print("\nD5 Monthly revenue by category, 2025");
s.orders.aggregate([
  { $match: { order_date: { $gte: ISODate("2025-01-01"), $lt: ISODate("2026-01-01") }, status: { $ne: "cancelled" } } },
  { $unwind: "$items" },
  { $group: { _id: { month: { $dateToString: { format: "%Y-%m", date: "$order_date" } }, category: "$items.product.category" },
              orders: { $addToSet: "$_id" }, units: { $sum: "$items.quantity" }, revenue: { $sum: "$items.line_total" } } },
  { $project: { _id: 0, month: "$_id.month", category: "$_id.category", orders: { $size: "$orders" }, units: 1, revenue: 1 } },
  { $sort: { month: 1, category: 1 } }
]).toArray().slice(0, 10).forEach(printjson);

// D6 ── Stuck orders: last stage change older than 7 days ─────────────
print("\nD6 Stuck orders");
s.orders.aggregate([
  { $match: { status: { $in: OPEN } } },
  { $set: { last_move: { $arrayElemAt: ["$stages.at", -1] } } },
  { $match: { last_move: { $lt: new Date(REF.getTime() - 7 * 864e5) } } },
  { $sort: { due_date: 1 } },
  { $project: { _id: 0, order_number: 1, status: 1, due_date: 1, last_move: 1 } }
]).toArray().slice(0, 5).forEach(printjson);

// D7 ── Search inside embedded measurement profiles ───────────────────
print("\nD7 Individuals with a waist of 70–75 cm:",
  s.customers.countDocuments({ measurements: { $elemMatch: { profile: "general",
    "values.waist": { $gte: NumberDecimal("70"), $lte: NumberDecimal("75") } } } }));

// D8 ── Different Ankara specification shapes in one collection ───────
print("\nD8 Flexible Ankara specifications");
s.orders.deleteMany({ order_number: /^SL-P4-/ });
const base = {
  customer: { id: 4, type: "individual", name: "Ngozi Adeyemi" }, taken_by: { id: 2, name: "Daniel Mensah" },
  order_date: REF, due_date: ISODate("2026-12-06"), status: "received",
  items: [{ line: 1, product: { variant_id: 9, name: "Custom Ankara outfit", category: "ankara_custom", size: "CUSTOM", colour: "Multi" },
            quantity: 1, unit_price: NumberDecimal("120.00"), line_total: NumberDecimal("120.00") }],
  stages: [{ from: null, to: "received", by: "Daniel Mensah", at: REF }]
};
s.orders.insertOne({ ...base, _id: 900001, order_number: "SL-P4-AGBADA",
  custom_spec: { style: "agbada", fabric: { type: "wax print", yards: 10, colourway: "indigo/gold" },
    measurements: { chest: NumberDecimal("104"), shoulder: NumberDecimal("48"), sleeve: NumberDecimal("64"),
                    agbada_length: NumberDecimal("150"), trouser_length: NumberDecimal("102"), waist: NumberDecimal("88") },
    options: { cap: true, neck_embroidery: "gold, traditional motif" } } });
s.orders.insertOne({ ...base, _id: 900002, order_number: "SL-P4-GOWN",
  custom_spec: { style: "gown", fabric: { type: "wax print", yards: 6 },
    measurements: { bust: NumberDecimal("92"), waist: NumberDecimal("74"), hip: NumberDecimal("101"), gown_length: NumberDecimal("140") },
    options: { neckline: "sweetheart", sleeve: "puff", slit: "left, 30 cm" } } });
s.orders.find({ order_number: /^SL-P4-/ }, { _id: 0, order_number: 1, custom_spec: 1 }).forEach(printjson);
try {   // gown without hip and gown_length -> must be rejected
  s.orders.insertOne({ ...base, _id: 900003, order_number: "SL-P4-BAD",
    custom_spec: { style: "gown", fabric: { type: "wax print", yards: 6 },
      measurements: { bust: NumberDecimal("92"), waist: NumberDecimal("74") } } });
  print("  invalid spec accepted — validator not active!");
} catch (e) { print("  invalid gown spec REJECTED:", e.errInfo ? JSON.stringify(e.errInfo.details).slice(0, 300) : e.message); }
s.orders.deleteMany({ order_number: /^SL-P4-/ });

// D9 ── Atomic conditional payment ────────────────────────────────────
print("\nD9 Atomic conditional payment on SL-2026-0004");
const pay = (amt, who) => s.orders.updateOne(
  { order_number: "SL-2026-0004", $expr: { $lte: [{ $add: ["$invoice.paid", NumberDecimal(amt)] }, "$invoice.total"] } },
  { $inc: { "invoice.paid": NumberDecimal(amt), "invoice.balance": NumberDecimal("-" + amt) },
    $push: { "invoice.payments": { amount: NumberDecimal(amt), method: "cash", reference: "P4-TEST", paid_at: REF, received_by: who } } }
).modifiedCount;
print("  pay 50 (Daniel):", pay("50.00", "Daniel Mensah"));
print("  pay 50 (Mei)   :", pay("50.00", "Mei Chen"), " <- refused, would exceed the total");
printjson(s.orders.findOne({ order_number: "SL-2026-0004" }, { _id: 0, "invoice.total": 1, "invoice.paid": 1, "invoice.balance": 1 }));
s.orders.updateOne({ order_number: "SL-2026-0004" },
  { $inc: { "invoice.paid": NumberDecimal("-50.00"), "invoice.balance": NumberDecimal("50.00") },
    $pull: { "invoice.payments": { reference: "P4-TEST" } } });          // undo

// D10 ── Optimistic stage move ────────────────────────────────────────
print("\nD10 Optimistic stage move on SL-2026-0005");
const move = (from, to, who) => s.orders.updateOne({ order_number: "SL-2026-0005", status: from },
  { $set: { status: to }, $push: { stages: { from, to, by: who, at: REF } } }).modifiedCount;
print("  Aisha cutting->sewing   :", move("cutting", "sewing", "Aisha Bello"));
print("  Liam  cutting->cancelled:", move("cutting", "cancelled", "Liam Carter"), " <- refused");
s.orders.updateOne({ order_number: "SL-2026-0005" }, { $set: { status: "cutting" }, $pop: { stages: 1 } });   // undo

// D11 ── Bucket pattern ───────────────────────────────────────────────
print("\nD11 Stock ledger buckets, White poplin");
s.stock_ledger.find({ material_id: 1 }, { count: 1, net_change: 1 }).sort({ month: -1 }).limit(3).forEach(printjson);

// D12 ── Document sizes ───────────────────────────────────────────────
print("\nD12 Document sizes");
printjson(s.orders.aggregate([{ $group: { _id: null, orders: { $sum: 1 },
  avg_bytes: { $avg: { $bsonSize: "$$ROOT" } }, max_bytes: { $max: { $bsonSize: "$$ROOT" } } } }]).toArray()[0]);
printjson(s.stats({ scale: 1024 * 1024 }));
