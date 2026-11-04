import {
  audit,
  failure,
  json,
  LOGIN_EMAIL_DOMAIN,
  readBody,
  requireAdmin,
  temporaryPassword,
} from "../_shared/admin.ts";

const ROLES = ["admin", "manager", "employee"];

// The temporary password is returned once, for the admin to hand over. It is never stored.
Deno.serve(async (req) => {
  const ctx = await requireAdmin(req);
  if (ctx instanceof Response) return ctx;

  const body = await readBody(req);
  if (!body) return failure(400, "invalid_request");

  const username = typeof body.username === "string" ? body.username.trim().toLowerCase() : "";
  const fullName = typeof body.full_name === "string" ? body.full_name.trim() : "";
  const department = typeof body.department === "string" ? body.department.trim() || null : null;
  const role = body.role as string;
  const restaurantId = typeof body.restaurant_id === "string" ? body.restaurant_id : null;

  if (!/^[a-z0-9._-]{3,32}$/.test(username)) return failure(400, "invalid_username");
  if (!fullName) return failure(400, "invalid_full_name");
  if (!ROLES.includes(role)) return failure(400, "invalid_role");
  if (role === "admin" && restaurantId) return failure(400, "admin_has_no_restaurant");
  if (role !== "admin" && !restaurantId) return failure(400, "restaurant_required");

  let siteId: string | null = null;
  if (restaurantId) {
    const { data: restaurant } = await ctx.service
      .from("restaurants")
      .select("site_id")
      .eq("id", restaurantId)
      .eq("is_active", true)
      .maybeSingle();
    if (!restaurant) return failure(400, "restaurant_not_found");
    siteId = restaurant.site_id;
  }

  const { data: existing } = await ctx.service
    .from("profiles")
    .select("id")
    .eq("username", username)
    .maybeSingle();
  if (existing) return failure(409, "username_taken");

  const password = temporaryPassword();
  const { data: created, error: createError } = await ctx.service.auth.admin.createUser({
    email: `${username}@${LOGIN_EMAIL_DOMAIN}`,
    password,
    email_confirm: true,
  });
  if (createError || !created.user) {
    console.error(`createUser failed: ${createError?.status} ${createError?.code}`);
    return failure(createError?.status === 422 ? 409 : 500, createError?.status === 422 ? "username_taken" : "create_failed");
  }

  const userId = created.user.id;
  const { error: profileError } = await ctx.service.from("profiles").insert({
    id: userId,
    username,
    full_name: fullName,
    department,
    role,
    site_id: siteId,
    restaurant_id: restaurantId,
  });

  // Never leave a login without a profile behind.
  if (profileError) {
    console.error(`profile insert failed: ${profileError.code}`);
    await ctx.service.auth.admin.deleteUser(userId);
    return failure(500, "create_failed");
  }

  await audit(ctx, "create_user", userId, { username, role, restaurant_id: restaurantId });

  return json(201, { id: userId, username, temporary_password: password });
});
