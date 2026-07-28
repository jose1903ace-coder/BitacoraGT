# Wedding Planner

Aplicación web elegante y minimalista para organizar bodas: reserva venues,
contrata wedding planners y floristerías, y renta mobiliario para tu evento.

## Cómo funciona

Es una aplicación de un solo archivo (`index.html`), igual que la bitácora de
vuelos. Puedes abrirla directamente en el navegador o publicarla con GitHub
Pages, Netlify, etc. El backend (cuentas, anuncios y reservas) es Supabase.

## Dos tipos de cuenta

- **Pareja (cliente):** explora el catálogo, envía solicitudes de reserva con
  fecha e invitados, y da seguimiento desde su panel. Al ser aceptada una
  solicitud, ve el contacto del proveedor.
- **Proveedor:** publica anuncios (venue, wedding planner, floristería,
  fotógrafo o mobiliario) con descripción, ubicación, precio y foto; recibe solicitudes y
  las acepta o declina desde su panel.

## Planes para proveedores (monetización)

- **Gratis:** 1 anuncio activo. Es el plan con el que nace toda cuenta de
  proveedor. El límite se aplica en la base de datos (trigger `wp_listing_limit`).
- **Destacado (Q299/mes):** anuncios ilimitados, insignia dorada "★ Destacado"
  y primeros lugares del catálogo. El botón "Quiero destacar" abre un correo a
  `jose1903ace@gmail.com` con los datos del proveedor para coordinar el pago
  (transferencia, Recurrente, etc.).

### Activar el plan Destacado a un proveedor (tras recibir el pago)

En el panel de Supabase → SQL Editor, ejecuta (cambia el correo):

```sql
update public.wp_profiles
set plan = 'premium', plan_expires_at = now() + interval '30 days'
where id = (select id from auth.users where email = 'correo@delproveedor.com');
```

Para renovar, vuelve a ejecutar lo mismo; para cancelar, pon `plan = 'free'`.
Los usuarios no pueden cambiarse el plan a sí mismos (trigger `wp_protect_plan`).

Para cambiar el precio mostrado en la página, edita `PLAN_PRICE` y la sección
"Planes" en `index.html`. El correo de contacto está en `CONTACT_EMAIL`.

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
