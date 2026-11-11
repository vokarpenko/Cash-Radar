-- Dates must be representable by the application's calendar, including direct API writes.
alter table public.transactions add constraint transaction_date_supported
  check (transaction_date between date '1900-01-01' and date '2100-12-31');
