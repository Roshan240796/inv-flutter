# Invoice Application Milestones

## Completed Milestones

### Project Setup
- [x] Install Flutter.
- [x] Install Android Studio.
- [x] Configure the Android SDK.
- [x] Accept Android SDK licenses.
- [x] Create and run a Pixel 7 Android emulator.
- [x] Create the Flutter project.
- [x] Run the Flutter application on the Android emulator.
- [x] Create the Spring Boot application.
- [x] Run Spring Boot inside WSL.
- [x] Connect Spring Boot to PostgreSQL.
- [x] Configure Spring Boot on port `8080`.
- [x] Configure Spring Boot for WSL networking.

Spring Boot server configuration:
```properties
server.port=8080
server.address=0.0.0.0
```

---

### Authentication
- [x] Create a Flutter login screen.
- [x] Remove hard-coded Flutter credentials.
- [x] Store JWT credentials securely using `flutter_secure_storage`.
- [x] Replace Basic Authentication with JWT.
- [x] Add backend login endpoint.
- [x] Add JWT token generation.
- [x] Add JWT token validation.
- [x] Add JWT authentication filter.
- [x] Add logout functionality.
- [x] Add JWT expiration configuration.
- [x] Add basic `ADMIN` role to the authenticated user.
- [x] Verify login through PowerShell.
- [x] Verify protected invoice access using a bearer token.

Login endpoint:
```http
POST /api/auth/login
```

Protected request format:
```http
Authorization: Bearer <JWT_TOKEN>
```

---

### Invoice Lifecycle
- [x] Add invoice details endpoint.
- [x] Add invoice editing endpoint.
- [x] Add invoice deletion endpoint.
- [x] Add invoice status changes.
- [x] Add `DRAFT` status.
- [x] Add `SUBMITTED` status.
- [x] Add `APPROVED` status.
- [x] Add `REJECTED` status.
- [x] Add `PAID` status.
- [x] Add supported invoice status transitions.
- [x] Add invalid status transition validation.
- [x] Add Flutter invoice list loading.
- [x] Add Flutter invoice loading states.
- [x] Add Flutter invoice error and retry handling.
- [x] Add Flutter invoice refresh support.
- [x] Add Flutter invoice creation.
- [x] Add Flutter invoice detail screen.
- [x] Add Flutter invoice edit screen.
- [x] Add invoice line item add/delete support.
- [x] Connect Flutter invoice form to backend invoice APIs.

Supported transitions:
```text
DRAFT      -> SUBMITTED

SUBMITTED  -> APPROVED
SUBMITTED  -> REJECTED

APPROVED   -> PAID

REJECTED   -> DRAFT
REJECTED   -> SUBMITTED
```

---

### Invoice Information
- [x] Add supplier details.
- [x] Add customer address.
- [x] Add customer contact information.
- [x] Add invoice date.
- [x] Add due date.
- [x] Add payment terms.
- [x] Add tax details.
- [x] Add discount details.
- [x] Add invoice line items.
- [x] Add subtotal calculation.
- [x] Add tax calculation.
- [x] Add total calculation.
- [x] Add invoice notes.
- [x] Add invoice attachments.

---

### Testing and Version Control
- [x] Add backend authentication tests.
- [x] Add backend invoice lifecycle tests.
- [x] Add Flutter widget tests.
- [x] Run backend Maven tests successfully.
- [x] Run Flutter analyzer successfully.
- [x] Run Flutter tests successfully.
- [x] Push backend code to `inv-backend/develop`.
- [x] Push Flutter code to `inv-flutter/develop`.
- [x] Merge backend `develop` into `main`.
- [x] Merge Flutter `develop` into `main`.

---

## Partially Completed Milestones

### Authentication
- [ ] Implement full role-based permissions.
- [ ] Add database-backed users.
- [ ] Add refresh tokens.
- [ ] Add automatic token refresh.
- [ ] Add explicit client-side token expiration detection.
- [ ] Add production-grade secret management.

### Invoice Lifecycle
- [ ] Add Flutter invoice deletion controls.
- [ ] Add Flutter status management controls.
- [ ] Add invoice approval workflow UI.
- [ ] Add invoice rejection reasons.
- [ ] Add invoice payment tracking.

---

## Features Still To Implement

