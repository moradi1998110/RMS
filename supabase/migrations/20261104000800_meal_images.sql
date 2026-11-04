-- Meal photos. Readable by link, which keeps them fast and cacheable, since they hold
-- no personal data. Managers write only inside their own restaurant's folder:
-- <restaurant_id>/<file name>. The app compresses images before upload.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('meal-images', 'meal-images', true, 307200, array['image/webp', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create policy meal_images_manager_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'meal-images'
    and private.app_role() = 'manager'
    and (storage.foldername(name))[1] = private.my_restaurant_id()::text
  );

create policy meal_images_manager_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'meal-images'
    and private.app_role() = 'manager'
    and (storage.foldername(name))[1] = private.my_restaurant_id()::text
  );

-- Deleting and uploading need to find the manager's own files.
create policy meal_images_manager_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'meal-images'
    and private.app_role() = 'manager'
    and (storage.foldername(name))[1] = private.my_restaurant_id()::text
  );
