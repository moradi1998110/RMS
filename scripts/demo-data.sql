-- A small restaurant and one employee, for trying the employee screens on a phone until
-- the manager and admin screens exist. Paste into the Supabase SQL editor once.
--
-- First create the login: Authentication > Users > Add user, with the email
-- demo.employee@meals.invalid, a password of your choice and Auto Confirm on.

do $$
declare
  v_user uuid;
  v_site uuid;
  v_restaurant uuid;
  v_meal uuid;
  v_row record;
begin
  select id into v_user from auth.users where email = 'demo.employee@meals.invalid';
  if v_user is null then
    raise exception 'Create the user demo.employee@meals.invalid first';
  end if;
  if exists (select 1 from public.profiles where id = v_user) then
    raise exception 'The demo data already exists';
  end if;

  insert into public.sites (name) values ('موقع تجريبي') returning id into v_site;

  insert into public.restaurants (site_id, name, timezone)
  values (v_site, 'مطعم تجريبي', 'Asia/Baghdad')
  returning id into v_restaurant;

  insert into public.profiles (id, username, full_name, department, role, site_id, restaurant_id)
  values (v_user, 'demo.employee', 'موظف تجريبي', 'قسم التجربة', 'employee', v_site, v_restaurant);

  for v_row in
    select * from (values
      ('بيض وجبن مع خبز', 'بيض مسلوق وجبن أبيض وخبز طازج', 3000, 'breakfast', false, false, false, true),
      ('رز ودجاج مشوي', 'رز بسمتي مع نصف دجاجة مشوية', 6000, 'lunch', true, false, true, false),
      ('سمك مع خضار', 'فيليه سمك مشوي مع خضار سوتيه', 7500, 'lunch', true, true, false, false),
      ('شوربة عدس وساندويش', 'شوربة عدس ساخنة وساندويش جبن', 4000, 'dinner', false, false, true, false)
    ) as t(name, description, price, period, salad, soft_drink, juice, vegetables)
  loop
    insert into public.meals (restaurant_id, name, description, price, has_salad, has_soft_drink, has_juice, has_vegetables)
    values (v_restaurant, v_row.name, v_row.description, v_row.price, v_row.salad, v_row.soft_drink, v_row.juice, v_row.vegetables)
    returning id into v_meal;

    insert into public.schedules (restaurant_id, meal_id, period, season, weekdays, start_date)
    values (v_restaurant, v_meal, v_row.period::public.meal_period, 'normal', array[0, 1, 2, 3, 4, 5, 6]::smallint[], current_date);
  end loop;

  perform private.generate_offerings(v_restaurant);
  perform private.post_tx(v_user, 'topup', 100000, 0, null, 'رصيد تجريبي');
end;
$$;
