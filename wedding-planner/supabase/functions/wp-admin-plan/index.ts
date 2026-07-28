// Edge function wp-admin-plan (desplegada en el proyecto Supabase).
// Activa o desactiva el plan Destacado de un proveedor. Solo el administrador
// (ADMIN_EMAIL) puede llamarla; la actualización real la hace la RPC
// wp_admin_set_plan con la clave de servicio.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ADMIN_EMAIL = "jose1903ace@gmail.com";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await caller.auth.getUser();
    if (!user || (user.email ?? "").toLowerCase() !== ADMIN_EMAIL) {
      return json({ ok: false, error: "not_admin" }, 403);
    }
    const { email, days } = await req.json();
    if (!email) return json({ ok: false, error: "missing_email" }, 400);
    const svc = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data, error } = await svc.rpc("wp_admin_set_plan", { p_email: email, p_days: days ?? 30 });
    if (error) return json({ ok: false, error: error.message }, 400);
    return json(data);
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e) }, 400);
  }
});
