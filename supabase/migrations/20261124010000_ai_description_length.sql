-- Descriptions can be as long as imported transaction descriptions.
alter table public.ai_merchant_rules
  drop constraint ai_merchant_rules_merchant_name_check;
alter table public.ai_merchant_rules
  add constraint ai_merchant_rules_merchant_name_check
  check (length(merchant_name) between 3 and 500);

alter table public.ai_unrecognized_merchants
  drop constraint ai_unrecognized_merchants_merchant_name_check;
alter table public.ai_unrecognized_merchants
  add constraint ai_unrecognized_merchants_merchant_name_check
  check (length(merchant_name) between 3 and 500);
