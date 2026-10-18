# Normalisation — StitchLine Uniforms & Embroidery

This document derives the relational schema from the business's existing paper order sheet, step by step from unnormalised form (UNF) to Boyce–Codd Normal Form (BCNF).

---

## 0. Starting point: the paper order sheet (UNF)

StitchLine currently records each order on a single paper sheet. Transcribed into one relation, it looks like this:

```
ORDER_SHEET (
  order_no, order_date, due_date, status, taken_by_name,
  customer_name, customer_phone, customer_address, school_name, contact_person,
  { item_name, item_category, size, colour, qty, unit_price,
    { logo_name, logo_file, placement, thread_colour } },
  { measurement_name, measurement_value },
  invoice_no, invoice_total,
  { payment_date, payment_amount, payment_method, received_by_name }
)
```

`{ }` marks a **repeating group**. Note the nested group: one item line can carry several logos.

### Sample data (two sheets)

| order_no | customer_name | customer_phone | school_name | contact_person | items | payments |
|---|---|---|---|---|---|---|
| SL-0001 | Greenfield Academy | +1…1001 | Greenfield Academy | Mr. Paul Adams | Shirt S ×40 @18 (crest, left chest, gold); Shirt M ×60 @20 (crest, left chest, gold); Trousers M ×50 @25 | 03-Aug 1500 transfer (Mei); 27-Aug 1670 transfer (Mei) |
| SL-0006 | Greenfield Academy | +1…1001 | Greenfield Academy | Mr. Paul Adams | Badge ×80 @5 (crest, pocket, gold) | — |

### Anomalies in this form

| Anomaly | Example |
|---|---|
| **Update** | Greenfield Academy changes its contact person. Every past and current order sheet for that school must be edited, and any sheet that is missed now contradicts the others. |
| **Insertion** | A new school asks for a quote. It cannot be recorded until it places an order, because there is no order number to attach it to. The same applies to a new product or a new logo. |
| **Deletion** | SL-0006 is cancelled and its sheet is destroyed. If it were the school's only order, the school's contact details and its logo file would be lost with it. |
| **Redundancy** | The school name, phone, contact person, logo file and staff names are rewritten on every sheet. |

---

## 1. Functional dependencies

Identified from the business rules:

| # | Functional dependency | Business rule |
|---|---|---|
| FD1 | `order_no → order_date, due_date, status, taken_by, customer_phone` | One order sheet belongs to one customer and is taken by one staff member |
| FD2 | `customer_phone → customer_name, customer_address, customer_type` | A phone number identifies a customer |
| FD3 | `customer_phone → school_name, contact_person` *(schools only)* | |
| FD4 | `(order_no, line_no) → item_name, size, colour, qty, unit_price` | Each line on the sheet is one product variant |
| FD5 | `(item_name, size, colour) → item_category, list_price` | Catalogue data depends on the variant, not the order |
| FD6 | `item_name → item_category` | |
| FD7 | `(customer, logo_name) → logo_file, stitch_count` | A logo belongs to a customer |
| FD8 | `(order_no, line_no, logo_name, placement) → thread_colour, custom_text` | |
| FD9 | `invoice_no → order_no, invoice_total, issue_date` and `order_no → invoice_no` | One invoice per order |
| FD10 | `payment_ref → invoice_no, payment_date, payment_amount, method, received_by` | |
| FD11 | `(customer_phone, measurement_name) → measurement_value` | |
| FD12 | `staff_name → staff_role` *(names are not unique, so a staff_id is introduced)* | |

> **Note on `unit_price`.** FD4 includes `unit_price` on the order line even though FD5 gives a `list_price` for the variant. They are **different facts**: `list_price` is today's catalogue price; `unit_price` is the price agreed *when the order was taken*. If the catalogue price changes, old orders and invoices must not change. Keeping both is therefore correct and not a 3NF violation.

---

## 2. First Normal Form (1NF)

**Rule:** every attribute holds one atomic value; no repeating groups.

**Action:** remove each repeating group into its own relation, carrying the key of its parent.

```
ORDER          (order_no, order_date, due_date, status, taken_by_name,
                customer_phone, customer_name, customer_address, school_name, contact_person,
                invoice_no, invoice_total)

ORDER_LINE     (order_no, line_no, item_name, item_category, size, colour, qty, unit_price)

LINE_LOGO      (order_no, line_no, logo_name, placement, logo_file, stitch_count,
                thread_colour, custom_text)

PAYMENT        (payment_ref, order_no, payment_date, payment_amount, method, received_by_name)

MEASUREMENT    (customer_phone, measurement_name, measurement_value)
```

**Problem remaining:** partial dependencies on composite keys (2NF).

---

## 3. Second Normal Form (2NF)

**Rule:** in 1NF, and every non-key attribute depends on the **whole** primary key.

Only relations with composite keys can violate 2NF.

| Relation | Key | Partial dependency | Fix |
|---|---|---|---|
| ORDER_LINE | (order_no, line_no) | `item_category` depends on `item_name` only — not on which order it is in (FD6) | Move to **PRODUCT** |
| ORDER_LINE | (order_no, line_no) | Variant data (`size`, `colour` combined with `item_name`) describes a catalogue item, not the order | Create **PRODUCT_VARIANT**; the line references `variant_id` |
| LINE_LOGO | (order_no, line_no, logo_name, placement) | `logo_file`, `stitch_count` depend on the logo only (FD7) | Move to **EMBROIDERY_DESIGN** |

After 2NF:

