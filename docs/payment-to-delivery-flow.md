# Payment to Delivery Process Flow

This document describes the complete flow from payment initiation to final document delivery in the Retaining Wall Design application.

---

## Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Payment Page  │───▶│  Stripe Process │───▶│ Design Submit   │───▶│  Delivery Page  │
│   /payment      │    │  (Payment Sheet)│    │  (C++ Backend)  │    │  /delivery/:id  │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## Detailed Process Flow

### Step 1: Payment Page (`/payment`)

**File:** `lib/features/payment/presentation/pages/payment_page.dart`

The user arrives at the payment page with their wall design parameters already configured. The page displays:

1. **Order Summary Card**
   - Wall height and material specifications
   - Price tier description (Small/Medium/Large wall)
   - Total price based on wall height:
     - Under 4 ft: $49.99
     - 4-8 ft: $99.99
     - Over 8 ft: $149.99

2. **Payment Form Widget**
   - Stripe payment integration
   - Customer email and name from wall input state
   - Metadata including wall specifications

---

### Step 2: Stripe Payment Processing

**Files:**
- `lib/features/payment/providers/payment_provider.dart`
- `lib/core/services/stripe_service.dart`

#### 2.1 Payment Initiation

When user clicks "Pay", the `PaymentNotifier.processPayment()` method is called:

```dart
await ref.read(paymentProvider.notifier).processPayment(
  amount: wallState.price,
  email: wallState.input.customerInfo.email,
  customerName: wallState.input.customerInfo.name,
  metadata: {
    'wall_height': wallState.input.height.toString(),
    'material': wallState.input.materialLabel,
  },
);
```

#### 2.2 Payment Status Flow

```
PaymentStatus.pending
       │
       ▼
PaymentStatus.processing  ──────────────────┐
       │                                     │
       ▼                                     ▼
PaymentStatus.completed            PaymentStatus.failed
       │                                     │
       ▼                                     ▼
  (Continue to Step 3)             (Show error, allow retry)
```

#### 2.3 Backend Payment Intent Creation

**Endpoint:** `POST /api/v1/create-payment-intent`

The Stripe service calls the backend to create a payment intent:

```json
{
  "amount": 9999,
  "currency": "usd",
  "email": "customer@example.com",
  "metadata": {
    "wall_height": "96",
    "material": "Concrete"
  }
}
```

**Response:**
```json
{
  "clientSecret": "pi_xxx_secret_xxx",
  "paymentIntentId": "pi_xxx",
  "amount": 9999,
  "currency": "usd"
}
```

#### 2.4 Platform-Specific Payment UI

| Platform | Method | UI |
|----------|--------|-----|
| **Web** | `CardField` + `confirmPayment()` | Custom card input form |
| **Mobile (iOS/Android)** | Payment Sheet | Native Stripe UI with Apple/Google Pay |
| **Desktop (macOS/Windows/Linux)** | Demo mode | Simulated payment for testing |

#### 2.5 3D Secure Authentication (if required)

If the payment requires additional authentication:
1. `PaymentIntentsStatus.RequiresAction` is returned
2. `Stripe.instance.handleNextAction()` is called
3. User completes 3D Secure challenge
4. Payment status updated to `Succeeded` or `Failed`

---

### Step 3: Design Submission to Backend

**File:** `lib/features/wall_input/providers/wall_input_provider.dart`

After successful payment, the design is submitted to the C++ backend server.

#### 3.1 Trigger

The `onPaymentSuccess` callback in `PaymentFormWidget` triggers:

```dart
onPaymentSuccess: () async {
  await _submitDesignAndNavigate(context, ref);
}
```

#### 3.2 Design Submission

**Method:** `WallInputNotifier.submitDesign()`

```dart
Future<bool> submitDesign() async {
  // 1. Validate input
  if (!validate()) return false;

  // 2. Set submitting state
  state = state.copyWith(isSubmitting: true);

  // 3. Call API
  final response = await _apiClient.submitDesign(state.input.toJson());

  // 4. Update state with response
  state = state.copyWith(
    isSubmitting: false,
    lastResponse: response,
  );

  return response.success;
}
```

#### 3.3 API Call Details

**Endpoint:** `POST /api/v1/design`

**Request Body:**
```json
{
  "height": 96,
  "material": 0,
  "surcharge": 0,
  "optimization_parameter": 0,
  "soil_stiffness": 0,
  "topping": 2,
  "has_slab": false,
  "toe": 12,
  "site_address": {
    "street": "123 Main St",
    "City": "Springfield",
    "State": "IL",
    "Zip Code": 62701
  },
  "customer_info": {
    "name": "John Doe",
    "email": "john@example.com",
    "phone": "555-1234",
    "mailing_address": { ... }
  }
}
```

**Response:**
```json
{
  "success": true,
  "request_id": "req_abc123xyz",
  "wall_specifications": { ... },
  "files": {
    "preview_pdf": "/files/req_abc123xyz/PreviewDrawing.pdf",
    "detailed_pdf": "/files/req_abc123xyz/DetailedDrawing.pdf"
  }
}
```

#### 3.4 Backend Processing (C++ Server)

The C++ `rwcpp` server:
1. Receives JSON input with wall parameters
2. Performs engineering calculations
3. Generates PDF drawings (Preview and Detailed)
4. Stores files and returns URLs

---

### Step 4: Navigation to Delivery Page

After successful design submission:

```dart
if (designSuccess && context.mounted) {
  final response = ref.read(wallInputProvider).lastResponse;
  if (response != null && response.success) {
    context.goToDelivery(response.requestId);
  }
}
```

