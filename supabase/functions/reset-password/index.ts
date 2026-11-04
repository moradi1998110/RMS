import { audit, failure, json, readBody, requireAdmin, temporaryPassword } from "../_shared/admin.ts";

// Issues a new temporary password and signs the user out everywhere, so a lost
// phone loses access too.
Deno.serve(async (req) => {
  const ctx = await requireAdmin(req);
  if (ctx instanceof Response) return ctx;

  const body = await readBody(req);
  const userId = typeof body?.user_id === "string" ? body.user_id : "";
  if (!userId) return failure(400, "invalid_request");

  const { data: profile } = await ctx.service
    .from("profiles")
    .select("id")
    .eq("id", userId)
    .maybeSingle();
  if (!profile) return failure(404, "user_not_found");

  const password = temporaryPassword();
  const { error: authError } = await ctx.service.auth.admin.updateUserById(userId, { password });
  if (authError) {
    console.error(`updateUser failed: ${authError.status} ${authError.code}`);
    return failure(500, "reset_failed");
  }

  const { error: profileError } = await ctx.service
    .from("profiles")
    .update({ must_change_password: true })
    .eq("id", userId);
  const { error: sessionsError } = await ctx.service.rpc("revoke_user_sessions", { p_user_id: userId });
  if (profileError || sessionsError) {
    console.error(`reset follow-up failed: ${profileError?.code} ${sessionsError?.code}`);
    return failure(500, "reset_failed");
  }

  await audit(ctx, "reset_password", userId);

  return json(200, { id: userId, temporary_password: password });
});
