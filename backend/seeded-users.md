# Seeded Users Reference

This file lists the current development seed users
and invite details for the backend.

These values match:

- [backend/src/utils/seed.js](/Users/gafar/Documents/Documents/myPlayGround/adams/backend/src/utils/seed.js)
- [backend/.env](/Users/gafar/Documents/Documents/myPlayGround/adams/backend/.env)

If you change the seed values in `.env` and rerun
`npm run seed`, update this file too.

## Shared Seed Passwords

- Admin password: `AdminPass123!` Source:
  `SEED_ADMIN_PASSWORD`
- Staff password: `StaffPass123!` Source:
  `SEED_STAFF_PASSWORD`
- Customer password: `CustomerPass123!` Source:
  `SEED_CUSTOMER_PASSWORD`

## Seeded Accounts

### 1. Admin

- Role: `admin`
- Status: `active`
- First name: `Adams`
- Last name: `Gafar`
- Email: `admin@adams.local`
- Phone: `+491111111111`
- Password: `AdminPass123!`

### 2. Staff 1

- Role: `staff`
- Status: `active`
- First name: `Daniel`
- Last name: `Weber`
- Email: `staff1@adams.local`
- Phone: `+492222222222`
- Password: `StaffPass123!`

### 3. Staff 2

- Role: `staff`
- Status: `active`
- First name: `Sofia`
- Last name: `Keller`
- Email: `staff2@adams.local`
- Phone: `+493333333333`
- Password: `StaffPass123!`

### 4. Customer 1

- Role: `customer`
- Status: `active`
- First name: `Michael`
- Last name: `Braun`
- Email: `customer1@adams.local`
- Phone: `+494444444444`
- Password: `CustomerPass123!`

### 5. Customer 2

- Role: `customer`
- Status: `active`
- First name: `Laura`
- Last name: `Hoffmann`
- Email: `customer2@adams.local`
- Phone: `+495555555555`
- Password: `CustomerPass123!`

## Pending Staff Invite

- Role: `staff`
- Status: `invited`
- First name: `Elias`
- Last name: `Becker`
- Email: `pending.staff@adams.local`
- Phone: `+496666666666`
- Password: none yet
- Invite id: `sample-invite-id`
- Notes: this user is not created as an active
  account until the invite registration flow is
  completed
