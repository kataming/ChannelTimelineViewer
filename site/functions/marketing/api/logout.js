import { clearCookie } from '../../../marketing-server/auth.js';

export function onRequest({ request }) {
  const url = new URL(request.url);
  return new Response(null, {
    status: 303,
    headers: { Location: `${url.origin}/marketing/`, 'Set-Cookie': clearCookie() },
  });
}
