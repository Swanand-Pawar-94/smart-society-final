# Nivora Mobile App User Guide

This guide explains how to use the screens and actions currently present in the Nivora mobile app. Screen labels below match the app where practical. The guide reflects the repository inspected on 2026-10-19; deployed builds can differ.

## Contents

- [Introduction to Nivora](#1-introduction-to-nivora)
- [Getting started](#2-getting-started)
- [Login and account access](#3-login-and-account-access)
- [Understanding the interface](#4-understanding-the-interface)
- [Resident guide](#5-resident-guide)
- [Security team guide](#6-security-team-guide)
- [Society staff guide](#7-society-staff-guide)
- [Administrator guide](#8-administrator-guide)
- [Feature status and limitations](#9-feature-status-and-limitations)
- [Common issues](#10-common-issues)
- [Privacy and safe use](#11-privacy-and-safe-use)
- [Related documentation](#12-related-documentation)

## 1. Introduction to Nivora

Nivora is a mobile app for common residential society tasks. It brings visitor approvals and gate records, maintenance bills, parcel logging, complaints, notices, bookings, and account notifications into one place. It is intended for residents, security personnel, society staff, and administrators.

The app sends authenticated requests to the Nivora backend over its configured API connection. The backend checks the account and its role, saves allowed changes, and returns data for the app to display. Notifications may also be delivered by Firebase when the app and server are configured for push notifications. The app can continue to show in-app notifications even when push delivery is unavailable.

| Role | Main purpose in the app |
| --- | --- |
| Resident | Manage expected visitors, view unit information and dues, pay or submit payment details, raise complaints, book amenities, view notices and parcels, and manage penalty appeals/payments. |
| Security team | Register gate visitors, record visitor entry and exit, log parcel deliveries, view notices, and submit violation reports. |
| Society staff | Work with assigned complaints and parcel records, and view notices and messages. |
| Administrator | Manage residents, units, staff, bills, payment activity, notices, complaints, parking, amenities, parcels, visitor records, reports, and penalty decisions. |

The exact screens depend on the signed-in role. A button or module available to an administrator may not appear for a resident or staff member.

## 2. Getting started

### Platform and installation

The repository contains an Android app configuration. No verified Google Play listing or official public download link was found. A local build artifact exists in the developer workspace, but its version, signing identity, and suitability for distribution have not been verified; it is not an official download source.

Ask your society administrator for the current approved Nivora installation method and build. Install only an app package supplied through the society's trusted channel. If the administrator does not know which build is current, ask them to verify the app version and API environment before distributing it. This guide does not provide a public APK link.

### What you need before signing in

- A Nivora account registered for the correct society.
- The email address or mobile number associated with the account, and its password.
- The correct role selected on the login screen: Resident, Administrator, Society staff, or Security team.
- A network connection to the backend configured in the installed app.

The production API configured by the project is `https://smartsociety.codevizor.com/api`. A normal user cannot change the API address inside the app. The app build must have been configured for the correct backend. If the app reports that the API is not configured, or a local/test server appears, contact the person who supplied the build or your society administrator.

### First launch and connection errors

On launch, Nivora checks the backend and restores a saved sign-in when one is available. A successful sign-in opens the dashboard or role workspace for that account. If the server cannot be reached, the app may show an error or retry action instead of current data.

Try these steps when a page cannot load:

1. Confirm the device has internet or the expected local network connection.
2. Close and reopen the app, then use **Retry** or pull down on the page to refresh.
3. Check that you were given the current app build and correct account role.
4. If the problem continues, tell the society administrator the exact on-screen error, the page you were opening, and approximately when it happened. Do not send your password or one-time reset link.

The app's **Configuration Help** dialog is a developer-oriented diagnostic. It does not change the API address or repair a misconfigured distributed build.

## 3. Login and account access

### Sign in

1. Open Nivora.
2. In **Email or mobile number**, enter the account email address or registered phone number.
3. In **Sign in as**, choose the role assigned to your account.
4. Enter **Password**. Use the eye icon to reveal or hide it while entering it.
5. Leave **Remember me** checked if you want the app to retain the sign-in token on this device. Uncheck it on a shared device if you want to sign in again next time.
6. Tap **Sign in**.

The app requires a non-empty login and a password of at least eight characters before it submits the form. A valid account opens the dashboard appropriate to its role. If the role selection does not match the account, the backend can reject the sign-in even when the password is correct.

### Sign-in errors

- **Invalid credentials / account not found:** check the email or mobile number and password. If still rejected, ask the administrator to confirm that the account exists and is active.
- **Role mismatch:** choose the role the administrator assigned to the account.
- **Inactive staff or security account:** staff and security registrations require an administrator to activate the account before sign-in.
- **API not configured / connection error:** the build cannot reach its configured backend; contact the person who supplied the app or the society administrator.
- **Server validation message:** correct the field indicated by the message. If the message does not make sense, share its text with the administrator without including your password.

### Create an account

The login screen includes **Create an account**. Public registration offers Resident, Society staff, and Security team. It does not offer Administrator accounts.

1. Tap **Create an account** and choose **Account type**.
2. Enter **Full name**, **Email address**, **Mobile number**, **Password**, and **Confirm password**. The app validates an email-like value, a 10-digit Indian mobile number (optionally with `+91`/`91`), a password of at least eight characters, and matching password confirmation.
3. A resident also enters **Flat number**, **Building / block**, and **Relationship to flat** (Owner, Tenant, or Family member). Gender and date of birth are optional; emergency contact is optional.
4. Society staff enter a designation and joining date. Security team members enter an employee ID, shift, and joining date.
5. Tap **Submit registration** and read the confirmation or error message.

Choose the unit name exactly as your society uses it. Contact the administrator if you are unsure which flat/building to select or if the account appears under the wrong unit. Staff and security accounts remain inactive until an administrator activates them. Administrator access must be arranged through the society; it cannot be self-registered in this form.

### Password reset

1. Tap **Forgot password?** on the login screen.
2. Enter the **Account email** linked to Nivora and tap **Send reset link**.
3. Check that email, including its spam folder, and follow the reset instructions if a message arrives.

The app validates that the email contains `@` and asks the backend to send a reset link. Email delivery depends on server mail configuration. The mobile app does not provide a separate reset-token form; if no email arrives or the link is invalid/expired, ask the administrator to check the account and reset process.

### Sign out

Use **More > Sign out** (administrator/security), **More > Log out** (resident), or the logout icon in a generic role workspace. Sign out removes the saved app token and returns to the login screen. On a shared phone, always sign out when finished.

## 4. Understanding the interface

### Navigation by role

| Role | Main navigation | Other modules |
| --- | --- | --- |
| Resident | Bottom tabs: **Home**, **My Unit**, **Gate**, **More** | **More** opens Penalties, Amenities, Bookings, Complaints, Notices, Payments, Parking, Parcels, Messages, Notifications, and Profile. |
| Security | Bottom tabs: **Dashboard**, **Visitors**, **Parcels**, **More** | **More** includes Visitors, Parcels, Penalty reports, Notices, Messages, My profile, and Sign out. The dashboard has visitor/parcel quick actions and checked-out history. |
| Administrator | Bottom tabs: **Dashboard**, **Residents**, **Finance**, **More** | **More** includes Units, Staff, Penalty management, Maintenance, Complaints, Visitors, Parcels, Notices, Parking, Amenities, Reports, Messages, My profile, and Sign out. |
| Society staff | A **Staff workspace** list rather than the three role-specific bottom-tab shells | Dashboard, Profile, Complaints, Parcels, Notices, Messages, and Notifications. |

### Common controls

- **Pull down** on a scrollable list or dashboard to reload its data. Some screens also have a refresh icon or a **Retry** button when loading fails.
- Tap a list card to open its details. Available actions depend on your role and the record's current status.
- A **+** button or a labeled add action opens a form only where creation is enabled for that role.
- Required fields must be completed. Dropdowns show the available choices; date and time fields open pickers. Error text appears on the form or as a message after the server rejects a change.
- Status labels such as **PENDING**, **APPROVED**, **OVERDUE**, and **COLLECTED** describe the saved record. Read the text label; colors are only a visual aid.
- The notification bell opens the **Notifications** list. A dot/highlight marks unread entries. Opening a notification marks it read; the Notifications screen also has **Mark all as read**.

## 5. Resident guide

### Home dashboard

The **Home** tab shows your name and unit and provides cards such as **PENALTIES**, **MY DUES**, **AT THE GATE**, **HELPDESK**, and **VISITORS TODAY**. The values summarize data returned by the backend; tap a card to open that area. Under **Quick actions**, use **Add visitor**, **Pay dues**, **Book amenity**, or **Helpdesk**. The dashboard can also show an upcoming booking and **Announcements**; tap **View all** to open notices. Pull down to refresh.

### Unit and profile

Open **My Unit** to view the name/email, flat and building, assigned parking slot(s), and unit-service links. **Maintenance dues** opens **My Dues**. **Resident profile** opens the profile module. The edit icon opens the account profile.

In **My profile**, you can update the account information shown in the form, including name, email, phone, emergency contact, optional profile details, and an optional new password with confirmation. Tap **Save profile**. If the app reports a validation error, correct the field and save again. Keep your contact information current so the society can reach you.

### Visitors and gate approvals

Open **Gate** to see visitor records for your unit. A pending gate request can show **Approve** and **Reject**. Use these only after checking the visitor and purpose with the person at the gate. The decision is sent to the server and appears in the visitor status/notifications.

To create an expected visitor in advance:

1. Open **Gate** and tap **Add visitor** (or Home > **Add visitor**).
2. On **Pre-approve visitor**, enter **Visitor name** and choose **Visitor type**: Guest, Delivery, Cab / taxi, Service provider, or Other.
3. Tap the expected date/time control and select when the visitor should arrive. It defaults to about one hour from the current time.
4. Tap **Pre-approve visitor** and wait for the result.

The pre-approval form records the visitor name, type, and expected time; it does not ask for a phone number or vehicle number. If the details change, coordinate with security and society management. A resident can approve or reject pending gate requests from the list or from a visitor notification's **View Request** action. A request that is already pre-approved may not show those pending approval buttons.

### Dues, invoices, and payment

Open **My Dues** from **My Unit**, Home > **Pay dues**, or **More > Payments**.

- **Open Invoices** shows bills with an outstanding amount. Tap a bill or **View Invoice** to inspect its details. **Pay full amount** starts checkout for that bill.
- Select multiple invoice checkboxes to use **Pay Now** for the selected outstanding bills.
- In **Review payment** / **Pay all outstanding dues**, check the amount breakdown, choose one of the payment methods displayed, and tap the pay button. The payable amount is calculated by the backend from outstanding bills. Complete any provider checkout shown and wait for Nivora's payment verification result. Do not assume payment succeeded just because checkout opened or the payment app returned; look for the in-app success confirmation and updated bill status/receipt.
- If checkout is cancelled or fails, the app shows a message and the bill should remain outstanding until a verified payment is recorded. Retry later or contact the administrator if money was debited but Nivora still shows an unpaid bill.
- **History** shows invoice history. Open a bill for its invoice; use the ledger link to see debit/credit entries and running balance.
- **Advance** shows the account's advance balance when present.
- The history icon opens **Ledger History**. Use **All**, **Debit**, or **Credit** to filter and **Export PDF** to share a PDF ledger.
- The receipt icon opens **Payment activity**, where you can view payment orders and status. Open an order to inspect its detail and any available receipt.

**Submit payment** is also available as a form in **More > Payments** where the app offers the add action. It records payment details such as bill, amount, method, reference, and receipt reference for administrative review. It is not a confirmation that an offline transfer cleared. Wait until the payment/bill status is updated or a receipt is issued; ask the administrator to review a pending submission.

Razorpay checkout requires a working server configuration. Live provider availability was not verified for this guide. If checkout reports that the gateway is unavailable, use the society's official payment process and ask the administrator for guidance; never send card/UPI credentials to society staff.

### Complaints and helpdesk

Open Home > **Helpdesk** or **More > Complaints**. Tap **+** to open **New complaint**. Choose a category, enter a short title and description, choose a priority, and submit. Categories include Plumbing, Electricity, Security, Cleaning, Lift, Parking, Water, Noise, Maintenance, and Other; priorities include Low, Medium, High, and Emergency.

Your complaint appears in the list with its status. Tap it to see details and available actions. Administrators can assign staff and update progress; assigned staff can update their complaint status and add a note. Statuses used by the app include Open, Assigned, In progress, Resolved, Closed, and Reopened. Status changes depend on the current state and your role. If a status cannot be changed, contact society management rather than submitting a duplicate complaint.

### Amenities and bookings

Open Home > **Book amenity** or **More > Amenities**. The app lists the available amenities; tap **Book** on an amenity. On **Book amenity**, choose the date, start and end time, and optionally add notes. The start time must be before the end time. Review the **Confirm Amenity Booking?** dialog and tap **Confirm Booking** to send it. A request can be rejected if the amenity is inactive or the time conflicts with another booking. The amenity list does not guarantee a slot until the booking is saved and its status is visible. The app does not display a live availability calendar; confirm facility hours with the administrator.

Use **More > Bookings** to see your booking records. Tap a booking for details; the detail toolbar may offer **Cancel booking** while cancellation is allowed. The app does not show an interactive calendar of available time slots; check the returned status and coordinate with the administrator if a booking remains pending.

### Notices and notifications

Open **More > Notices** or use **Announcements > View all** on Home. Tap a notice to read it. The list contains notices available to your account and audience. New or scheduled notices may not appear until they are published and within their dates.

Open the bell or **More > Notifications** to view individual alerts. Tap an item (or **View Request** for a visitor request) to read it; unread entries are marked read when opened. On the Notifications page, tap the check-all icon labeled **Mark all as read** to clear all unread indicators. Push alerts depend on device permission and Firebase setup; if you do not receive a push, open the in-app notification list to check for updates.

### Parcels, parking, and messaging

- **Parcels:** Open **More > Parcels** to see parcel records associated with your unit. A parcel card shows the courier, type, unit, recipient, tracking number when recorded, received time, and pickup status. The app does not expose a resident-side collection confirmation button; coordinate pickup with the gate/staff and check the record again.
- **Parking:** Open **More > Parking** or **My Unit**. My Unit shows the parking slot assigned to your unit when one exists. If no slot appears, the app says no slot is assigned; ask the administrator to confirm the assignment.
- **Messages:** Open **More > Messages** and select a conversation already listed to read and send messages in it. The current mobile UI has no verified action to start a new conversation. Messaging is API-backed; do not expect live updates or chat push delivery.

### Penalties, appeals, and penalty payments

Open the **PENALTIES** dashboard card or **More > Penalties**. Residents can view reports assigned to their record, read the decision/status, and open a penalty for available actions.

- To dispute an eligible penalty, open it and use **Appeal penalty**. Enter the reason and submit. The app may allow supporting evidence where the form provides the attachment option. The appeal then appears as submitted/under review; an administrator decides it.
- If the penalty is approved and unpaid, use **Pay securely** to start payment. Wait for the verified payment result and updated status. A penalty payment is unavailable when the gateway is not configured.
- A paid penalty cannot be waived or adjusted through the current appeal flow; contact the administrator if you believe a paid amount needs correction.

Penalty values are decided by an administrator. The app's configured penalty-rule limits are not currently used to calculate the amount automatically. If a charge or report looks wrong, use the appeal flow and provide a clear explanation.

## 6. Security team guide

### Dashboard and visitor counts

The **Dashboard** summarizes expected visitors, requests awaiting approval, visitors checked in/out today, parcels awaiting pickup, and **Gate Status**. These counts are backend data; pull down to refresh.

### Register a gate visitor

Use **Quick actions > Vehicle entry** when recording an unplanned arrival, or open **Visitors** and use the add action. Despite the label **Vehicle entry**, the current form creates a gate visitor record; it asks for visitor name, flat, resident, and visitor type. It does not provide a separate vehicle log or a vehicle-number field in that form.

1. Choose the destination **Flat** and **Resident** from the available options.
2. Enter the visitor name and choose the type (Guest, Delivery, Cab / taxi, Service provider, or Other).
3. Submit the form. If the person requires resident approval, the resident can receive an in-app/push request. Follow your society's entry policy while approval is pending.

The security visitor record form does not ask for purpose, phone, or vehicle number. Do not invent those details in another field; use your society's approved gate procedure for information the app does not capture.

### Check a visitor in

1. Tap **Check in visitor** on the dashboard.
2. In **Check In Visitor**, review **Eligible Visitors**. Only approved visitors awaiting entry are listed.
3. Use **Search visitor...** to filter the list by visitor name, type, flat/building, or vehicle information when present. Pull down or tap **Refresh** if the list is stale.
4. Tap the correct visitor and check the details in **Check In Confirmation** (visitor, destination, phone/purpose/vehicle/expected time when present).
5. Tap **Check In** only after confirming the person and destination. The visitor moves out of the eligible list and the dashboard refreshes.

If the visitor is not listed, refresh and confirm that a resident has approved the request. Do not use another resident's record as a substitute.

### Check a visitor out and see history

1. Tap **Check out visitor** on the dashboard.
2. In **Currently Inside**, search for the visitor and verify the destination and entry time.
3. Tap the visitor, review **Check Out Confirmation**, and tap **Check Out**.
4. To review completed visits, tap the dashboard's **Checked Out** metric card. Search by visitor, type, unit/building, or vehicle when information was captured. Pull down to refresh.

The app prevents a second check-in/check-out for a record whose state no longer permits that action. If an entry is incorrect, contact the administrator rather than trying to create duplicate records.

### Record parcels

Tap **Record parcel** on the dashboard or open the **Parcels** tab and use the add button. In **Receive parcel**, select a flat and resident, enter the courier name, choose parcel type (Document, Box, Food, Other), and optionally enter tracking number and notes. Submit the form; the resident can then see the parcel as awaiting pickup/ready for pickup.

When the recipient collects it, open the parcel record and use the **Mark collected** action if it is available to your role. Check that its status changes to **COLLECTED**. Avoid marking it collected before handover.

### Penalty reports, notices, and account

Open **More > Penalty reports** to review your submitted reports. Use the **+** action to open **Report violation**, select a category and matching violation type, choose the affected flat when known, add incident location and description, set the incident date/time, and attach evidence photos when appropriate. For financial or parking reports, the form may show a related bill or parking-slot selector. Tap **Submit** and check that the report appears in the list. The app permits up to five image attachments; unsupported or oversized files are rejected by the server.

Security accounts can submit reports and view submissions. They do not decide penalty amounts or approve penalties; that is an administrator action. Use **More > Notices** to read announcements, **Messages** to open listed conversations, **My profile** to update account details, and **Sign out** when ending a shared-device session.

### Emergency alert is not a verified dispatch

The dashboard currently displays an **Emergency alert** control and an **Send Alert** confirmation. In the inspected app code, confirming it only displays a local “Emergency alert broadcasted.” message; it does not send an alert request to the backend. Do not rely on this control to notify anyone. Use your society's established emergency phone/radio procedure.

## 7. Society staff guide

Staff sign in by choosing **Society staff**. A staff account created from the registration form must first be activated by an administrator. The **Staff workspace** is a list rather than a bottom-tab dashboard.

- **Dashboard:** view the staff dashboard/assigned work summary where returned by the backend.
- **Complaints:** open a complaint assigned to you, review its description/history, and use the edit action to update an allowed status or add a note. Staff do not create resident complaints or assign them to other staff through this screen.
- **Parcels:** use the add action to record a delivery for the selected unit/resident. Open a parcel and use **Mark collected** only after pickup.
- **Notices:** open and read published society notices.
- **Messages:** open a listed conversation and send a message. Starting a new conversation from the current UI is not available/verified.
- **Profile / Notifications:** review your profile and in-app notifications. Sign out when finished on a shared phone.

If an assigned complaint is missing or a record is outside your access, ask an administrator to check your staff account and assignment.

## 8. Administrator guide

### Dashboard and reports

The **Dashboard** shows society metrics such as residents, units, occupancy, bills/collection, open complaints, visitors today, active staff, and parcels waiting. Use its quick actions:

- **Add resident** opens the Residents area.
- **Add unit** opens the Flats/Units area.
- **Maintenance** opens bills.
- **Record payment** opens Finance.
- **Add notice** opens Notices.
- **View reports** opens Society reports.
- **Review penalties** opens penalty management.

Tap metric cards to move into related lists where supported. Pull down to refresh. Under **More > Reports**, choose **Today**, **This week**, **This month**, **Last month**, **This year**, or **Custom date range**. For a custom range, select both dates and review the maintenance, operations, capacity, and collection summaries shown. Report values are based on server records and the chosen range.

### Residents, units, and staff

- **More > Residents** or the **Residents** tab lists residents. Use **+** to open **Resident** and enter name, email, optional phone/password, flat, and relationship. Tap a record to inspect it; edit and delete actions appear where available. Deleting a record is irreversible in the UI and asks for confirmation.
- **More > Units** opens the Flats list. Use **+** and choose **Flat** to enter flat number, building, optional floor/owner, and occupancy status. Check the selected owner and unit before saving so residents are associated with the correct unit.
- **More > Staff** opens staff records. Use **+** to add a staff member record with name, designation, joining date, and any optional employee ID/contact/shift/status fields. This form does not set a login password. A staff/security user registers through **Create an account**; open their staff record to activate or deactivate the account after the confirmation prompt. Activation controls whether registered staff/security accounts can sign in.

Public registration does not create administrator accounts. Use the admin-controlled staff/resident management and account provisioning process used by your society.

### Maintenance bills and payment review

Open **More > Maintenance**. Tap **+** to create a **Maintenance bill** for a selected flat and billing month. Enter the due date and base maintenance; period start/end, water, common electricity, parking, other charges, late fee, discount, and notes are available as additional fields. Review the selected unit, billing month, and amounts before saving. The screen's **Generate Monthly Invoices** app-bar action calls the backend generator; confirm the intended billing run with your society before using it. Pull down to reload the bill list.

Use **Finance** to inspect payment activity. Open an item to view its detail. For a manually submitted maintenance payment request, the review screen can **Confirm payment** (requires a receipt/transaction reference) or **Mark payment as failed**. Confirm only after checking the actual payment evidence. A failed request does not change the bill balance; verified gateway payment orders are reconciled through the payment verification flow rather than manually marked paid.

The payment gateway may be unavailable if server credentials/provider configuration are missing. The app does not establish that a live transaction is possible; test the society's payment process before announcing it to residents.

### Visitors and parcels

Open **More > Visitors** to review visitor records. The current administrator list is for viewing/details; the dedicated check-in and check-out workflow is available to Security. Coordinate corrections with the responsible security user rather than assuming administrator visitor records have gate action buttons.

Open **More > Parcels** to record parcels or review records. Use **Receive parcel** with a flat, resident, courier, parcel type, and optional tracking/notes. Open a parcel and use **Mark collected** only after handover. Verify the status after saving.

### Complaints

Open **More > Complaints** and tap a complaint. Use the edit action to assign a staff member and select an available status (Open, Assigned, In progress, Resolved, Closed, Reopened); add a note to record context. Save and confirm the updated status. The resident and assigned staff see the record within their access. If the app refuses a transition, follow the server's displayed message and review the current complaint status.

### Notices

Open **More > Notices**, then tap **+** to open **Create notice**. Enter title and content, select category, priority, and audience, then choose **Publish now** or **Save as draft**. Optional publication and expiry dates control when a notice is visible. Confirm the audience carefully: notices can be society-wide, for residents, owners, or staff. Only published, in-date notices are shown to eligible readers. The app's notice list has no verified edit/delete controls after creation, so check the wording, audience, and dates before saving.

### Parking and amenities

- **Parking:** open **More > Parking** and use **+** to add a slot. Enter slot number, type (Car, Bike, Visitor, Other), and optionally associate a flat and vehicle number. Open a record to inspect or edit it if the action is available. Confirm unit and slot assignment to avoid incorrect resident information.
- **Amenities:** open **More > Amenities** and use **+** to add an amenity with name, optional description/opening and closing times, maximum booking hours, and active state. Residents can view active amenities and request bookings. The booking flow checks conflicts, but the mobile client does not present a live slot calendar; verify bookings/statuses in **Bookings**.
- **Bookings:** open **More > Bookings** to inspect booking records. Open a record to review it; available detail actions depend on status and backend authorization. Avoid assuming a request is confirmed until its saved status says so.

### Penalty management

Open **More > Penalty management** or tap **Review penalties** on the dashboard. The main screen shows reports and summary cards; use its status/category/search filters to narrow the list. Tap a report to review its evidence and context. Available decisions include moving a report under review, issuing a warning, approving, or rejecting. A decision form requires a reason; approving also requires a positive disciplinary amount and a responsible resident linked to the affected flat. Add repair cost only when supported by evidence. Review all values before saving because the decision can notify the resident and create a penalty.

Use the sliders/settings icon (**Rules and appeals**) to open **Penalty rules and appeals**:

- In the rules area, use **Add rule** or edit an existing rule. Configure its category/type, amount bounds, late-fee/grace values, evidence requirement, and active state. Active state controls whether a rule is offered in rule lists.
- In appeals, open an appeal and use **Decide appeal** to record a reason and outcome. Waiving or adjusting a penalty already paid is blocked because no refund workflow exists.

Important: current code stores rule settings but does not use the rule bounds, grace values, or evidence flag to calculate/enforce the amount during a report decision. The administrator-entered amount is what is applied. Do not tell residents that the configured rules automatically calculate their penalty. Review evidence and applicable society policy before deciding.

### Messages, notifications, and profile

Open **More > Messages** to view existing conversations and send messages within one. The current mobile screen does not show a create-conversation action, and messages do not have a configured real-time transport; refresh the thread to check for updates.

Use the notification bell or **Notifications** to read system alerts and **Mark all as read** to clear unread indicators. Push delivery depends on Firebase setup and device permission. Open **My profile** to update your own account information, and use **Sign out** at the end of a shared-device session.

## 9. Feature status and limitations

| Feature | User-facing status |
| --- | --- |
| Login, registration, profile, reset-link request | Available in the mobile UI; registration roles and activation requirements are described above. Email reset delivery depends on server mail setup. |
| Visitors, resident approval, check-in/out, history | Available through resident and security screens; entry is restricted to approved visitors in the dedicated check-in list. |
| Bills, receipts/history, payment checkout | Screens and flows are implemented. Live Razorpay availability and production payment configuration were not verified. |
| Parcels, complaints, notices, parking, amenities/bookings | Available according to the role-specific screens and backend access. A saved status is the source for whether an action completed. |
| Penalty reports, admin decisions, resident appeals/payment | Screens and workflows are present. Rule-based automatic amount calculation is not implemented. |
| Messages | Existing conversation viewing and message sending are present. Starting a conversation and real-time delivery are not available/verified in the current mobile UI. |
| Firebase push notifications | Integration exists, but delivery requires correct client/server configuration and notification permission. |
| Security Emergency alert | The visible action currently only shows a local success message; it does not send a backend alert. Do not rely on it for emergencies. |
| Vehicle entry | The visible shortcut opens the gate visitor form; it is not a separate vehicle movement log and that form has no vehicle-number field. |
| App download/distribution | No official store listing or verified public APK distribution was found. Get the approved build from the society administrator. |

## 10. Common issues

| What you see | What to do |
| --- | --- |
| **No upcoming visitors** | This is an empty state. Use **Add visitor** to pre-approve an expected visitor, or ask the gate to submit a request. |
| **No visitors are currently eligible for check-in** | Pull down or tap **Refresh**. Only approved visitors awaiting entry appear. Confirm resident approval and destination. |
| **No parking slot is assigned to your unit** | Ask the administrator to confirm that your flat and parking assignment are correct. |
| **No new notifications** | Refresh and check the notification permission/internet connection. Push delivery may be unavailable even when in-app alerts are stored. |
| **Could not load / Retry** | Confirm network, retry, and contact the administrator if it continues. Include the page and exact error text. |
| **Payment cancelled / failed / verification failed** | Check **My Dues** and **Payment activity** before trying again. If money was debited but the bill is unpaid, keep the provider reference and contact the administrator; avoid repeated attempts until reviewed. |
| **Amenity booking conflict or rejected request** | Choose another date/time or contact management. A booking is not guaranteed until the app shows its saved status. |
| **Staff/security cannot sign in after registration** | Ask an administrator to activate the account and verify the selected login role. |
| **A menu or action is missing** | The app hides actions by role or record state. Ask the administrator to confirm your role and whether the record is eligible for that action. |

## 11. Privacy and safe use

- Keep your password private. Do not share a password, reset link, payment PIN, or banking/UPI credentials with another user.
- Sign out on shared devices. Use **Remember me** only on a device you control.
- Verify visitor identity and destination before approving or recording gate entry. Never approve a request just to clear a notification.
- Confirm the unit, amount, audience, and status before saving administrative changes.
- Contact your society's established emergency channel for urgent safety events; the app's current emergency-alert button is not a dispatch service.
- Report suspicious access, incorrect resident/unit records, or payment discrepancies to the society administrator.

## 12. Related documentation

- [Project overview and local setup](../README.md)
- [Architecture and workflows](WORKFLOWS.md)
- [API reference](API_REFERENCE.md) (for administrators/integrators)
- [Data model and business rules](DATA_MODEL.md) (technical reference)
- [Deployment, testing, and security](DEPLOYMENT_TESTING_SECURITY.md) (technical reference)
