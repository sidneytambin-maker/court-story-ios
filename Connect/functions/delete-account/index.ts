// Verify the caller through Supabase Auth; never accept an account ID from the request.
Deno.serve(async (request: Request) => {
  if (request.method !== "DELETE") return new Response("Method not allowed", { status: 405 });
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return new Response("Sign in required", { status: 401 });
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return new Response("Service unavailable", { status: 503 });
  try {
    const userResponse = await fetch(url + "/auth/v1/user", { headers: { apikey: key, Authorization: authorization } });
    if (!userResponse.ok) return new Response("Sign in required", { status: 401 });
    const user = await userResponse.json();
    if (!user.id || user.is_anonymous) return new Response("Verified account required", { status: 403 });
    const deleted = await fetch(url + "/auth/v1/admin/users/" + encodeURIComponent(user.id), {
      method: "DELETE", headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json" }, body: JSON.stringify({ should_soft_delete: false })
    });
    return deleted.ok ? new Response(null, { status: 204 }) : new Response("Account deletion failed; try again", { status: 503 });
  } catch { return new Response("Account deletion unavailable", { status: 503 }); }
});
