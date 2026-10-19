# Nivora API Reference

Source of truth: `backend/routes/api.php`, controllers, Form Requests and JSON resources. Routes below are relative to `/api`; production's configured base URL is `https://smartsociety.codevizor.com/api`. Protected requests use `Authorization: Bearer <token>` and `Accept: application/json`. Send JSON bodies with `Content-Type: application/json`, except penalty evidence uploads, which use multipart form data.

The API does not use one uniform response schema. Laravel resources generally return an item under `data`; paginated resource collections use Laravel pagination (`data`, `links`, `meta`). Inline controller responses may include `message`, `data`, and endpoint-specific fields. Validation commonly returns HTTP 422 with `message` and `errors`. Exact response properties are described only where verified in the controller/resource.

## Public diagnostics and authentication

| Method | Path | Access | Input / behavior |
| --- | --- | --- | --- |
| GET | `/health` | Public | Returns `status`, `message`, `service`, `timestamp`, and configured DB name or `disconnected`. The handler returns `status: ok` even when DB lookup throws; interpret the `database` field separately. |
| GET | `/ping` | Public | Connectivity diagnostics including server/client address and host header. Avoid exposing this diagnostic casually in production. |
| GET | `/debug-info` | Public | Reflects request/server address and header information. Restrict/remove from publicly exposed production routing if not needed. |
| POST | `/auth/login` | Public | Body: `login` (email or phone) or compatibility `email`, `password`, optional `requested_role` (`ADMIN`, `RESIDENT`, `STAFF`, `SECURITY`), optional `device_name`. Successful response: `{message, data: {token, token_type: "Bearer", user}}`. Invalid credentials return 422; role mismatch/inactive operational user returns 403. |
| POST | `/auth/register` | Public | See registration fields below. Admin registration is not allowed. Success is HTTP 201 with `message` and user resource data. |
| POST | `/auth/forgot-password` | Public | Requires valid `email`; sends reset link using Laravel's mail configuration. Success returns 202; mail/reset broker failure returns 503. |
| POST | `/auth/reset-password` | Public | Requires `token`, `email`, `password`, and `password_confirmation`; password must be >=8 chars, mixed case and include numbers. Invalid/expired token returns 422. Successful reset invalidates all user tokens. |
| POST | `/auth/logout` | Sanctum | Deletes the authenticated user's tokens and returns a message. |
| GET | `/auth/me` | Sanctum | Returns current user resource with profile, resident/flat, and staff details where present. |
| PATCH | `/auth/profile` | Sanctum | Updates validated user/profile attributes. See `UpdateAccountProfileRequest`. |

Registration body fields in `RegisterRequest`:

| Field | Rules / use |
| --- | --- |
| `role` | Required: `RESIDENT`, `STAFF`, or `SECURITY`. |
| `name`, `email`, `phone`, `password`, `password_confirmation` | Required; email/phone must be unique; phone uses Indian mobile format; password confirmation and strength required. |
| `flat_number`, `building` | Required for residents; used to find/create the flat. |
| `relation_to_owner` | Optional `OWNER`, `TENANT`, or `FAMILY_MEMBER`. |
| `designation` | Required for `STAFF`. |
| `employee_id`, `joining_date`, `shift` | Security requires employee ID, date and shift. Staff/security accounts begin inactive. |
| `date_of_birth`, `gender`, `emergency_contact` | Optional profile/contact fields validated by the request. |

## Dashboards, profiles, residents, flats and staff

| Method | Path | Access | Notes |
| --- | --- | --- | --- |
| GET | `/resident/dashboard` | Resident | Dashboard scoped to the current resident/unit. |
| GET | `/security/dashboard` | Security | Gate dashboard summary. |
| GET | `/staff/dashboard` | Staff | Staff profile/dashboard summary. |
| GET | `/admin/dashboard` | Admin | Administrative summary. |
| GET | `/admin/reports` | Admin | Reports; query `range` is supported by the report controller. |
| GET | `/resident/profile` | Authenticated | Current resident profile. |
| PATCH | `/resident/profile` | Authenticated | Updates resident profile (see controller validation). |
| GET/POST | `/admin/residents` | Admin | List/create residents. `GET` paginates; `POST` requires name, unique email, password (min 8) and accepts phone, flat, relation, primary-contact flag. |
| GET/PUT/PATCH/DELETE | `/admin/residents/{resident}` | Admin | Resource detail/update/delete; update validation is in `UpdateResidentRequest`. |
| GET/POST | `/admin/flats` | Admin | List/create flat. Create requires building, flat number and occupancy status; building + flat number is unique. |
| GET/PUT/PATCH/DELETE | `/admin/flats/{flat}` | Admin | Flat resource operations. |
| GET | `/admin/options` | Admin | Selection data for admin forms. |
| GET | `/staff/options` | Staff | Selection data for staff forms. |
| GET | `/security/visitors/options` | Security | Security selection data, also used by the parcel form. |
| GET/POST | `/admin/staff-members` | Admin | Paginated staff list/create. Create validates name, mobile, designation, joining date; optional linked user, employee ID, shift and status. |
| GET/PUT/PATCH | `/admin/staff-members/{staffMember}` | Admin | Detail/update. Delete is not registered on the staff resource. |
| PATCH | `/admin/staff-members/{staffMember}/status` | Admin | Body `status`: `ACTIVE`, `INACTIVE`, or `ON_LEAVE`. Activation controls staff/security login. |

