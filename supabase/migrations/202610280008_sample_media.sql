begin;
alter table public.products add column image_is_illustration boolean not null default false;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('comparts-sample-media','comparts-sample-media',true,2097152,array['image/png'])
on conflict(id) do nothing;

-- Public catalog media may be read through public object URLs. Only backend
-- credentials upload/replace/delete the supplied sample assets.
create policy comparts_sample_media_no_client_insert on storage.objects
as restrictive for insert to anon,authenticated
with check (bucket_id <> 'comparts-sample-media');
create policy comparts_sample_media_no_client_update on storage.objects
as restrictive for update to anon,authenticated
using (bucket_id <> 'comparts-sample-media')
with check (bucket_id <> 'comparts-sample-media');
create policy comparts_sample_media_no_client_delete on storage.objects
as restrictive for delete to anon,authenticated
using (bucket_id <> 'comparts-sample-media');
commit;