### Invoice Search and Filtering
- [ ] Add invoice search.
- [ ] Filter by customer.
- [ ] Filter by status.
- [ ] Filter by date.
- [ ] Filter by currency.
- [ ] Sort by invoice number.
- [ ] Sort by amount.
- [ ] Sort by date.
- [ ] Add pagination.

### XML Integration
- [ ] Upload XML invoices.
- [ ] Parse XML files.
- [ ] Validate XML structure.
- [ ] Display XML validation errors.
- [ ] Store original XML files.
- [ ] Map XML fields to invoice fields.
- [ ] Support standardized e-invoice formats.
- [ ] Add XML processing logs.

### SFTP Integration
- [ ] Configure SFTP connections.
- [ ] Store SFTP settings securely.
- [ ] Upload files through SFTP.
- [ ] Download files through SFTP.
- [ ] Validate transferred files.
- [ ] Add SFTP transfer history.
- [ ] Add retry handling.
- [ ] Add SFTP error logs.

### REST API Integration
- [ ] Configure external API endpoints.
- [ ] Add API authentication settings.
- [ ] Configure request headers.
- [ ] Configure webhooks.
- [ ] Process webhook events.
- [ ] Add request logging.
- [ ] Add response logging.
- [ ] Add API retry handling.
- [ ] Add API timeout handling.
- [ ] Add integration error reporting.

### ERP Integration
- [ ] Design ERP integration interfaces.
- [ ] Add Sage integration support.
- [ ] Add NetSuite integration support.
- [ ] Add SAP integration support.
- [ ] Synchronize customers.
- [ ] Synchronize suppliers.
- [ ] Synchronize invoices.
- [ ] Synchronize payment statuses.
- [ ] Add ERP synchronization logs.

### SSO Integration
- [ ] Support SAML.
- [ ] Support OpenID Connect.
- [ ] Support OAuth2.
- [ ] Configure identity providers.
- [ ] Implement login redirects.
- [ ] Implement callback handling.
- [ ] Implement secure logout.
- [ ] Add SSO error handling.
- [ ] Add identity-provider configuration.

### Client and Project Management
- [ ] Add client management.
- [ ] Add project management.
- [ ] Add project members.
- [ ] Add project status.
- [ ] Add delivery milestones.
- [ ] Add milestone dates.
- [ ] Add milestone ownership.
- [ ] Add stakeholder notes.
- [ ] Add project activity history.

### UAT and Change Management
- [ ] Add UAT test cases.
- [ ] Track UAT progress.
- [ ] Record UAT results.
- [ ] Track defects.
- [ ] Track workflow changes.
- [ ] Add training tasks.
- [ ] Add training completion status.
- [ ] Add client sign-off.
- [ ] Add change-management notes.

### Integration Troubleshooting
- [ ] Add integration health status.
- [ ] Add application logs.
- [ ] Add request and response logs.
- [ ] Add server response inspection.
- [ ] Add data-flow error reporting.
- [ ] Add failed integration records.
- [ ] Add retry controls.
- [ ] Add escalation status.
- [ ] Add diagnostic information.

### Database and Production Readiness
- [ ] Add Flyway or Liquibase migrations.
- [ ] Replace `ddl-auto=update`.
- [ ] Add development configuration.
- [ ] Add test configuration.
- [ ] Add production configuration.
- [ ] Move database credentials to environment variables.
- [ ] Secure all application secrets.
- [ ] Add database indexes.
- [ ] Add database backup strategy.
- [ ] Add production logging.
- [ ] Add health checks.
- [ ] Add monitoring.
- [ ] Add API documentation.
- [ ] Add CI/CD pipeline.
- [ ] Add deployment configuration.

---

## Milestone Summary

| Area | Status |
|---|---|
| Project Setup | ✅ Completed |
| Authentication | 🟡 Partially Completed |
| Invoice Lifecycle | ✅ Completed |
| Testing and Version Control | ✅ Completed |
| Invoice Information | ✅ Completed |
| Invoice Search and Filtering | ⬜ Not Started |
| XML Integration | ⬜ Not Started |
| SFTP Integration | ⬜ Not Started |
| REST API Integration | ⬜ Not Started |
| ERP Integration | ⬜ Not Started |
| SSO Integration | ⬜ Not Started |
| Client and Project Management | ⬜ Not Started |
| UAT and Change Management | ⬜ Not Started |
| Integration Troubleshooting | ⬜ Not Started |
| Database and Production Readiness | ⬜ Not Started |