```
ORDER             (order_no, order_date, due_date, status, taken_by_name,
                   customer_phone, customer_name, customer_address, school_name, contact_person,
                   invoice_no, invoice_total)
PRODUCT           (product_id, item_name, item_category)
PRODUCT_VARIANT   (variant_id, product_id, size, colour, list_price)
ORDER_LINE        (order_no, line_no, variant_id, qty, unit_price)
EMBROIDERY_DESIGN (design_id, customer_phone, logo_name, logo_file, stitch_count)
LINE_DESIGN       (order_no, line_no, design_id, placement, thread_colour, custom_text)
PAYMENT           (payment_ref, order_no, payment_date, payment_amount, method, received_by_name)
MEASUREMENT       (customer_phone, measurement_name, measurement_value)
```

**Problem remaining:** ORDER still holds customer, school, staff and invoice facts that depend on something other than `order_no` directly (3NF).

---

## 4. Third Normal Form (3NF)

**Rule:** in 2NF, and no non-key attribute depends on another non-key attribute (no transitive dependencies).

| Relation | Transitive dependency | Fix |
|---|---|---|
| ORDER | `order_no → customer_phone → customer_name, customer_address` (FD1 + FD2) | Move to **CUSTOMER** |
| ORDER | `order_no → customer_phone → school_name, contact_person` (FD3) | Move to **SCHOOL** (subtype of customer) |
| ORDER | `order_no → taken_by → staff_role` (FD12) | Move to **STAFF**; order keeps `taken_by` as an FK |
| ORDER | `order_no → invoice_no → invoice_total, issue_date` (FD9) | Move to **INVOICE** with `order_id UNIQUE` (1:1) |
| PAYMENT | `payment_ref → received_by_name → staff_role` | Reference **STAFF** by `staff_id` |

### Supertype / subtype decision

School-only attributes (`school_name`, `contact_person`) would be NULL for every individual, and individual-only attributes (`first_name`, `last_name`, body measurements) NULL for every school. Rather than one wide table full of NULLs, CUSTOMER is split into a supertype holding shared attributes and two subtypes:

- **CUSTOMER** (`customer_id`, `customer_type`, `phone`, `email`, `address`)
- **SCHOOL** (`customer_id`, `school_name`, `contact_person`, `contact_phone`)
- **INDIVIDUAL_CUSTOMER** (`customer_id`, `first_name`, `last_name`)

Measurements now reference INDIVIDUAL_CUSTOMER, so the schema itself prevents a school from having body measurements.

### Surrogate keys

`customer_phone` was the natural determinant in the FDs, but phone numbers change. A surrogate `customer_id` becomes the primary key, and `phone` stays as a `UNIQUE` candidate key. The same reasoning applies to staff (names are not unique) and orders (`order_number` is kept as a unique business identifier).

---

## 5. Boyce–Codd Normal Form (BCNF)

**Rule:** for every non-trivial FD `X → Y`, `X` is a superkey.

Every relation in the final schema was checked:

| Relation | Determinants | All are superkeys? |
|---|---|---|
| customer | `customer_id`, `phone` | ✅ both are candidate keys |
| school | `customer_id`, `school_name` | ✅ |
| individual_customer | `customer_id` | ✅ |
| customer_measurement | `(customer_id, measure_name)` | ✅ |
| staff | `staff_id`, `email` | ✅ |
| supplier | `supplier_id`, `name` | ✅ |
| product | `product_id`, `name` | ✅ |
| product_variant | `variant_id`, `(product_id, size, colour)` | ✅ |
| material | `material_id`, `name` | ✅ |
| product_material | `(variant_id, material_id)` | ✅ |
| embroidery_design | `design_id`, `(customer_id, name)` | ✅ |
| sales_order | `order_id`, `order_number` | ✅ |
| order_item | `(order_id, line_no)` | ✅ |
| order_item_design | `(order_id, line_no, design_id, placement)` | ✅ |
| order_stage_history | `history_id` | ✅ |
| invoice | `invoice_id`, `invoice_number`, `order_id` | ✅ all three are candidate keys |
| payment | `payment_id` | ✅ |
| stock_movement | `movement_id` | ✅ |

No relation has a determinant that is not a candidate key, so **the schema is in BCNF**.

---

## 6. Deliberate exceptions and their justification

Normalisation removes redundancy, but some apparent redundancy records different facts or is needed for performance. Each case below is intentional.

| Attribute | Looks redundant because… | Kept because… |
|---|---|---|
| `order_item.unit_price` | Price exists on `product_variant` | It records the **price at the time of the order** — a historical fact. Changing the catalogue must not change past orders. |
| `invoice.total_amount` | Derivable as `SUM(quantity × unit_price)` | An issued invoice is a **fixed legal document**. It must not change if order lines are edited afterwards. `verify.sql` shows the two currently agree. |
| `material.stock_qty` | Derivable as `SUM(stock_movement.change_qty)` | Summing the whole ledger on every order is slow, and a single stored row is what gets **locked** when two orders draw on the same material at once (Portfolio 3). `verify.sql` proves the stored value reconciles with the ledger. |
| `sales_order.status` | Derivable as the `to_stage` of the latest `order_stage_history` row | Filtering orders by stage (the app's main screen) would otherwise need a subquery per order. `status` is the current state; the history table is the audit trail. Both are written in the same transaction. |
| Invoice balance | Could be stored as `amount_paid` | **Not stored.** It is computed by the view `v_invoice_balance`, so it can never drift out of sync with payments. Whether to store it for speed is evaluated in Portfolio 2. |

---

## 7. Known limitation carried forward

`customer_measurement` stores body measurements as name/value rows. This is valid BCNF and allows any measurement, but:

- values cannot be type-checked per measurement (e.g. a sleeve length range differs from a waist range);
- different garment styles need different measurement sets, which the schema cannot express;
- retrieving one customer's full profile requires pivoting rows into columns.

This semi-structured data is a natural fit for a document model and is revisited in **Portfolio 4 (NoSQL)**.
