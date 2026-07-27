# 24. Payments & Monetization

## 1. Overview
The PlaySphere Payments System handles all financial transactions within the platform, primarily focusing on registration fees and season subscriptions. It is designed to be multi-tenant, allowing individual organizations (State, District, Community) to route funds directly to their respective accounts.

## 2. Core Features
- **Registration Fees**: Pay-to-play entry fees for specific sports or seasons.
- **Season Subscriptions**: All-access passes for a specific duration or season.
- **Payment Gateway Integration**: Built primarily with Razorpay for the Indian market, with abstract interfaces to support Stripe for global scaling.
- **Refund Management**: Automated partial or full refunds upon withdrawal before an organization-defined deadline.
- **Receipts**: Auto-generated PDF receipts emailed upon successful payment.

## 3. Financial Precision & Data Storage
- **Amount Representation**: All monetary values are strictly stored as `int` representing the smallest currency unit (e.g., Paise for INR, Cents for USD).
  - Example: ₹100.50 is stored as `10050`.
- **Currency Code**: Iso 4217 code stored per transaction (e.g., "INR").

## 4. Payment Workflows
### Checkout Flow
1. User selects season/sport requiring a fee.
2. Backend generates an internal `OrderEntity` with `status: PENDING`.
3. Gateway order (e.g., Razorpay Order ID) is generated and sent to the Flutter client.
4. Client SDK handles UI and card/UPI details.
5. On success, Gateway calls PlaySphere Webhook.
6. Webhook verifies signature, updates `OrderEntity` to `SUCCESS`, and finalizes `RegistrationEntity`.

### Refund Flow
1. User initiates withdrawal.
2. System checks if `current_time < registration_deadline`.
3. If valid, backend triggers Gateway Refund API.
4. Updates status to `REFUNDED` and alerts user.

## 5. Organization Dashboard
- **Revenue Overview**: Total collected, pending settlements, refunds.
- **Transaction Ledger**: Searchable list of all payments with filters by Season, Sport, and Status.
- **Payout Management**: View settlement status from the gateway to the organization's bank account.

## 6. Data Model
- **PaymentTransactionEntity**:
  - `id`: String (UUID)
  - `orgId`: String
  - `userId`: String
  - `amount`: Integer (in smallest unit)
  - `currency`: String (Default "INR")
  - `status`: Enum (PENDING, SUCCESS, FAILED, REFUNDED)
  - `gatewayOrderId`: String
  - `gatewayPaymentId`: String
  - `metadata`: JSON (Season ID, Sport ID)
  - `createdAt`: Timestamp
