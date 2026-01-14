# Retaining Wall Designer - User Manual

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [Step-by-Step Guide](#step-by-step-guide)
   - [Step 1: Landing Page](#step-1-landing-page)
   - [Step 2: Wall Parameters](#step-2-wall-parameters)
   - [Step 3: Customer Information](#step-3-customer-information)
   - [Step 4: Payment](#step-4-payment)
   - [Step 5: Document Delivery](#step-5-document-delivery)
4. [Wall Parameters Reference](#wall-parameters-reference)
5. [Pricing](#pricing)
6. [Technical Process](#technical-process)
7. [Troubleshooting](#troubleshooting)

---

## Introduction

The Retaining Wall Designer is a web application that generates professional engineering drawings for retaining wall construction projects. Users input wall specifications, pay securely via Stripe, and receive detailed PDF documents ready for construction.

### What You'll Receive

- **Preview Drawing** - A quick overview of your wall design with key dimensions
- **Detailed Construction Drawing** - Complete specifications, calculations, rebar placement, and construction details

---

## Getting Started

### System Requirements

- Modern web browser (Chrome, Firefox, Safari, or Edge)
- Internet connection
- Valid email address for document delivery
- Credit/debit card or digital wallet (Apple Pay, Google Pay) for payment

### Accessing the Application

Navigate to the application URL in your web browser. You'll be greeted by the landing page with information about the service and pricing.

---

## Step-by-Step Guide

### Step 1: Landing Page

**URL:** `/`

The landing page provides an overview of the service:

- **Hero Section** - Introduction to professional retaining wall designs
- **Features Section** - Key benefits including engineering drawings, fast turnaround, customizable parameters, and transparent pricing
- **Pricing Section** - Three pricing tiers based on wall height
- **How It Works** - Four-step process overview

**Action:** Click "Start Your Design" or "Start Design" button to begin.

**What happens behind the scenes:**
- The application initializes state management
- Route changes to `/design`

---

### Step 2: Wall Parameters

**URL:** `/design`

This is the main design page with a split layout:
- **Left side (Desktop):** Real-time wall preview that updates as you change parameters
- **Right side:** Wizard steps for data input

#### Wall Specifications

| Parameter | Description | Options/Range |
|-----------|-------------|---------------|
| **Height** | Total wall height | 24" - 144" (2 ft - 12 ft) |
| **Material** | Wall construction material | Concrete or CMU (Concrete Masonry Unit) |
| **Surcharge** | Slope condition above the wall | Flat, 1:1 slope (45°), 1:2 slope, 1:4 slope |
| **Optimization** | Design priority | Minimize Excavation or Minimize Footing |
| **Soil Stiffness** | Ground condition | Stiff Soil or Soft Soil |
| **Topping** | Topsoil thickness | 0" - 24" |
| **Has Slab** | Adjacent slab present | Yes/No |
| **Toe Length** | Footing toe dimension | 0" - 120" |

#### Site Address

Enter the location where the wall will be built:
- Street address
- City
- State (2-letter abbreviation)
- ZIP Code

**Validation Requirements:**
- All address fields must be filled
- Height must be within 24-144 inches
- Toe must be within 0-120 inches
- Topping must be within 0-24 inches

**What happens behind the scenes:**
- Wall preview updates in real-time using Canvas rendering
- Input validation runs continuously
- Price calculates automatically based on height

**Action:** Click "Continue" to proceed to customer information.

---

### Step 3: Customer Information

**URL:** `/design` (Wizard Step 2)

Enter your contact information for document delivery and records.

| Field | Description | Requirements |
|-------|-------------|--------------|
| **Name** | Your full name | Required |
| **Email** | Email address | Required, valid format |
| **Phone** | Contact number | Required |

**Validation Requirements:**
- Name cannot be empty
- Email must be valid format (e.g., `name@domain.com`)
- Phone number cannot be empty

**What happens behind the scenes:**
- Customer info is stored in application state
- Email validation uses regex pattern matching

**Action:** Click "Proceed to Payment" to continue.

---

### Step 4: Payment

**URL:** `/design` (Wizard Step 3) or `/payment`

This step displays an order summary and payment options.

#### Order Summary

Review your design details:
- Wall height (inches and feet)
- Selected material
- Site conditions
- Site address
- Customer information
- Pricing tier and total

#### Payment Methods

**Quick Pay (Stripe Payment Sheet)**
- Opens Stripe's secure payment interface
- Supports: Visa, Mastercard, Amex, Apple Pay, Google Pay
- Recommended for fastest checkout

**Manual Card Entry**
- Enter card details directly in the form
- Card number (with real-time brand detection)
- Expiry date (MM/YY)
- CVC
- Cardholder name

**Demo Payment**
- For testing purposes only
- Bypasses actual payment processing

**What happens behind the scenes:**

1. **Payment Intent Creation:**
   - Frontend sends amount to backend: `POST /api/v1/create-payment-intent`
   - Backend calls Stripe API with secret key
   - Stripe returns `clientSecret`
   - Backend returns `clientSecret` to frontend

2. **Payment Confirmation:**
   - Frontend uses Stripe.js with `clientSecret`
   - User completes payment in Stripe interface
   - Stripe processes payment and confirms

3. **Design Submission:**
   - After successful payment, frontend sends wall parameters: `POST /api/v1/design`
   - Backend calculates wall specifications using physics engine
   - Backend generates PDF documents using Cairo graphics
   - Backend returns `requestId` and file URLs

**Action:** Click "Pay $XX.XX" to process payment.

---

### Step 5: Document Delivery

**URL:** `/delivery/:requestId`

After successful payment and design generation, you'll see your documents.

#### Success Confirmation

- Celebration message confirming your design is ready
- Order ID for reference

#### Download Documents

**Preview Drawing (PDF)**
- Quick overview of wall design
- Key dimensions
- Approximate size: ~500 KB

**Detailed Construction Drawing (PDF)**
- Complete specifications
- Structural calculations
- Rebar placement
- Construction details
- Approximate size: ~1.5 MB

**Download Methods:**
1. Click "Download" button to open PDF in browser/download
2. Use "Send to Email" to receive documents via email

#### Email Delivery

- Pre-filled with your email address
- Optionally change to a different email
- Click "Send to Email" to receive documents

#### What's Next Guide

The page provides guidance on next steps:
1. Review your drawings
2. Consult a licensed professional
3. Obtain building permits
4. Begin construction

**What happens behind the scenes:**

1. **File Retrieval:**
   - Frontend requests files: `GET /files/{requestId}/{filename}`
   - Backend serves PDF from output directory
   - Browser downloads or displays the file

2. **Status Check (if needed):**
   - Frontend can check: `GET /api/v1/status/{requestId}`
   - Backend confirms file availability

---

## Wall Parameters Reference

### Height (24" - 144")

The total height of the retaining wall from footing to top.

| Height Range | Pricing Tier |
|--------------|--------------|
| Up to 4 feet (48") | Small Wall |
| 4-8 feet (48"-96") | Medium Wall |
| Over 8 feet (96"+) | Large Wall |

### Material Types

| Value | Material | Description |
|-------|----------|-------------|
| 0 | Concrete | Poured concrete wall |
| 1 | CMU | Concrete Masonry Unit (block) wall |

### Surcharge Types

Describes the slope condition of the ground above the wall.

| Value | Type | Description |
|-------|------|-------------|
| 0 | Flat | Level ground, no slope |
| 1 | 1:1 Slope | 45-degree slope (steepest) |
| 2 | 1:2 Slope | Moderate slope |
| 4 | 1:4 Slope | Gentle slope |

### Optimization Parameters

| Value | Optimization | Description |
|-------|--------------|-------------|
| 0 | Excavation | Minimize digging required |
| 1 | Footing | Minimize footing size |

### Soil Stiffness

| Value | Type | Description |
|-------|------|-------------|
| 0 | Stiff | Firm, stable soil |
| 1 | Soft | Loose, less stable soil |

---

## Pricing

Pricing is based on wall height:

| Tier | Height Range | Price | Includes |
|------|--------------|-------|----------|
| **Small Wall** | Up to 4 feet | $49.99 | Preview + Detailed PDF |
| **Medium Wall** | 4-8 feet | $99.99 | Preview + Detailed PDF, Multi-section design |
| **Large Wall** | Over 8 feet | $149.99 | Preview + Detailed PDF, Multi-section design, Structural calculations |

All tiers include:
- Preview drawing (PDF)
- Detailed construction drawing (PDF)
- Email delivery option
- 24-hour file availability

---

## Technical Process

### System Architecture

```
[Web Browser] <---> [Flutter Web App] <---> [rwcpp Server] <---> [Stripe API]
                                                  |
                                            [PDF Generation]
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Server health check |
| `/api/v1/design` | POST | Submit wall design, generate PDFs |
| `/api/v1/status/{requestId}` | GET | Check design processing status |
| `/api/v1/create-payment-intent` | POST | Create Stripe payment intent |
| `/files/{requestId}/{filename}` | GET | Download generated PDFs |

### Design Submission Request

```json
{
  "height": 72.0,
  "material": 1,
  "surcharge": 0,
  "optimization_parameter": 0,
  "soil_stiffness": 0,
  "topping": 2,
  "has_slab": true,
  "toe": 12,
  "site_address": {
    "street": "123 Main St",
    "City": "Salt Lake City",
    "State": "UT",
    "Zip Code": 84101
  },
  "customer_info": {
    "name": "John Doe",
    "email": "john@example.com",
    "phone": "555-123-4567"
  }
}
```

### Design Response

```json
{
  "success": true,
  "request_id": "20241112_143025_001_4567",
  "timestamp": 1699800625,
  "wall_specifications": {
    "total_height": 72,
    "sections": [
      {"height": 48, "width": 8},
      {"height": 24, "width": 12}
    ],
    "footing": {
      "heel": 36,
      "toe": 60,
      "thickness": 12
    },
    "material": "CMU"
  },
  "files": {
    "preview_pdf": "http://server/files/requestId/PreviewDrawing.pdf",
    "detailed_pdf": "http://server/files/requestId/DetailedDrawing.pdf"
  }
}
```

### Payment Flow

```
1. User clicks "Pay"
2. Frontend: POST /api/v1/create-payment-intent {amount: 9999}
3. Backend: Calls Stripe API with secret key
4. Stripe: Returns payment intent with client_secret
5. Backend: Returns {clientSecret, paymentIntentId} to frontend
6. Frontend: Opens Stripe Payment Sheet with clientSecret
7. User: Completes payment in Stripe interface
8. Stripe: Confirms payment
9. Frontend: Submits design to backend
10. Backend: Generates PDFs, returns requestId
11. Frontend: Navigates to delivery page
```

### File Retention

- Generated PDF files are retained for **24 hours**
- After 24 hours, files are automatically deleted
- Download your files promptly or use email delivery

---

## Troubleshooting

### Common Issues

#### "Invalid email format"
- Ensure email follows format: `name@domain.com`
- Check for extra spaces before or after the email

#### "Height must be between 24 and 144 inches"
- Enter a height value between 2 feet (24") and 12 feet (144")

#### Payment fails
- Check card details are entered correctly
- Ensure sufficient funds
- Try a different payment method
- Contact your bank if issues persist

#### PDFs won't download
- Check your browser's popup blocker settings
- Try right-clicking the download button and selecting "Save Link As"
- Use the email delivery option as an alternative

#### "Request not found" on delivery page
- Files are only available for 24 hours
- Ensure you're using the correct request ID
- Contact support if issue persists

### Browser Compatibility

| Browser | Supported |
|---------|-----------|
| Chrome 90+ | Yes |
| Firefox 88+ | Yes |
| Safari 14+ | Yes |
| Edge 90+ | Yes |
| Internet Explorer | No |

### Contact Support

If you encounter issues not covered here, please contact support with:
- Your Order ID (request ID)
- Description of the issue
- Screenshots if applicable
- Browser and device information

---

## Glossary

| Term | Definition |
|------|------------|
| **CMU** | Concrete Masonry Unit - precast concrete blocks |
| **Footing** | The base foundation of the retaining wall |
| **Heel** | Back portion of the footing (soil side) |
| **Toe** | Front portion of the footing (open side) |
| **Surcharge** | Additional load from sloped ground above the wall |
| **Topping** | Layer of topsoil above the wall |
| **Rebar** | Steel reinforcement bars inside concrete |

---

*Last Updated: December 2024*
*Version: 1.0*
