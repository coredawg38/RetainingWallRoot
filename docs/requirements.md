# Software Requirements Document
## Retaining Wall Business Management System

**Version:** 1.0  
**Date:** November 2025  
**Document Status:** Initial Draft

---

## 1. EXECUTIVE SUMMARY

### 1.1 Purpose
This document defines the comprehensive software requirements for operating a retaining wall business, encompassing both the core engineering drawing generation system and the complete business management infrastructure needed to run the operation efficiently.

### 1.2 Business Overview
The retaining wall business provides customers with professionally engineered retaining wall designs that meet local building codes. Customers input their project parameters, receive engineered drawings suitable for building department submission, and can either self-build or hire contractors for construction.

### 1.3 System Scope

1. Wall Generator, that uses the rwcpp projects rest api to generate pdf documents
2. Flutter UI, that calles the wall generator api, and the stripe payment api


## 2. CORE ENGINEERING SYSTEM REQUIREMENTS

### 2.1 Engineering Calculation Engine

#### 2.1.1 Current Implementation
- **Technology Stack:** C++ application
- **Input Format:** JSON configuration files
- **Output Format:** PDF engineering drawings
- **Status:** Functional and operational
- REST API wrapper for web integration

### 2.2 Parameter Input System

#### 2.3.1 User Interface Requirements
- Intuitive web-based form interface
- Real-time validation of inputs
- Visual aids and tooltips for technical terms
- Support for imperial

#### 2.3.2 Required Parameters
- defined in the input json schema

## 3. CUSTOMER-FACING WEB PORTAL

### 3.1 Wall Workflow

Main Screen has 2 sides.

Side 1:
1. Preview updates with parameters

Side 2: (wizard)
1. Input wall parameters
2. Payment (stripe launch) on payment success
3. Email & Download final documents

### 3.2 Payment Gateway Integration
- Stripe integration for credit/debit cards

### 3.3 Pricing
wall under x feet price a
walls between x and y feet price b
walls over y feet price c

## 4. APPENDICES

### Appendix A: Sample JSON Input Structure
- Complete parameter specification

### Appendix B: API Documentation Format
- RESTful API specifications

### Appendix C: Database Schema
- Complete entity relationship diagrams

### Appendix D: UI/UX Mockups
- Wire frames and design concepts