The admin resident and flat resources use Laravel `apiResource`; consult the matching Form Request/controller for exact update behavior. The mobile client uses shared module forms rather than one unique form widget per resource.

## Visitors and gate operations

Visitor list requests accept validated filters: `q` (name/mobile/vehicle search), `approval_status`, `entry_status`, `visitor_type`, `flat_id`; the security list also accepts boolean `eligible_for_check_in`.

| Method | Path | Access | Input / behavior |
| --- | --- | --- | --- |
| GET | `/security/visitors/options` | Security | Flat/resident selection options. |
| GET | `/security/visitors` | Security | Paginated filtered list. |
| POST | `/security/visitors` | Security | Requires `visitor_name`, `flat_id`, `resident_id`, and visitor type (`GUEST`, `DELIVERY`, `CAB`, `SERVICE_PROVIDER`, `OTHER`). Resident must belong to flat. Creates `PENDING` / `WAITING` visitor request, notifies flat residents in-app, and attempts resident email. |
| GET | `/security/visitors/{visitor}` | Security | Detail subject to visitor policy. |
| PATCH | `/security/visitors/{visitor}/entry` | Security | No body fields required. Allowed only for approved visitor not already entered. Locks record and sets entry state/time. |
| PATCH | `/security/visitors/{visitor}/exit` | Security | No body fields required. Allowed only for currently entered visitor; locks record, sets `EXITED`, approval `COMPLETED`, and exit time. |
| GET | `/resident/visitors` | Resident | Paginated list limited to current resident's flat. |
| GET | `/resident/visitors/pending` | Resident | Pending list for current flat. |
| POST | `/resident/visitors/pre-approvals` | Resident | Requires visitor name, visitor type and `expected_at` >= now. Creates an approved expected visitor tied to resident's flat. |
| GET | `/resident/visitors/{visitor}` | Resident | Detail permitted only for resident's flat. |
| PATCH | `/resident/visitors/{visitor}/approve` | Resident | No body required; only pending request can be approved. |
| PATCH | `/resident/visitors/{visitor}/reject` | Resident | Optional body `reason` (max 500 chars); only pending request can be rejected. |
| GET/POST | `/admin/visitors`, `/admin/visitors/{visitor}` | Admin | Read-only visitor listing/detail. |
| POST | `/visitor-requests` | Authenticated Security | Compatibility creation route; accepts visitor name, optional mobile/purpose/type, optional flat/resident. Returns a bespoke `{message, data: {visitor, notification}}` response. |

