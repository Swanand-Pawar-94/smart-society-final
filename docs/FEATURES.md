# Nivora Feature Catalog

This catalog describes the application behavior visible in the inspected Flutter client and Laravel API. **Implemented** means the corresponding app/API workflow exists in this repository; it does not prove the production deployment, external credentials, or every role/device combination has been verified. **Partial** identifies a workflow with an important limitation or incomplete integration. **Not verified** means repository evidence cannot establish the live behavior.

The mobile labels and paths below refer to the current app. Backend routes and persistence details are summarized here; see the [API reference](API_REFERENCE.md), [workflow guide](WORKFLOWS.md), [data model](DATA_MODEL.md), and [end-user guide](USER_GUIDE.md) for fuller route, lifecycle, and step-by-step details.

## Feature directory

| Feature | Status | Main roles | Details |
| --- | --- | --- | --- |
| [Sign-in, registration, and account access](#sign-in-registration-and-account-access) | Implemented with limitations | All | Login, registration, reset, token handling |
| [Role access and navigation](#role-access-and-navigation) | Implemented | All | Role-specific destinations and API boundaries |
| [Profiles and resident records](#profiles-and-resident-records) | Implemented | Resident, admin | Profile edits and resident management |
| [Units and society records](#units-and-society-records) | Implemented | Admin, resident | Flat/unit assignment and lookup |
| [Resident dashboard](#resident-dashboard) | Implemented | Resident | Resident summary and shortcuts |
| [Security dashboard](#security-dashboard) | Partial | Security | Gate and parcel overview; alert limitation |
| [Administrator dashboard](#administrator-dashboard) | Implemented | Admin | Society operations overview |
| [Staff workspace](#staff-workspace) | Implemented | Staff | Staff-facing operational modules |
| [Visitor requests and pre-approval](#visitor-requests-and-pre-approval) | Implemented | Resident, security, admin | Request, approve, reject, pre-approve |
| [Gate check-in, check-out, and history](#gate-check-in-check-out-and-history) | Implemented | Security | Entry and exit tracking |
| [Maintenance bills and invoices](#maintenance-bills-and-invoices) | Implemented | Resident, admin | Bill generation, dues, invoice views |
| [Payment tracking and history](#payment-tracking-and-history) | Implemented | Resident, admin | Manual records, ledger, receipts, export |
| [Razorpay payments](#razorpay-payments) | Partial; live use unverified | Resident, admin | Order and signature verification |
| [Penalty rules](#penalty-rules) | Partial | Admin | Rule configuration and enforcement gaps |
| [Penalty reports and decisions](#penalty-reports-and-decisions) | Implemented with authorization caveat | Security, admin, resident | Evidence, review, assignment |
| [Penalty appeals and payment](#penalty-appeals-and-payment) | Partial | Resident, admin | Appeal decisions and payment constraints |
| [Parcels](#parcels) | Implemented with workflow caveat | Resident, staff, security, admin | Record, view, mark collected |
| [Complaints](#complaints) | Implemented | Resident, staff, admin | Submission and status handling |
| [Notices](#notices) | Implemented | Admin, all authenticated roles | Draft, publication, audience, expiry |
| [Staff management](#staff-management) | Implemented with account provisioning split | Admin, staff | Staff records and activation |
| [Parking](#parking) | Implemented; assignment depth varies | Resident, admin | Slot information and administration |
| [Amenities and bookings](#amenities-and-bookings) | Partial | Resident, admin | Booking and conflict checks |
| [In-app and push notifications](#in-app-and-push-notifications) | Partial | All | Database notifications and configured FCM |
| [Reports and analytics](#reports-and-analytics) | Implemented | Admin | Operational and occupancy reports |
| [Messaging](#messaging) | Partial | All permitted participants | API-backed conversations; no live transport |
| [Payment administration and resident transactions](#payment-administration-and-resident-transactions) | Implemented | Admin, resident | Administrative records and resident activity |
| [Diagnostic and emergency actions](#diagnostic-and-emergency-actions) | Partial / limited | Admin, security | Health endpoint and local-only emergency feedback |

## Sign-in, registration, and account access

**Status:** Implemented. Password reset is a mail-dependent flow; remember-me behavior is a client-side token-persistence choice. No public admin registration is provided.

**Roles:** Resident, Society staff, Security team, and Admin can sign in. Registration offers resident, staff, and security choices; administrator accounts are provisioned separately.

**Mobile path:** Login screen. Fields are `Email or mobile number`, `Sign in as`, and `Password`; the form also exposes `Remember me`, `Forgot password?`, `Sign in`, and `Create an account`. Signup fields depend on the selected role. Resident signup collects identity/contact and unit/relationship details; staff and security signup collect role-specific employment details. Staff/security accounts require administrator activation.

**How it works:** The client submits credentials to the Laravel authentication endpoint. Laravel validates credentials and role, issues a Sanctum token, and the client stores it using secure storage. Authenticated requests send the bearer token. Logout revokes the current token. The password reset request sends an email link through the configured mailer; an in-app password reset form/token completion flow was not verified in the mobile app.

**Validation and errors:** Required fields and password constraints are validated by the client and API. Invalid credentials, unavailable accounts, validation failures, expired/invalid tokens, or an unreachable API prevent entry and should be treated as sign-in failures. Account status and role determine access after authentication.

**Data/security:** Uses the user account, role/status, Sanctum personal access token, and resident/staff profile records. Passwords are handled by Laravel hashing; never share or store passwords in support messages. Registration and account-access details are in [USER_GUIDE.md](USER_GUIDE.md#3-login-and-account-access), [API_REFERENCE.md](API_REFERENCE.md#public-diagnostics-and-authentication), and [DATA_MODEL.md](DATA_MODEL.md#core-entity-map).

**Known limits and tests:** No remember-me checkbox should be interpreted as a server-side session policy. Existing backend auth/authorization tests and Flutter login/roles widget tests are present; they were not run for this documentation change. See [test inventory](DEPLOYMENT_TESTING_SECURITY.md#testing-and-quality-workflow).

## Role access and navigation

**Status:** Implemented through Flutter role navigation and Laravel role middleware/controller checks.

**Mobile paths:** Residents use `Home`, `My Unit`, `Gate`, and `More`; security uses `Dashboard`, `Visitors`, `Parcels`, and `More`; admins use `Dashboard`, `Residents`, `Finance`, and `More`. Staff see a `Staff workspace` with Dashboard, Profile, Complaints, Parcels, Notices, Messages, and Notifications. App-bar notification/profile controls are also available where present.

**Access behavior:** The selected role controls the destinations shown in the app. The API independently enforces authentication, role middleware, and record ownership/scope checks. Hiding a button is not the security boundary; the backend must authorize every operation. A forbidden operation can return an authorization error even if a stale client screen exposes it.

**Caveat:** A review identified `GET /api/penalty-reports` as authenticated without the expected role-specific fallback rejection, which can expose an unfiltered report list to an otherwise authenticated role. This should be treated as a backend authorization issue and not as intended permission. See [authorization notes](DEPLOYMENT_TESTING_SECURITY.md#security-controls-and-known-gaps) and [penalty reports](#penalty-reports-and-decisions).

## Profiles and resident records

**Status:** Implemented. Resident self-service and administrator resident management are distinct flows.

**Resident path:** `More` → `Profile` / `My profile` (the label varies by role workspace). Review or edit the fields presented by the profile form and save. The authenticated profile endpoint scopes the record to the current account. Available fields depend on the account type and current form; do not assume every registration-only field can later be edited.

**Admin path:** `Residents` or `More` → `Residents` opens the resident list and management forms. Admins can search/select resident records and use the available create/edit actions to maintain resident details and unit association. Backend validation protects required identity and relationship fields.

**Data and limits:** User, resident profile, flat/unit, and resident relationship records are linked through migrations. An admin can manage residents; residents cannot edit another account. See [resident and flat API details](API_REFERENCE.md#dashboards-profiles-residents-flats-and-staff), [resident data model](DATA_MODEL.md#module-to-model-and-table-map), and [user steps](USER_GUIDE.md#5-resident-guide).

## Units and society records

**Status:** Implemented for a single society.

**Admin path:** `More` → `Units` (or the unit controls under resident management) provides flat/unit record administration. Create or edit the unit fields shown in the form, save, then assign a resident through the resident relationship controls. Existing units are also offered as registration/assignment choices where applicable.

**Resident path:** `My Unit` displays the signed-in resident’s assigned flat/unit and related information, including parking information when present. This is a view of the account’s current association, not a facility for changing another resident’s unit.

**Data and limitation:** Flats/units and resident associations are persisted by Laravel models/migrations. The schema is single-society; multi-society tenancy and cross-society isolation are not implemented. See [DATA_MODEL.md](DATA_MODEL.md#core-entity-map).

## Resident dashboard

**Status:** Implemented.

**Path:** Resident `Home`. The dashboard surfaces current resident summaries and shortcuts for penalties, dues, gate/visitor activity, helpdesk, and visitors expected today. It can also show upcoming amenity booking and announcements when available.

**Actions:** Quick actions include `Add visitor`, `Pay dues`, `Book amenity`, and `Helpdesk`. Selecting a card or shortcut opens its corresponding module; the dashboard is a summary, so records and final status should be checked in the module itself.

**Data/behavior:** Dashboard data comes from the authenticated resident dashboard API and is scoped to the current resident/unit. Empty values can mean there are no matching records; request errors indicate the API could not provide the summary. See [resident guide](USER_GUIDE.md#5-resident-guide) and [dashboard API](API_REFERENCE.md#dashboards-profiles-residents-flats-and-staff).

## Security dashboard

**Status:** Partially implemented. Visitor/parcel metrics and gate workflows are present; one emergency action is only local feedback.

**Path:** Security `Dashboard`. Summary cards include expected visitors, awaiting approval, currently checked in/out, parcels awaiting pickup, and gate status. Shortcuts include `Check-in visitor`, `Check-out visitor`, `Record parcel`, `Vehicle entry`, `View all visitors`, and `Emergency alert` where shown.

**Use:** Use visitor actions to work only with eligible requests and record entry/exit. `Record parcel` opens the parcel intake form. `Vehicle entry` currently uses the gate visitor creation flow and does not collect a vehicle registration/plate number in that form.

**Important limitation:** `Emergency alert` displays a local success Snackbar after confirmation; no backend dispatch, notification to residents, or emergency-service integration was verified. Do not rely on it to contact anyone. See [security guide](USER_GUIDE.md#6-security-team-guide).

## Administrator dashboard

**Status:** Implemented.

**Path:** Admin `Dashboard`. It presents society operation summaries and links to administrative destinations. The main navigation includes `Dashboard`, `Residents`, `Finance`, and `More`; the `More` area exposes management and operations such as Units, Staff, Penalty management, Maintenance, Complaints, Visitors, Parcels, Notices, Parking, Amenities, and Reports.

**Use and data:** Dashboard cards summarize API data; open the source module to review records and perform changes. Admin routes are protected by role middleware, and controller validation applies to create/update operations. The dashboard does not itself change bill, visitor, or penalty state. See [administrator guide](USER_GUIDE.md#8-administrator-guide).

## Staff workspace

**Status:** Implemented with a narrower, role-specific set of modules.

**Path:** Staff `Staff workspace`. Available destinations include Dashboard, Profile, Complaints, Parcels, Notices, Messages, and Notifications. A staff member’s access is limited by the staff role and record-specific backend rules; the admin’s operational menus are not automatically available to staff.

**Use:** Open a module, inspect the list, and use the actions shown for the selected record. Complaint and parcel operations are subject to API validation and role restrictions. Staff profiles and user accounts are related but are provisioned through separate steps; see [staff management](#staff-management).

## Visitor requests and pre-approval

**Status:** Implemented for resident requests, resident pre-approval, security intake, and authorized administration.

**Resident path:** `Gate` → `Add visitor` opens `Pre-approve visitor`. Enter visitor name, type (guest, delivery, cab, service, or other), visit date/time, and any fields shown; submit with `Pre-approve visitor`. The form defaults the visit time to approximately one hour ahead. Review pending visitor requests in the resident Gate list and use `Approve` or `Reject` when those actions are available.

**Security/admin path:** Security can create a visitor request from `Visitors`/gate actions by entering the visitor and resident/unit information. Authorized users can review the request. Security check-in is available only for approved eligible visits; a pending/rejected/expired visit cannot be checked in through the normal eligible list.

**Lifecycle/data:** Visitor records link a resident/unit and include visit time/type plus approval and gate status/timestamps. Duplicate or invalid transitions are rejected by the API. New request/decision events can create database notifications; push delivery depends on FCM configuration. See [visitor workflow](WORKFLOWS.md#visitor-lifecycle), [visitor API](API_REFERENCE.md#visitors-and-gate-operations), and [user steps](USER_GUIDE.md#5-resident-guide).

## Gate check-in, check-out, and history

**Status:** Implemented.

**Security path:** `Visitors` → `Check In Visitor` lists approved eligible visitors. Search with `Search visitor...`, select a visitor, review the confirmation details, and choose `Check In`. For an in-progress visit, open the check-out action and confirm `Check Out`. The checked-out metric/card opens visit history.

**Validation and states:** The server checks allowed transitions and rejects duplicate check-in or check-out. Entry/exit timestamps are saved to the visitor record; history reflects completed visits. Only authorized security operations can record gate transitions. A failed API response means the transition was not confirmed; refresh the list before retrying to avoid duplicate attempts.

**Tests:** Backend security visitor workflow and visitor management tests, plus Flutter security visitor workflow tests, exist in the repository; not run during this documentation task. More details: [visitor workflow](WORKFLOWS.md#visitor-lifecycle).

## Maintenance bills and invoices

**Status:** Implemented.

**Resident path:** Open `My Dues` from `Home`/`More` or the `Pay dues` shortcut. `Open Invoices` lists unpaid/part-paid bills; open a bill to view invoice details and select `Pay full amount`. The screen also provides `History` and `Advance` views where applicable. Invoice/PDF actions are available on supported bill details.

**Admin path:** `Finance` or `More` → `Maintenance` provides bill administration. Admins can create/manage maintenance bills and the backend also has a bill-generation command. Bill amounts, due dates, and status are validated and stored server-side; a resident sees their own bills.

**Lifecycle/data:** Bills are associated with flats/residents; payment records and bill balances determine outstanding dues. Payment success must be confirmed in the backend before a bill is treated as paid. See [maintenance workflow](WORKFLOWS.md#maintenance-and-payment-tracking), [bill API](API_REFERENCE.md#maintenance-and-payments), and [data model](DATA_MODEL.md#module-to-model-and-table-map).

## Payment tracking and history

**Status:** Implemented, with manual payment review and gateway behavior depending on configuration.

**Resident path:** From an invoice select `Pay full amount`, or select multiple bill checkboxes and choose `Pay Now`. Review the server-calculated payment summary and choose an available payment option. `My Dues` → `History` shows payment records; transaction activity/ledger views expose `All`, `Debit`, and `Credit` filters and a PDF export action where available. Under `More` → `Payments`, a manual payment-record form may be shown for submitting payment details for review.

**Admin path:** Admin finance/payment screens and API endpoints allow authorized payment review/management. A manual submission is not equivalent to a verified gateway payment: wait for its status to be updated before treating a bill as settled.

**Data/security:** Payment orders, order items, receipts, resident transactions, and ledger entries are persisted with their related bills and users. Amounts are computed/validated by the API. See [payment guide](USER_GUIDE.md#5-resident-guide), [payment API](API_REFERENCE.md#maintenance-and-payments), and [payment model](DATA_MODEL.md#module-to-model-and-table-map).

## Razorpay payments

**Status:** Partial; live production operation is not verified.

**Resident path:** Begin checkout from an invoice with `Pay full amount` or from selected dues with `Pay Now`. If gateway configuration is available, the app opens the Razorpay checkout flow. Complete the provider UI and return to Nivora; the server verifies the order/payment signature before recording success.

**Backend/configuration:** Laravel exposes order creation and verification endpoints. Server-side Razorpay keys and mode are required; secrets must remain on the backend. If credentials/configuration are missing, order creation can be unavailable (including a service-unavailable response). Never treat a client-side success screen alone as proof: verify the resulting payment/history/bill state.

**Limitations:** The repository’s example configuration is test-oriented/placeholders. No live merchant activation, production webhook, credentials, or live transaction is verified. See [Payments](../README.md#payments) and [payment API](API_REFERENCE.md#payment-orders-and-gateway).

## Penalty rules

**Status:** Partial. Rule administration exists, but configured safeguards are not all enforced by the decision workflow.

**Admin path:** `More` → `Penalty management` → rules. Admins can configure category/violation type, fee bounds, grace period, evidence requirement, and active state as shown by the form. Rules are stored with the penalty configuration records.

**Enforcement caveat:** Fee bounds, grace period, and evidence-required flags are stored but the report decision path does not consistently enforce them, and it does not require an active matching rule before decision. The amount entered by the admin is operative. Do not assume a configured rule automatically calculates or blocks a charge. This is an implementation limitation, not a user-facing guarantee.

**Rule categories:** Current categories cover parking/vehicle, noise/nuisance, maintenance/financial, and property/safety, with violation types selected from the category. See [penalty semantics](DATA_MODEL.md#penalty-rule-and-assignment-semantics) and [workflow caveats](WORKFLOWS.md#penalty-management--actual-rules-and-gaps).

## Penalty reports and decisions

**Status:** Implemented with an authorization caveat for the general report-list endpoint.

**Security path:** `More` → penalty reports or the dashboard report action → `Report violation`. Choose a category/type, optionally select an affected flat and related maintenance bill/parking record when relevant, enter location/description and incident date/time, and attach up to five photos when the picker is offered. Submit the report for admin review.

**Admin path:** `More` → `Penalty management` → review reports. Reports can move from reported to under review, warning issued, approved, or rejected using the available decision actions. Approval requires a positive disciplinary amount and a responsible resident in the reported flat; repair-cost evidence requirements apply in the relevant path. An approved report creates one penalty record in unpaid state.

**Authorization warning:** `GET /api/penalty-reports` was found to lack the expected role-specific fallback rejection and may return an unfiltered list to an authenticated role that should not have it. Treat this as a backend issue; do not assume the list is safely role-scoped until corrected and verified. Admin decision endpoints have their own role controls.

**Data and evidence:** Reports, evidence files, rule references, assigned penalties, and audit events are stored separately. Access to evidence is intended to be restricted to permitted participants. See [penalty API](API_REFERENCE.md#penalty-management), [data model](DATA_MODEL.md#penalty-rule-and-assignment-semantics), and [security guide](DEPLOYMENT_TESTING_SECURITY.md#security-controls-and-known-gaps).

## Penalty appeals and payment

**Status:** Partial.

**Resident path:** Open `Penalties`, select an assigned penalty, review the violation details, and use the appeal action if available. Provide a reason and supporting evidence where requested. An assigned resident can also begin payment from the penalty detail when payment configuration permits.

**Admin path and states:** Admins review appeals and can uphold, waive, adjust, or reject them. A penalty can be unpaid or paid; the appeal outcome updates the associated penalty according to the decision. Already paid penalties cannot be waived/adjusted through the current flow, and no refund workflow was verified.

**Payment limitation:** Penalty payment is Razorpay-based in the current resident flow; there is no verified manual/demo path for production. Live availability depends on backend gateway configuration. Check the resulting penalty and payment state after returning from checkout. See [penalty workflow](WORKFLOWS.md#penalty-management--actual-rules-and-gaps).

## Parcels

**Status:** Implemented with a collection-flow caveat.

**Receive path:** Security/staff (and authorized admin) open `Parcels` → `Record parcel`/`Receive parcel`; enter the resident or unit, courier, parcel type, and any tracking/notes fields shown, then save. A creation notification can be generated for the resident. Residents open `Parcels` to view their own parcel records and pickup status.

**Collection:** An authorized staff/security/admin user opens the parcel record and selects the available collected action. The saved status is then visible in the parcel list/history.

**Caveat:** A transaction/lock-aware `ParcelWorkflowService` exists, but the routed parcel controller does not use it for collection. The current endpoint is weaker about concurrency and no collection notification was verified. Check the saved status rather than assuming a tap completed collection. See [parcel workflow](WORKFLOWS.md#other-module-workflows), [API reference](API_REFERENCE.md#parcels-messaging-and-notifications), and [data model](DATA_MODEL.md#lifecycles).

## Complaints

**Status:** Implemented.

**Resident path:** `More` → `Complaints`/`Helpdesk` → create complaint. Choose a category (such as Plumbing, Electricity, Security, Cleaning, Lift, Parking, Water, Noise, Maintenance, or Other), enter a title and description, choose a priority, and submit. Open the complaint later to review its status and any available update action.

**Staff/admin path:** Open `Complaints`, select a record, and use the status/update actions shown for the role. The API scopes resident reads to the resident’s own records and applies role-specific access to staff/admin operations. Validation requires the necessary complaint fields and supported status values; status history is persisted.

**Outcome/errors:** A successful submission appears in the user’s complaint list. A validation or authorization response means the requested update did not complete. See [complaint guide](USER_GUIDE.md#5-resident-guide), [API reference](API_REFERENCE.md#complaints-notices-and-community-modules), and [complaint data lifecycle](DATA_MODEL.md#lifecycles).

## Notices

**Status:** Implemented for admin creation/publication and role-scoped reading.

**Admin path:** `More` → `Notices` → create. Enter title/content, choose category, priority, and audience, then publish now or save as a draft; scheduling and expiry fields are available in the backend/form where shown. Reopen the list to confirm the notice’s state.

**Reader path:** Residents, staff, and security open `Notices` to read items visible to their role/audience. Drafts and expired notices are not intended to appear as active notices. The API applies publication, expiry, and audience rules.

**Limitations:** Mobile edit/delete actions for existing notices were not verified. See [notice workflow](API_REFERENCE.md#complaints-notices-and-community-modules) and [lifecycle model](DATA_MODEL.md#lifecycles).

## Staff management

**Status:** Implemented, with account creation separated from staff record creation.

**Admin path:** `More` → `Staff` to create or maintain staff details, such as designation and joining information. This creates/updates the staff profile record. It does not necessarily create a login credential or activate an account by itself.

**Staff account path:** Staff/security users can register through the account flow; an administrator must activate eligible accounts. Admins should verify both the staff record and account status before expecting staff sign-in. The backend applies role and activation checks.

**Data:** Staff profile and user account are related records; they have separate lifecycles. See [staff API](API_REFERENCE.md#dashboards-profiles-residents-flats-and-staff) and [staff model mapping](DATA_MODEL.md#module-to-model-and-table-map).

## Parking

**Status:** Implemented; user-facing assignment details vary by screen.

**Resident path:** `My Unit` or `More` → `Parking` to view available parking information associated with the resident/unit. Use the records shown in the app; a vehicle entry action on Security dashboard is not a vehicle registration module and does not record a plate number in its current form.

**Admin path:** `More` → `Parking` to manage parking slots and related records using the actions and fields displayed. The API validates slot records and exposes parking information to authorized users.

**Limitations:** Do not infer automated vehicle access control, plate recognition, or a complete resident vehicle registry from the parking/gate screens. See [parking API](API_REFERENCE.md#complaints-notices-and-community-modules).

## Amenities and bookings

**Status:** Partial. Booking records and conflict checks are implemented; a complete live availability calendar and operating-hour enforcement were not verified.

**Resident path:** `More` → `Amenities` → choose an amenity and tap `Book`. Select date, start time, end time, and enter notes if offered. Review the `Confirm Amenity Booking?` dialog and choose `Confirm Booking`. Open `Bookings` to review the saved booking or use a cancellation action when available.

**Validation:** The backend checks that the amenity is active, the end time follows the start time, and the requested time does not conflict with an existing booking. It does not enforce configured opening/closing hours in the inspected flow. The list should not be treated as guaranteed real-time availability until the booking response succeeds.

**Admin path:** Admins manage amenity records and booking status through the admin module/API. See [booking lifecycle](DATA_MODEL.md#lifecycles) and [user guide](USER_GUIDE.md#5-resident-guide).

## In-app and push notifications

**Status:** In-app/database notifications are implemented; live push delivery is configuration-dependent and unverified.

**Mobile path:** Use the app-bar notification bell or `More` → `Notifications`. Open a notification to review it; use the available mark-read action, or mark all read when shown. The unread indicator reflects notification read state.

**Backend/client behavior:** Notification records are stored by Laravel. The app registers and refreshes FCM device tokens through authenticated API endpoints and uses local notifications for foreground messages. Visitor workflows can create database notifications independently of push delivery.

**Configuration and errors:** Actual FCM delivery needs Firebase client configuration and server credentials/project configuration. Missing credentials or push service failure does not necessarily undo the underlying visitor/parcel operation. No live production push delivery was verified. See [notification guide](../README.md#notifications), [API reference](API_REFERENCE.md#parcels-messaging-and-notifications), and [security/configuration](DEPLOYMENT_TESTING_SECURITY.md#security-controls-and-known-gaps).

## Reports and analytics

**Status:** Implemented for administrator report endpoints and report screens.

**Admin path:** `More` → `Reports`. Select the available period, such as Today, This week, This month, Last month, This year, or Custom, then open the desired report. Current report areas include maintenance collection, operations, occupancy/capacity, parking, and staff metrics. The backend computes results from current records and accepts validated date ranges.

**Access and interpretation:** Reports are administrator data and should be interpreted as a snapshot for the selected period, not an accounting audit. Empty results may mean there were no matching records. The report endpoints do not change source records. See [reports API](API_REFERENCE.md#complaints-notices-and-community-modules) and [administrator guide](USER_GUIDE.md#8-administrator-guide).

## Messaging

**Status:** Partial. Conversation/message screens and API endpoints exist; real-time delivery is not configured.

**Mobile path:** Open `Messages` from the role’s More/workspace menu or a conversation entry. Open an existing conversation, review its history, enter a message in the composer, and send. The app does not expose a verified create-conversation workflow, so a user may only be able to message within conversations already provided to them.

**Backend/security:** Conversation participants and messages are persisted. The API checks authenticated access/participation. No broadcasting/WebSocket transport is configured in the repository; users may need to refresh or reopen a conversation to see new messages. Do not describe this as live chat. See [messaging API](API_REFERENCE.md#parcels-messaging-and-notifications) and [architecture](WORKFLOWS.md#system-architecture).

## Payment administration and resident transactions

**Status:** Implemented. This section covers administrative review and transaction records; resident checkout is described under [payment tracking](#payment-tracking-and-history).

**Admin path:** `Finance` and `More` → payment/transaction options expose the administrative finance records shown for the role. Review the resident, bill, amount, method, reference, and state before taking an available review action. The server validates payment references and state transitions; use the saved payment history to confirm the outcome.

**Resident path:** The resident’s `My Dues` history and payment/transaction screens show records scoped to that user. Ledger entries distinguish debits and credits; exports are generated from the displayed ledger. A submitted manual record can remain pending review.

**Data:** Payments, payment orders, order items, receipts, resident transactions, and ledger entries have separate meanings. A receipt/history item should be read with its status and related bill. See [API payment endpoints](API_REFERENCE.md#maintenance-and-payments) and [data model](DATA_MODEL.md#module-to-model-and-table-map).

## Diagnostic and emergency actions

**Status:** Partial and limited.

**Diagnostics:** `GET /api/health` is a public health endpoint. The production endpoint was observed returning HTTP 200 on 2026-10-19, but that only established endpoint availability at that time; it did not verify every module or external integration. `GET /api/debug-info` is also public in the inspected routes and should not be used to expose sensitive deployment details.

**Emergency action:** Security dashboard `Emergency alert` currently gives local confirmation only; no remote dispatch, backend record, resident alert, or emergency-services integration was verified. For urgent incidents, use the society’s established emergency contact process.

## Verification and test inventory

The repository contains these relevant test files (file presence only):

- Backend API feature tests: `backend/tests/Feature/Api/AuthenticationTest.php`, `AuthorizationTest.php`, `ResidentAndFlatTest.php`, `ResidentDashboardTest.php`, `SecurityVisitorWorkflowTest.php`, `VisitorManagementTest.php`, `VisitorNotificationEndToEndTest.php`, `VisitorFcmNotificationTest.php`, `DeviceTokenTest.php`, `FirebaseCloudMessagingServiceTest.php`, `NotificationTest.php`, `MaintenanceTest.php`, `PaymentOrderTest.php`, `RazorpayPaymentTest.php`, `ComplaintNoticeTest.php`, `DashboardAndNoticeLifecycleTest.php`, `SelectionOptionsAndParcelsTest.php`, and `PenaltyManagementTest.php`.
- Backend unit/console tests: `backend/tests/Unit/FirebasePushChannelTest.php` and `backend/tests/Feature/Console/CreateInitialAdminCommandTest.php`.
- Flutter tests: `mobile/test/login_roles_test.dart`, `residents_screen_test.dart`, `security_visitor_workflow_test.dart`, `dues_navigation_test.dart`, `payment_order_overflow_test.dart`, `penalty_navigation_test.dart`, `complaint_edit_test.dart`, `time_picker_test.dart`, and `widget_test.dart`.

**Results:** None of these suites were run for this documentation update. File presence is not evidence that the current branch passes. The [deployment/testing guide](DEPLOYMENT_TESTING_SECURITY.md#testing-and-quality-workflow) lists the available commands and release checks.

## Not implemented or not verified

| Capability | Status in the inspected repository |
| --- | --- |
| Multiple societies with tenant isolation | Not implemented; current schema is single-society. |
| Real-time messaging/broadcasting | Not configured; conversation APIs and screens are API-backed. |
| Create a new message conversation in the mobile UI | Not verified; the app exposes existing conversation views/composer. |
| Security emergency dispatch to residents/services | Not implemented; the current action displays local feedback only. |
| Vehicle plate capture or automated gate/vehicle recognition | Not implemented in the current security vehicle-entry flow. |
| Amenity opening-hours enforcement and live availability calendar | Not implemented/verified; active state, duration, and booking overlap checks exist. |
| In-app password-reset completion form | Not verified; the app requests an email reset link, and completion depends on the configured mail/reset flow. |
| Live FCM push delivery, Razorpay live payments, and deployed mobile build verification | Not verified; all depend on external configuration and production checks. |
| Public APK download/distribution | Not verified by the repository documentation; use only a distribution link supplied by the society administrator. |

**Tests were not run for this documentation update.** Test-file presence is not evidence that the current branch passes; use the test guide for commands and record actual results when they are run.
