#!/bin/bash

# ========= CONFIG =========
DB_NAME="admin-backend"
DB_USER="postgres"
DB_HOST="localhost"
DB_PORT="5432"

# Provide user IDs here
USER_IDS=(101 205 333)

# Output dump file
DUMP_FILE="user_export_$(date +%Y%m%d_%H%M%S).sql"

TEMP_SCHEMA="temp_user_export"
# ===========================

USER_IDS_CSV=$(IFS=,; echo "${USER_IDS[*]}")

echo "Creating temporary schema..."

psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME <<EOF

DROP SCHEMA IF EXISTS $TEMP_SCHEMA CASCADE;
CREATE SCHEMA $TEMP_SCHEMA;

-- 1️⃣ Copy users
CREATE TABLE $TEMP_SCHEMA.users AS
SELECT * FROM public.users WHERE id IN ($USER_IDS_CSV);

-- 2️⃣ Copy all direct FK tables referencing users.id

CREATE TABLE $TEMP_SCHEMA.bank_accounts AS
SELECT * FROM public.bank_accounts WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.upi_details AS
SELECT * FROM public.upi_details WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.transactions AS
SELECT * FROM public.transactions WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.withdrawals AS
SELECT * FROM public.withdrawals WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.kyc_details AS
SELECT * FROM public.kyc_details WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.kyc_journey AS
SELECT * FROM public.kyc_journey WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.nominees AS
SELECT * FROM public.nominees WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.nominee_guardians AS
SELECT ng.*
FROM public.nominee_guardians ng
JOIN public.nominees n ON n.id = ng.nominee_id
WHERE n.user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.additional_details AS
SELECT * FROM public.additional_details WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.primary_addresses AS
SELECT * FROM public.primary_addresses WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.segment_activation AS
SELECT * FROM public.segment_activation WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.demat_mapping AS
SELECT * FROM public.demat_mapping WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.consents AS
SELECT * FROM public.consents WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.account_closure_requests AS
SELECT * FROM public.account_closure_requests WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.kyc_modify_requests AS
SELECT * FROM public.kyc_modify_requests WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.referral_code_usage AS
SELECT * FROM public.referral_code_usage WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.non_kyc_users AS
SELECT * FROM public.non_kyc_users WHERE user_id IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.collections AS
SELECT * FROM public.collections WHERE userid IN ($USER_IDS_CSV);

-- 3️⃣ Copy dependent collection tables

CREATE TABLE $TEMP_SCHEMA.instrumentscollection AS
SELECT ic.*
FROM public.instrumentscollection ic
JOIN public.collections c ON c.id = ic.collection_id
WHERE c.userid IN ($USER_IDS_CSV);

CREATE TABLE $TEMP_SCHEMA.basketscollection AS
SELECT bc.*
FROM public.basketscollection bc
JOIN public.collections c ON c.id = bc.collection_id
WHERE c.userid IN ($USER_IDS_CSV);

-- 4️⃣ Copy instruments referenced by collections

CREATE TABLE $TEMP_SCHEMA.instruments AS
SELECT DISTINCT i.*
FROM public.instruments i
JOIN public.instrumentscollection ic ON ic.instrument_id = i.id
JOIN public.collections c ON c.id = ic.collection_id
WHERE c.userid IN ($USER_IDS_CSV);

EOF

echo "Dumping schema..."

pg_dump \
  -h $DB_HOST \
  -p $DB_PORT \
  -U $DB_USER \
  -d $DB_NAME \
  --schema=$TEMP_SCHEMA \
  --data-only \
  --column-inserts \
  -f $DUMP_FILE

echo "Dump created: $DUMP_FILE"

echo "Cleaning temporary schema..."

psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "DROP SCHEMA $TEMP_SCHEMA CASCADE;"

echo "Done."