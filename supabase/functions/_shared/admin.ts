import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.58.0";

export const LOGIN_EMAIL_DOMAIN = "meals.invalid";

// Prefers the project's secret key. The local stack may only provide the older variable.
function serverKey(): string {
  const keys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (keys) {
    const parsed = JSON.parse(keys) as Record<string, string>;
    const key = parsed.default ?? Object.values(parsed)[0];
    if (key) return key;
  }
  console.warn("SUPABASE_SECRET_KEYS not set, using SUPABASE_SERVICE_ROLE_KEY");
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
}

export type AdminContext = { service: SupabaseClient; adminId: string };

export function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export function failure(status: number, error: string): Response {
  return json(status, { error });
}

// Returns the service client only when the caller is an active admin.
export async function requireAdmin(req: Request): Promise<AdminContext | Response> {
  if (req.method !== "POST") {
    return failure(405, "method_not_allowed");
  }

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) {
    return failure(401, "unauthorized");
  }

  const service = createClient(
    Deno.env.get("SUPABASE_URL")!,
    serverKey(),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: { user }, error } = await service.auth.getUser(token);
  if (error || !user) {
    return failure(401, "unauthorized");
  }

  const { data: profile } = await service
    .from("profiles")
    .select("role, is_active")
    .eq("id", user.id)
    .maybeSingle();

  if (profile?.role !== "admin" || !profile.is_active) {
    return failure(403, "forbidden");
  }

  return { service, adminId: user.id };
}

export async function readBody(req: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = await req.json();
    return body && typeof body === "object" && !Array.isArray(body) ? body : null;
  } catch {
    return null;
  }
}

// Easy to read aloud and type: no letters or digits that look alike.
export function temporaryPassword(length = 10): string {
  const alphabet = "abcdefghjkmnpqrstuvwxyz23456789";
  const limit = 256 - (256 % alphabet.length);
  let password = "";
  while (password.length < length) {
    for (const byte of crypto.getRandomValues(new Uint8Array(length * 2))) {
      if (byte < limit && password.length < length) {
        password += alphabet[byte % alphabet.length];
      }
    }
  }
  return password;
}

export async function audit(
  ctx: AdminContext,
  action: string,
  entityId: string,
  details: Record<string, unknown> = {},
): Promise<void> {
  const { error } = await ctx.service.from("audit_log").insert({
    actor_id: ctx.adminId,
    action,
    entity: "profile",
    entity_id: entityId,
    details,
  });
  if (error) {
    console.error(`audit failed: ${action}: ${error.code}`);
  }
}
