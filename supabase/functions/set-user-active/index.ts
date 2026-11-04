import { audit, failure, json, readBody, requireAdmin } from "../_shared/admin.ts";

const BAN_FOREVER = "876000h";

// Deactivating blocks sign-in and ends current sessions. Financial records and open
// bookings stay as they are.
Deno.serve(async (req) => {
  const ctx = await requireAdmin(req);
  if (ctx instanceof Response) return ctx;

  const body = await readBody(req);
  const userId = typeof body?.user_id === "string" ? body.user_id : "";
  const isActive = body?.is_active;
  if (!userId || typeof isActive !== "boolean") return failure(400, "invalid_request");
  if (userId === ctx.adminId && !isActive) return failure(400, "cannot_deactivate_self");

  const { data: profile } = await ctx.service
    .from("profiles")
    .select("id")
    .eq("id", userId)
    .maybeSingle();
  if (!profile) return failure(404, "user_not_found");

  const { error: authError } = await ctx.service.auth.admin.updateUserById(userId, {
    ban_duration: isActive ? "none" : BAN_FOREVER,
  });
  if (authError) {
    console.error(`updateUser failed: ${authError.status} ${authError.code}`);
    return failure(500, "update_failed");
  }

  const { error: profileError } = await ctx.service
    .from("profiles")
    .update({ is_active: isActive })
    .eq("id", userId);
  if (profileError) {
    console.error(`profile update failed: ${profileError.code}`);
    return failure(500, "update_failed");
  }

  if (!isActive) {
    const { error: sessionsError } = await ctx.service.rpc("revoke_user_sessions", { p_user_id: userId });
    if (sessionsError) {
      console.error(`revoke sessions failed: ${sessionsError.code}`);
      return failure(500, "update_failed");
    }
  }

  await audit(ctx, isActive ? "activate_user" : "deactivate_user", userId);

  return json(200, { id: userId, is_active: isActive });
});