Entry/exit side effects and lifecycle state details are in [Architecture and workflows — visitors](WORKFLOWS.md#visitor-lifecycle). Legacy/compatibility visitor route validation differs from `/security/visitors`.

## Maintenance and payments

### Bills and direct payment tracking

| Method | Path | Access | Input / behavior |
| --- | --- | --- | --- |
| GET | `/resident/maintenance-bills` | Resident | Own flat only. Optional filters: `status`, `flat_id`, `billing_month` (ownership scoping still applies). Returns paid/outstanding amounts. |
| GET | `/resident/maintenance-bills/{bill}` | Resident | Own flat only. |
| GET/POST | `/admin/maintenance-bills` | Admin | List with optional `status`, `flat_id`, `billing_month`; create fields below. |
| GET/PUT/PATCH/DELETE | `/admin/maintenance-bills/{bill}` | Admin | Bill resource operations; cancellation/deletion constraints enforced by service/policy. |
| GET | `/admin/maintenance-collection` | Admin | Collection summary. |
| POST | `/admin/maintenance-generate` | Admin | Optional `month` (`YYYY-MM`) and `amount`; triggers monthly invoice generation. |
| GET | `/resident/maintenance-payments` | Resident | Own payment list. Filters: `status`, `maintenance_bill_id`, `flat_id`. |
| POST | `/resident/maintenance-payments` | Resident | Requires bill ID and allowed `payment_method`; amount is calculated by backend, optional client amount is compatibility-only. Tracks a payment record. |
| GET | `/resident/maintenance-payments/{payment}` | Resident | Own payment only. |
| GET/POST | `/admin/maintenance-payments` | Admin | List/create admin payment tracking record. |
| GET | `/admin/maintenance-payments/{payment}` | Admin | Payment detail. |
| PATCH | `/admin/maintenance-payments/{payment}/status` | Admin | Status transition validated by `TransitionPaymentRequest`. |

Bill creation fields: `flat_id`, `billing_month` (`YYYY-MM-DD`, first day of month), `due_date` (on/after billing month), and either `amount` or at least one nonnegative charge component: `base_maintenance`, `water_charge`, `electricity_common_area_charge`, `parking_charge`, `other_charges`, `late_fee`, `discount`. Optional period start/end and notes. Period end must be on/after period start; component values drive the calculated total when supplied. One bill per flat/month is enforced by a unique key.

### Payment orders and gateway

| Method | Path | Access | Input / behavior |
| --- | --- | --- | --- |
| GET | `/resident/payment-orders` | Resident | Own orders, paginated. |
| GET | `/resident/payment-summary` | Resident | Optional query `maintenance_bill_ids` (comma-separated); summary calculated for the resident's own bills. |
| POST | `/resident/payment-orders/full` | Resident | Requires valid `payment_method`; optional distinct `maintenance_bill_ids[]` to pay selected owned bills. Creates order from server balances. |
| GET | `/resident/payment-orders/{paymentOrder}` | Resident | Own order detail. |
| PATCH | `/resident/payment-orders/{paymentOrder}/cancel` | Resident | Cancels only pending order. |
| POST | `/resident/payment-orders/{paymentOrder}/checkout` | Resident | Gateway contract checkout; can return 503 if no gateway is configured. |
| POST | `/resident/payment-orders/{paymentOrder}/confirm-demo` | Resident | Only enabled when `PAYMENT_MODE=demo`; otherwise 503 `DEMO_MODE_DISABLED`. |
| GET | `/resident/payment-orders/{paymentOrder}/receipt` | Resident | Receipt only exists after successful verification; otherwise 422. |
| POST | `/resident/payments/create-order` | Resident | Razorpay path. Optional `invoiceId`/`maintenance_bill_id`, `maintenance_bill_ids[]`, or `pay_all`; server computes outstanding amount. |
| POST | `/resident/payments/verify` | Resident | Requires `razorpay_order_id`, `razorpay_payment_id`, `razorpay_signature`. Validates signature and reconciles idempotently for current resident. |
| GET | `/admin/payment-orders` | Admin | Paginated; optional `status`. |
| GET | `/admin/payment-orders/{paymentOrder}` | Admin | Order detail. |
| GET | `/admin/payment-orders/{paymentOrder}/receipt` | Admin | Verified receipt only. |
| PATCH | `/admin/payment-orders/{paymentOrder}/status` | Admin | Validated status transition. Penalty orders cannot be marked successful by this admin endpoint; verified gateway callback is required. |
| POST | `/webhooks/razorpay` | Public URL; signature required | Checks `X-Razorpay-Signature` against configured webhook secret; processes captured/paid events. Invalid/missing signature returns 400. |

There is also a legacy `/resident/payment-orders` workflow separate from Razorpay checkout. See [Payments](WORKFLOWS.md#maintenance-and-payment-tracking) for the distinction between tracking, demo, and gateway verification.

### History and reports

| Method | Path | Access | Purpose |
| --- | --- | --- | --- |
| GET | `/resident/maintenance-history` | Resident | Maintenance history. |
| GET | `/resident/payment-history` | Resident | Payment history. |
| GET | `/resident/transaction-history` | Resident | Ledger-style transaction history. |
| GET | `/resident/transaction-summary` | Resident | Transaction summary. |
| GET | `/resident/transaction-category-breakdown` | Resident | Category breakdown. |
| GET | `/admin/reports` | Admin | Society dashboard/report data. |

## Penalty management

All routes below require Sanctum unless explicitly stated; role access is in the table.

| Method | Path | Role | Important input / behavior |
| --- | --- | --- | --- |
| GET | `/penalty-rules` | Authenticated | Active rules only. |
| GET | `/penalty-reports` | Authenticated route; intended Admin, Security, Resident | Optional `status`, `category`, `search`; admin sees all, security only self-reported reports, residents only reports assigned to them. Paginated 20. **Authorization gap:** the controller does not explicitly reject STAFF/other roles; those roles are not given the resident/security filters and may receive the unfiltered report list. |
| GET | `/penalty-reports/{report}` | Same scoped access | Includes report, rule, flat, resident, reporter, evidence metadata, penalty/appeals and audit logs. |
| GET | `/penalty-evidence/{evidence}` | Same report scope | Returns private evidence file with stored MIME type and `nosniff`. |
| POST | `/penalty-reports` | Security | Multipart body: `category`, `violation_type`, `incident_at` (not future), `location`, `description`; optional `flat_id`, `vehicle_slot_id`, `maintenance_bill_id`, `booking_id`, `evidence[]` (max 5; JPG/JPEG/PNG/WEBP/PDF, max 10 MB each). Duplicate fingerprint rejected. |
| GET | `/admin/penalty-dashboard` | Admin | Counts by status/category and sums by payment status. |
| GET | `/admin/penalty-rules` | Admin | All rules, paginated 50. |
| POST | `/admin/penalty-rules` | Admin | Create rule fields below. |
| PUT | `/admin/penalty-rules/{rule}` | Admin | Update same validated fields. |
| POST | `/admin/penalty-reports/{report}/decision` | Admin | `decision`: `under_review`, `warning_issued`, `approved`, `rejected`; required `reason`; approved also requires positive `disciplinary_amount` and `responsible_resident_id` for report flat. Optional `repair_cost` and due date. |
| GET | `/admin/penalty-appeals` | Admin | Appeal list, paginated 20. |
| POST | `/admin/penalty-appeals/{appeal}/decision` | Admin | `decision`: `upheld`, `waived`, `adjusted`, `rejected`; required reason; adjusted requires disciplinary amount. |
| POST | `/resident/penalties/{penalty}/appeals` | Owning Resident | Required reason; optional evidence (same max/file types). Only approved penalty; an open appeal is rejected. |
| POST | `/resident/penalties/{penalty}/payment` | Owning Resident | No client amount; creates/reuses a gateway order for approved unpaid penalty; 503 if gateway unavailable. |

Rule body fields: `category` in `parking_vehicle`, `noise_nuisance`, `maintenance_financial`, `property_safety`; `violation_type` must be valid for category; required `minimum_amount` (>=0); optional `maximum_amount` (>=minimum), `late_fee_amount` (>=0), `grace_period_days` (0–365), `requires_evidence`, `active`, and description. `(category, violation_type)` is unique.

**Important implementation boundary:** rule amounts, grace days, and `requires_evidence` are stored and surfaced but are not used by the current approval decision to calculate/validate the penalty. The admin supplies the amount at decision time. Controller sets late fee to zero for this approval flow. Evidence is explicitly required when a positive repair cost is entered. There is no refund workflow for paid penalties. See [Penalty management — actual rules and gaps](WORKFLOWS.md#penalty-management--actual-rules-and-gaps).

## Complaints, notices and community modules

| Method | Path | Role | Important request fields / scope |
| --- | --- | --- | --- |
| GET/POST | `/resident/complaints` | Resident | Create requires `category`, `title`, `description`; optional priority. Current resident/flat are attached server-side. |
| GET/PUT/PATCH | `/resident/complaints/{complaint}` | Owning Resident | View/update own complaint. Resident updates are limited to category/title/description/priority. |
| GET/PUT/PATCH | `/staff/complaints[/{complaint}]` | Staff | Lists complaints assigned to current staff member; update can change status/note. |
| GET/PUT/PATCH | `/admin/complaints[/{complaint}]` | Admin | Admin list/detail/update; update can assign staff and change status/note. |
| GET | `/resident/notices`, `/staff/notices`, `/security/notices` | Role-specific readers | Published, not expired, schedule active and audience matched. |
| GET/POST | `/admin/notices` | Admin | Create requires title/content/audience; optional category, priority, publication flag, dates. |
| GET/PUT/PATCH | `/admin/notices/{notice}` | Admin | Resource except delete. Update validates fields through `UpdateNoticeRequest`. |
| GET | `/amenities` | Authenticated | Active-only for non-admin; admin can see inactive too. |
| GET/POST | `/resident/amenity-bookings` | Resident | Create requires amenity, future/current date, start/end times and optional note. Rejects inactive amenity, too-long booking and overlapping active time. |
| PATCH | `/resident/amenity-bookings/{booking}/cancel` | Owning Resident or Admin | Cancels booking. |
| GET/POST | `/admin/amenities` | Admin | Create requires unique name, max booking hours 1–24; optional active/open/close fields. |
| PUT/PATCH | `/admin/amenities/{amenity}` | Admin | Update amenity. |
| GET | `/admin/amenity-bookings` | Admin | All bookings. |
| PATCH | `/admin/amenity-bookings/{booking}/status` | Admin | Status in `APPROVED`, `REJECTED`, `CONFIRMED`, `CANCELLED`, `COMPLETED`. |
| GET/POST | `/admin/parking-slots` | Admin | Create slot with unique slot number and type; optional flat/vehicle. |
| GET/PUT/PATCH | `/admin/parking-slots/{parkingSlot}` | Admin | Resource except delete. |
| GET | `/resident/parking-slots` | Resident | Parking inventory (controller scope applies). |

Complaint create accepts category from `Complaint::categories()`, title <=255, description <=5000, and priority from `LOW`, `MEDIUM`, `HIGH`, `URGENT`, `EMERGENCY`. Category `ELECTRICAL` normalizes to `ELECTRICITY`. Update may add `assigned_staff_id`, a permitted status and optional note; transition allow-list is enforced in `ComplaintService`.

Notice audience values are `ALL`, `RESIDENTS`, `OWNERS`, `STAFF`. Create requires title, content <=10000, and audience; `expires_at` must be after `published_at`. A future publication date stays scheduled. Notification is emitted when a notice first becomes published and is due.

## Parcels, messaging and notifications

| Method | Path | Role | Input / behavior |
| --- | --- | --- | --- |
| GET | `/resident/parcels`, `/resident/parcels/{parcel}` | Resident | Own resident's parcels only. |
| GET/POST | `/security/parcels`, `/staff/parcels`, `/admin/parcels` | Security/Staff/Admin | Create requires flat, resident, courier, parcel type (`DOCUMENT`, `BOX`, `FOOD`, `OTHER`); optional tracking/notes; resident must belong to flat. |
| GET | `/{role}/parcels/{parcel}` | Role-specific | Reads scoped to resident or operational role. |
| PATCH | `/{role}/parcels/{parcel}/collect` | Security/Staff/Admin | No body; only received/awaiting pickup parcel can be collected. |
| GET/POST | `/conversations` | Authenticated participants | List/create a conversation. |
| GET | `/conversations/{conversation}` | Authenticated participants | Read conversation and messages. |
| POST | `/conversations/{conversation}/messages` | Authenticated participant | Sends a message body validated by controller. |
| PATCH | `/conversations/{conversation}/read` | Authenticated participant | Marks conversation read. |
| GET | `/notifications` | Authenticated | Current user's notification records. |
| GET | `/notifications/unread-count` | Authenticated | Current user's unread count. |
| PATCH or POST | `/notifications/{notification}/read` | Authenticated owner | Marks one notification read. |
| PATCH or POST | `/notifications/read-all` | Authenticated | Marks all current user's notifications read. |
| POST/DELETE | `/device-tokens` | Authenticated | Register/update or deactivate FCM device token. `POST /fcm-token` is a compatibility alias. |

Parcel create is HTTP 201 with `data`; collection returns updated parcel `data`. Conversation and notification payloads are endpoint-specific; see controllers for exact current serialization. No real-time messaging transport is configured.

## Response errors and validation

| Status | Typical meaning |
| --- | --- |
| 400 | Invalid Razorpay webhook signature. |
| 401 | Missing/invalid Sanctum token; Flutter clears local session. |
| 403 | Authenticated role/action forbidden. |
| 404 | Resource absent or deliberately hidden by an ownership scope. |
| 422 | Field validation failure, invalid state transition, ownership mismatch, duplicate operation, or missing verified receipt. |
| 503 | Gateway/demo checkout not configured/enabled. |
| 5xx | Unhandled server/provider failure; inspect server logs without returning secret details. |

Input bodies and exact response resources change with implementation; this reference highlights required/important fields rather than replacing the source Form Requests and resources. Never paste live bearer tokens, user data, or provider secrets into examples or issue reports.
