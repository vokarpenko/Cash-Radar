-- Decimal amounts remain text when crossing JSON into Flutter Web.
create view public.import_item_details with (security_invoker = true) as
select i.id, i.batch_id, i.row_number, i.transaction_date, i.transaction_type,
       i.amount::text as amount, i.currency, i.account_amount::text as account_amount,
       i.category_id, c.name as category_name, i.raw_description
from public.import_items i join public.categories c on c.id = i.category_id and c.user_id = i.user_id;
revoke all on public.import_item_details from public, anon, authenticated;
grant select on public.import_item_details to authenticated;
grant all on public.import_item_details to service_role;
