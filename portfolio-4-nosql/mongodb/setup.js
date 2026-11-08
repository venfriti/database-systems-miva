// =====================================================================
// StitchLine — MongoDB collections, validators and indexes (Portfolio 4)
//
//   mongosh "$MONGODB_URI" --file setup.js
//
// Requires MongoDB 7.0 or later (MongoDB Atlas currently runs 8.x).
// Re-running drops and recreates the collections: run migrate.py after it.
// =====================================================================

const s = db.getSiblingDB("stitchline");

for (const c of ["customers", "orders", "products", "materials", "stock_ledger", "staff"]) {
  if (s.getCollectionNames().includes(c)) s.getCollection(c).drop();
}

const OPEN = ["received", "cutting", "sewing", "embroidery", "ready"];
const STAGES = [...OPEN, "delivered", "cancelled"];
const money = { bsonType: "decimal" };

// ---------------------------------------------------------------------
// customers — schools and individuals in ONE collection.
// The relational supertype/subtype becomes a "type" field; oneOf makes
// each type carry its own required fields (disjoint specialisation).
// ---------------------------------------------------------------------
s.createCollection("customers", {
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["_id", "type", "name", "phone"],
    properties: {
      type:  { enum: ["school", "individual"] },
      name:  { bsonType: "string", minLength: 1 },
      phone: { bsonType: "string" },
      designs: { bsonType: "array", items: {
        bsonType: "object", required: ["design_id", "name", "file_url"] } },
      measurements: { bsonType: "array", items: {
        bsonType: "object", required: ["profile", "unit", "values"],
        properties: {
          unit:   { enum: ["cm", "in"] },
          values: { bsonType: "object",
                    additionalProperties: { bsonType: "decimal" } } } } }
    },
    oneOf: [
      { properties: { type: { enum: ["school"] } },
        required: ["contact", "credit_limit"],
        not: { required: ["measurements"] } },          // schools have no body measurements
      { properties: { type: { enum: ["individual"] } },
        required: ["first_name", "last_name"] }
    ]
  } },
  validationAction: "error"
});

// ---------------------------------------------------------------------
// orders — one document per order: lines, embroidery placements, stage
// history, invoice and payments are all embedded.
// ---------------------------------------------------------------------
const specRequired = {                // Ankara styles need different measurements
  agbada:      ["chest", "shoulder", "sleeve", "agbada_length", "trouser_length", "waist"],
  gown:        ["bust", "waist", "hip", "gown_length"],
  iro_buba:    ["bust", "waist", "hip", "buba_length", "iro_length"],
  buba_sokoto: ["chest", "shoulder", "sleeve", "top_length", "waist", "trouser_length"]
};

s.createCollection("orders", {
  validator: { $and: [
    { $jsonSchema: {
      bsonType: "object",
      required: ["_id", "order_number", "customer", "taken_by", "order_date", "due_date", "status", "items", "stages"],
      properties: {
        order_number: { bsonType: "string" },
        customer: { bsonType: "object", required: ["id", "type", "name"] },
        order_date: { bsonType: "date" },
        due_date:   { bsonType: "date" },
        status: { enum: STAGES },
        items: { bsonType: "array", minItems: 1, items: {
          bsonType: "object", required: ["line", "product", "quantity", "unit_price"],
          properties: {
            quantity:   { bsonType: ["int", "long"], minimum: 1 },
            unit_price: money,
            embroidery: { bsonType: "array", items: {
              bsonType: "object", required: ["design_id", "placement", "thread_colour"],
              properties: { placement: { enum: ["left_chest", "right_chest", "back", "left_sleeve",
                                                "right_sleeve", "collar", "pocket", "cap_front"] } } } } } } },
        stages: { bsonType: "array", minItems: 1 },
        invoice: { bsonType: "object", required: ["number", "total", "paid", "balance"],
                   properties: { total: money, paid: money, balance: money } },
        // Ankara custom specification: shape depends on the garment style
        custom_spec: { bsonType: "object", required: ["style", "fabric", "measurements"],
          oneOf: Object.entries(specRequired).map(([style, req]) => ({
            properties: { style: { enum: [style] },
                          measurements: { bsonType: "object", required: req } } })) }
      }
    } },
    // Same rule as Portfolio 2's CHECK: an invoice can never be overpaid,
    // and the stored balance must match.
    { $expr: { $or: [
      { $eq: [{ $type: "$invoice" }, "missing"] },
      { $and: [
        { $lte: ["$invoice.paid", "$invoice.total"] },
        { $eq: ["$invoice.balance", { $subtract: ["$invoice.total", "$invoice.paid"] }] }
      ] }
    ] } },
    { $expr: { $gte: ["$due_date", "$order_date"] } }
  ] },
  validationAction: "error"
});

s.createCollection("products", { validator: { $jsonSchema: {
  bsonType: "object", required: ["_id", "name", "category", "variants"],
  properties: { category: { enum: ["uniform", "sportswear", "badge", "accessory", "ankara_custom"] } } } } });

s.createCollection("materials", { validator: { $jsonSchema: {
  bsonType: "object", required: ["_id", "name", "unit", "stock_qty"],
  properties: { stock_qty: { bsonType: "decimal", minimum: 0 } } } } });

s.createCollection("stock_ledger");   // bucket pattern: one document per material per month
s.createCollection("staff");

// ---------------------------------------------------------------------
// Indexes — each one serves a query in queries.js
// ---------------------------------------------------------------------
s.orders.createIndex({ order_number: 1 }, { unique: true });
s.orders.createIndex({ "customer.id": 1, order_date: -1 });                      // D1 history
s.orders.createIndex({ due_date: 1 },                                             // D4, D6 board
                     { partialFilterExpression: { status: { $in: OPEN } }, name: "open_by_due" });
s.orders.createIndex({ "invoice.due_date": 1 },                                   // D3 outstanding
                     { partialFilterExpression: { "invoice.balance": { $gt: NumberDecimal("0") } },
                       name: "unpaid_by_due" });
s.orders.createIndex({ order_date: 1 });                                          // D5 revenue
s.customers.createIndex({ phone: 1 }, { unique: true });
s.customers.createIndex({ type: 1, name: 1 });
s.customers.createIndex({ "measurements.profile": 1 }, { sparse: true });         // D7
s.stock_ledger.createIndex({ material_id: 1, month: -1 });

print("Collections:", s.getCollectionNames().sort().join(", "));
printjson(s.orders.getIndexes().map(i => i.name));
