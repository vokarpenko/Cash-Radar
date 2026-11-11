-- Preview and errors use physical CSV line numbers, including blank and quoted lines.
alter table public.import_items drop constraint import_items_row_number_check;
alter table public.import_items add constraint import_items_row_number_check
  check (row_number between 2 and 1048577);
