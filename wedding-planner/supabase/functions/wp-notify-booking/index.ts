// Edge function wp-notify-booking (desplegada en el proyecto Supabase).
// Al crear una solicitud de reserva, envía un correo al proveedor con los
// datos de la pareja (nombre, fecha, invitados, teléfono, correo y mensaje).
// Verifica que quien llama sea el autor de la solicitud. El envío usa la API
// de Brevo; la clave se lee del entorno (BREVO_API_KEY) o, si no existe, de
// la tabla protegida wp_secrets (solo legible con service_role). Opcionales:
// SENDER_EMAIL, SENDER_NAME, APP_URL.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

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
    if (!user) return json({ ok: false, error: "no_auth" }, 401);

    const { booking_id } = await req.json();
    if (!booking_id) return json({ ok: false, error: "missing_booking" }, 400);

    const svc = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: b, error } = await svc.from("wp_bookings")
      .select("id, event_date, guests, message, client_id, wp_listings(title, wp_profiles(full_name, phone, email)), wp_profiles(full_name, phone, email)")
      .eq("id", booking_id).single();
    if (error || !b) return json({ ok: false, error: "not_found" }, 404);
    if (b.client_id !== user.id) return json({ ok: false, error: "forbidden" }, 403);

    // La clave puede venir del entorno o de la tabla protegida wp_secrets
    let key = Deno.env.get("BREVO_API_KEY");
    if (!key) {
      const { data: sec } = await svc.from("wp_secrets").select("value").eq("key", "BREVO_API_KEY").maybeSingle();
      key = sec?.value;
    }
    if (!key) return json({ ok: false, error: "email_disabled" });

    const listing: any = b.wp_listings;
    const prov = listing?.wp_profiles;
    const cli: any = b.wp_profiles;
    if (!prov?.email) return json({ ok: false, error: "no_provider_email" });

    const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
    const fecha = b.event_date
      ? new Date(b.event_date + "T12:00:00").toLocaleDateString("es-GT", { day: "numeric", month: "long", year: "numeric" })
      : "por definir";
    const appUrl = Deno.env.get("APP_URL") ?? "https://jose1903ace-coder.github.io/BitacoraGT/wedding-planner/";

    const html = `
      <div style="font-family:Georgia,serif;max-width:520px;margin:0 auto;color:#221f1b">
        <h2 style="font-weight:500">Tienes una nueva solicitud de reserva</h2>
        <p style="font-family:Arial,sans-serif;font-size:14px;line-height:1.6">
          Tu anuncio <strong>${esc(listing?.title)}</strong> recibió una solicitud en Wedding Planner:
        </p>
        <table style="font-family:Arial,sans-serif;font-size:14px;line-height:1.9">
          <tr><td style="color:#8a8278;padding-right:14px">Pareja</td><td><strong>${esc(cli?.full_name)}</strong></td></tr>
          <tr><td style="color:#8a8278">Fecha del evento</td><td>${esc(fecha)}</td></tr>
          <tr><td style="color:#8a8278">Invitados</td><td>${esc(b.guests ?? "por definir")}</td></tr>
          <tr><td style="color:#8a8278">Teléfono</td><td>${esc(cli?.phone ?? "—")}</td></tr>
          <tr><td style="color:#8a8278">Correo</td><td>${esc(cli?.email ?? "—")}</td></tr>
        </table>
        ${b.message ? `<p style="font-family:Arial,sans-serif;font-size:14px;font-style:italic;border-left:3px solid #b08d57;padding-left:12px">“${esc(b.message)}”</p>` : ""}
        <p style="margin-top:24px">
          <a href="${appUrl}" style="background:#b08d57;color:#fff;text-decoration:none;padding:12px 24px;font-family:Arial,sans-serif;font-size:13px;letter-spacing:1px">RESPONDER EN MI PANEL</a>
        </p>
        <p style="font-family:Arial,sans-serif;font-size:12px;color:#8a8278;margin-top:28px">Wedding Planner · Acepta o declina la solicitud desde tu panel.</p>
      </div>`;

    const r = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": key, "Content-Type": "application/json" },
      body: JSON.stringify({
        sender: { name: Deno.env.get("SENDER_NAME") ?? "Wedding Planner", email: Deno.env.get("SENDER_EMAIL") ?? "jose1903ace@gmail.com" },
        to: [{ email: prov.email, name: prov.full_name ?? "" }],
        subject: `Nueva solicitud de reserva · ${listing?.title ?? "Wedding Planner"}`,
        htmlContent: html,
      }),
    });
    if (!r.ok) return json({ ok: false, error: "send_failed: " + (await r.text()).slice(0, 300) });
    return json({ ok: true });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message ?? e) }, 400);
  }
});
