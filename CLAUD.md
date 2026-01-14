# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Retaining Wall Business Management System** - a comprehensive SaaS application for professional engineering design services. The system combines:
- A C++ engineering calculation engine for generating professional PDF drawings
- A modern web portal for customer project submission and management
- Business operations tools (CRM, payments, order management)
- Professional compliance infrastructure (building codes, licensing)

**Current Status**: Requirements phase complete, pre-development. Directory structure established but source code not yet committed.

## Architecture Overview

### System Components

1. **C++ Engineering Core** (`rwcpp/`)
   - Handles engineering calculations for retaining wall designs
   - Generates professional PDF drawings with engineering stamps
   - Currently functional standalone, needs REST API wrapper
   - Input: JSON configuration → Output: PDF documents

2. **Web Application** (`webui/`)
   - Frontend: React.js or Vue.js with Material-UI/Ant Design
   - Backend: Node.js/Express or Python/FastAPI
   - Database: PostgreSQL (primary) + DynamoDB (sessions)
   - File Storage: AWS S3 for documents

3. **Infrastructure**
   - AWS cloud deployment (EC2, Lambda, S3, RDS, CloudFront)
   - Queue-based async processing (RabbitMQ/SQS)
   - Redis caching for calculations
   - WebSocket real-time updates

### Key Integration Points

- **C++ ↔ Web API**: Child process spawning or microservice architecture
- **Payment Processing**: Stripe, PayPal, ACH integration
- **Document Management**: S3 storage with versioning
- **Authentication**: email provided, with email results.  No accounts necessary.  
- **Email/SMS**: emailjs for notifications

## Development Commands

### C++ Application (rwcpp/)
```bash
# Build commands will be established once CMakeLists.txt is created
# Planned structure:
mkdir build && cd build
cmake ..
make
./rwcpp_test  # Run tests
```

### Web Application (webui/)
```bash
# Commands will be established once package.json is created
# Planned structure:
npm install       # Install dependencies
npm run dev       # Start development server
npm run build     # Build for production
npm test          # Run test suite
npm run lint      # Run linter
```

### Database Operations
```bash
# Planned migrations (once established):
npm run migrate           # Run database migrations
npm run migrate:rollback  # Rollback last migration
npm run seed             # Seed development data
```

## Critical Implementation Notes

### Phase 1 Priorities (Months 1-3)
1. Wrap C++ engine with REST API
2. Implement basic web 
3. Add preview generation (simplified calculations)
4. Integrate Stripe payments
5. Deploy to AWS staging environment

### Engineering Calculation Flow
1. User submits project parameters via web form
2. System validates input and creates job in queue
3. C++ engine processes calculation asynchronously
4. Results in S3 document storage
5. User notified via email/WebSocket when complete


## Project Structure

```
retainingWall/
├── rwcpp/           # C++ calculation engine
│   ├── main/        # Development branch
│   ├── test/        # Test environment
│   └── production/  # Production release
├── webui/           # Web application (to be created)
│   ├── frontend/    # React/Vue application
│   ├── backend/     # API server
│   └── shared/      # Shared utilities
└── docs/            # Documentation
    └── requirements.md  # Comprehensive requirements (735 lines)
```

## Key Files to Review

1. **docs/requirements.md** - Complete system requirements and specifications
2. **rwcpp/** - C++ application directory (code to be added)
3. **webui/** - Web application directory (to be created)

## Development Workflow

1. **Feature Development**: Create feature branch from `main`
2. **Testing**: Ensure >80% code coverage before PR
3. **Code Review**: All changes require review
4. **Deployment**: Automated via CI/CD pipeline (to be established)

## Contact Points

- **Requirements Questions**: Review docs/requirements.md first
- **C++ Engine**: Focus on API wrapper development
- **Web Portal**: Follow modern React/Vue best practices
- **Infrastructure**: AWS-first approach with cost optimization

## Next Steps for Development

1. Initialize git repository with proper branching strategy
2. Set up C++ project with CMakeLists.txt
3. Create web application scaffold (package.json, folder structure)
4. Establish CI/CD pipeline with GitHub Actions or GitLab CI
5. Begin Phase 1 implementation per requirements document