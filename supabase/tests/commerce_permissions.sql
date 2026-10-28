-- Read-only privilege assertions against the linked project.
do $$
declare f record; t text; r text;
begin
  for f in select oid::regprocedure as signature from pg_proc where pronamespace='public'::regnamespace and proname like 'commerce_%' loop
    foreach r in array array['anon','authenticated'] loop
      if has_function_privilege(r,f.signature,'execute') then raise exception 'Unexpected client execute privilege on % for %',f.signature,r; end if;
    end loop;
    if not has_function_privilege('service_role',f.signature,'execute') then raise exception 'Missing service execute privilege on %',f.signature; end if;
  end loop;
  foreach t in array array['orders','order_delivery_events','order_reviews'] loop
    foreach r in array array['anon','authenticated'] loop
      if has_table_privilege(r,'public.'||t,'INSERT,UPDATE,DELETE,TRUNCATE') then raise exception 'Unexpected client write privilege on % for %',t,r; end if;
    end loop;
    if not exists(select 1 from pg_class where oid=('public.'||t)::regclass and relrowsecurity) then raise exception 'Missing RLS on %',t; end if;
  end loop;
  if not has_function_privilege('anon','public.product_review_summary(uuid)','execute') then raise exception 'Public review projection unavailable'; end if;
end $$;
select 'commerce privilege assertions passed' as result;