**Route:** `/delivery/:requestId`

---

### Step 5: Delivery Page (`/delivery/:requestId`)

**Files:**
- `lib/features/delivery/presentation/pages/delivery_page.dart`
- `lib/features/delivery/providers/delivery_provider.dart`

#### 5.1 Page Initialization

On page load, the delivery provider is initialized with the request ID:

```dart
ref.read(deliveryProvider.notifier).setRequestId(widget.requestId);
```

This generates the file URLs:
- Preview: `{baseUrl}/files/{requestId}/PreviewDrawing.pdf`
- Detailed: `{baseUrl}/files/{requestId}/DetailedDrawing.pdf`

#### 5.2 Page Sections

1. **Success Header**
   - Celebration message
   - Order ID display

2. **Documents Section**
   - Preview Drawing download (~500 KB)
   - Detailed Construction Drawing download (~1.5 MB)
   - Download status indicators

3. **Email Delivery Section**
   - Pre-filled with customer email
   - Option to send documents via email

4. **What's Next Section**
   - Guidance for next steps:
     1. Review drawings
     2. Consult a professional
     3. Obtain permits
     4. Begin construction

#### 5.3 Document Download

Downloads are handled via `url_launcher`:

```dart
Future<void> _downloadFile(url, filename) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    notifier.markPreviewDownloaded(); // or markDetailedDownloaded()
  }
}
```

#### 5.4 Email Delivery

Sends documents to customer's email:

```dart
Future<bool> sendEmail(String emailAddress) async {
  state = state.copyWith(status: DeliveryStatus.sendingEmail);
  // Backend call to send email with PDF attachments
  state = state.copyWith(emailSent: true, status: DeliveryStatus.completed);
  return true;
}
```

---

## State Management

### Payment State (`PaymentState`)

| Field | Type | Description |
|-------|------|-------------|
| `status` | `PaymentStatus` | Current payment status |
| `amount` | `double` | Payment amount in dollars |
| `paymentIntentId` | `String?` | Stripe payment intent ID |
| `clientSecret` | `String?` | Client secret for payment |
| `transactionId` | `String?` | Transaction ID after success |
| `errorMessage` | `String?` | Error message if failed |

### Delivery State (`DeliveryState`)

| Field | Type | Description |
|-------|------|-------------|
| `status` | `DeliveryStatus` | Current delivery status |
| `requestId` | `String?` | Design request ID |
| `previewPdfUrl` | `String?` | URL for preview PDF |
| `detailedPdfUrl` | `String?` | URL for detailed PDF |
| `previewDownloaded` | `bool` | Preview download status |
| `detailedDownloaded` | `bool` | Detailed download status |
| `emailSent` | `bool` | Email delivery status |

---

## Error Handling

### Payment Errors

| Error | Handling |
|-------|----------|
| Card declined | Show error message, allow retry |
| Network error | Show error, maintain state for retry |
| 3D Secure failed | Return to payment form |
| Invalid card | Real-time validation feedback |

### Design Submission Errors

| Error | Handling |
|-------|----------|
| Server unavailable | Show error, allow retry |
| Invalid parameters | Validation before submission |
| Timeout | Show error with retry option |

### Delivery Errors

| Error | Handling |
|-------|----------|
| Download failed | Show error, provide copy link option |
| Email send failed | Show error, allow retry |

---

## Sequence Diagram

```
User            Flutter App       Stripe API       C++ Backend
 │                   │                │                 │
 │  Click Pay        │                │                 │
 ├──────────────────▶│                │                 │
 │                   │ Create Intent  │                 │
 │                   ├───────────────▶│                 │
 │                   │                ├────────────────▶│
 │                   │                │  (Create PI)    │
 │                   │                │◀────────────────┤
 │                   │◀───────────────┤                 │
 │  Payment Sheet    │                │                 │
 │◀──────────────────┤                │                 │
 │                   │                │                 │
 │  Enter Card       │                │                 │
 ├──────────────────▶│                │                 │
 │                   │ Confirm Payment│                 │
 │                   ├───────────────▶│                 │
 │                   │◀───────────────┤                 │
 │                   │                │                 │
 │                   │ Submit Design  │                 │
 │                   ├────────────────┼────────────────▶│
 │                   │                │   (Generate PDF)│
 │                   │◀───────────────┼─────────────────┤
 │                   │                │                 │
 │  Navigate to      │                │                 │
 │  Delivery Page    │                │                 │
 │◀──────────────────┤                │                 │
 │                   │                │                 │
 │  Download PDF     │                │                 │
 ├──────────────────▶│                │                 │
 │                   │  GET /files    │                 │
 │                   ├────────────────┼────────────────▶│
 │                   │◀───────────────┼─────────────────┤
 │◀──────────────────┤                │                 │
 │                   │                │                 │
```

---

## Key Files Reference

| Component | File Path |
|-----------|-----------|
| Payment Page | `lib/features/payment/presentation/pages/payment_page.dart` |
| Payment Provider | `lib/features/payment/providers/payment_provider.dart` |
| Stripe Service | `lib/core/services/stripe_service.dart` |
| Wall Input Provider | `lib/features/wall_input/providers/wall_input_provider.dart` |
| API Client | `lib/core/api/api_client.dart` |
| Delivery Page | `lib/features/delivery/presentation/pages/delivery_page.dart` |
| Delivery Provider | `lib/features/delivery/providers/delivery_provider.dart` |
| Router | `lib/app/router.dart` |
| Constants | `lib/core/constants/app_constants.dart` |
