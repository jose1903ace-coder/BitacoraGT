# Wedding Planner

Aplicación web elegante y minimalista para organizar bodas: reserva venues,
contrata wedding planners y floristerías, y renta mobiliario para tu evento.

## Cómo funciona

Es una aplicación de un solo archivo (`index.html`), igual que la bitácora de
vuelos. Puedes abrirla directamente en el navegador o publicarla con GitHub
Pages, Netlify, etc. El backend (cuentas, anuncios y reservas) es Supabase.

## Dos tipos de cuenta

- **Pareja (cliente):** explora el catálogo, envía solicitudes de reserva con
  fecha e invitados, y da seguimiento desde su panel, donde ve el nombre,
  teléfono y correo del proveedor de cada solicitud.
- **Proveedor:** publica anuncios (venue, wedding planner, floristería,
  fotógrafo o mobiliario) con descripción, ubicación, precio y foto — la foto
  se elige de la galería o cámara y se sube a Supabase Storage (bucket
  `wp-images`) comprimida automáticamente; recibe solicitudes y las acepta o
  declina desde su panel. La sección de planes solo se muestra a proveedores
  y visitantes, no a las parejas.

## Planes para proveedores (monetización)

- **Gratis:** 1 anuncio activo. Es el plan con el que nace toda cuenta de
  proveedor. El límite se aplica en la base de datos (trigger `wp_listing_limit`).
- **Destacado (Q299/mes):** anuncios ilimitados, insignia dorada "★ Destacado"
  y primeros lugares del catálogo. El botón "Quiero destacar" abre un correo a
  `jose1903ace@gmail.com` con los datos del proveedor para coordinar el pago
  (transferencia, Recurrente, etc.).

### Activar el plan Destacado a un proveedor (tras recibir el pago)

**Con un clic:** el correo que envía el proveedor con "Quiero destacar" incluye
un enlace de activación (`…/wedding-planner/?activar=correo@proveedor.com`).
Al abrirlo, entra con la cuenta de administrador (`jose1903ace@gmail.com`) y
elige la duración: 1, 3 o 12 meses, o "Quitar Destacado". La activación la
ejecuta la edge function `wp-admin-plan`, que verifica que quien la llama sea
el administrador y luego corre `wp_admin_set_plan` con permisos de servidor.

También puedes abrir ese enlace tú mismo en cualquier momento cambiando el
correo, o usar el SQL Editor de Supabase:

```sql
update public.wp_profiles
set plan = 'premium', plan_expires_at = now() + interval '30 days'
where id = (select id from auth.users where email = 'correo@delproveedor.com');
```

Los usuarios no pueden cambiarse el plan a sí mismos (trigger `wp_protect_plan`
+ RPC restringida a service_role).

Para cambiar el precio mostrado en la página, edita `PLAN_PRICE` y la sección
"Planes" en `index.html`. El correo de contacto está en `CONTACT_EMAIL`.

## Notificaciones por correo al proveedor

Cuando una pareja envía una solicitud, la app llama a la edge function
`wp-notify-booking`, que envía un correo al proveedor con los datos de la
pareja (nombre, fecha, invitados, teléfono, correo y mensaje) y un botón para
abrir su panel. El envío usa la API de [Brevo](https://www.brevo.com) (gratis
hasta 300 correos/día). Para activarlo (una sola vez):

1. Crea una cuenta gratis en brevo.com y verifica el remitente
   `jose1903ace@gmail.com` (Settings → Senders → Add sender; te llega un
   correo de confirmación).
2. Copia tu clave: Settings → SMTP & API → API Keys → Generate a new API key.
3. En Supabase → Project Settings → Edge Functions → Secrets, agrega
   `BREVO_API_KEY` con esa clave.

Sin la clave, la app funciona igual (la solicitud se registra y se ve en el
panel); simplemente no se envía el correo.

## Backend (Supabase)

- Proyecto: `pnlefnwngmktiykelkdd` (la app usa la clave *publishable*, segura
  para exponer en el navegador).
- Esquema y políticas de seguridad (RLS): ver `schema.sql`. Las tablas usan el
  prefijo `wp_` para no chocar con otras tablas del proyecto.
- Al registrarse un usuario, un trigger crea su perfil con el rol elegido.

### Nota sobre confirmación de correo

Si Supabase tiene activada la confirmación por correo (opción por defecto),
los usuarios nuevos deben confirmar su email antes de entrar; la app muestra
el aviso correspondiente. Para desactivarla: panel de Supabase →
Authentication → Sign In / Up → desmarcar "Confirm email".
