import { createClient } from 'npm:@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@9'
import serviceAccount from '../service-account.json' with { type: 'json' }

interface Notification {
  id: string
  user_id: string
  title: string
  body: string
  data: string | null
}

interface WebhookPayload {
  type: 'INSERT'
  table: string
  record: Notification
  schema: 'public'
}

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
)

Deno.serve(async (req) => {
  try {
    console.log("🔥 Function triggered")

    const payload: WebhookPayload = await req.json()
    console.log("Payload:", payload)

    const record = payload.record

    if (!record) {
      throw new Error("No record found in payload")
    }

    console.log("User ID:", record.user_id)

    // ✅ Respect the account-level push preference before doing anything else.
    // The in-app notification row (payload.record) was already inserted regardless —
    // this only gates whether we call FCM.
    const { data: userRow, error: userError } = await supabase
      .from('users')
      .select('is_push_enabled')
      .eq('id', record.user_id)
      .single()

    if (userError) {
      console.error("DB Error (users):", userError)
      throw userError
    }

    if (userRow && userRow.is_push_enabled === false) {
      console.log("Push disabled for user, skipping FCM send")
      return new Response(
        JSON.stringify({ message: 'Push disabled for user' }),
        { headers: { 'Content-Type': 'application/json' } }
      )
    }

    // ✅ Get all active device tokens for this user
    const { data: tokens, error } = await supabase
      .from('device_tokens')
      .select('fcm_token')
      .eq('user_id', record.user_id)
      .eq('is_active', true)

    if (error) {
      console.error("DB Error:", error)
      throw error
    }

    console.log("Tokens:", tokens)

    if (!tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({ message: 'No tokens found for user' }),
        { headers: { 'Content-Type': 'application/json' } }
      )
    }

    // ✅ Safe parse of data
    let notifData: Record<string, any> = {}
    try {
      notifData = typeof record.data === 'string'
        ? JSON.parse(record.data)
        : (record.data ?? {})
    } catch (e) {
      console.error("Invalid JSON in record.data:", record.data)
      notifData = {}
    }

    // ✅ Get Firebase access token
    const accessToken = await getAccessToken({
      clientEmail: serviceAccount.client_email,
      privateKey: serviceAccount.private_key,
    })

    console.log("Access token generated")

    // ✅ Send notification to all user devices
    const results = await Promise.all(
      tokens.map(async ({ fcm_token }) => {

        console.log("Sending to token:", fcm_token)

        // ✅ Ensure all data values are strings (FCM requirement)
        const formattedData = Object.fromEntries(
          Object.entries(notifData || {}).map(([k, v]) => [k, String(v)])
        )

        const res = await fetch(
          `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
          {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${accessToken}`,
            },
            body: JSON.stringify({
              message: {
                token: fcm_token,
                notification: {
                  title: record.title,
                  body: record.body,
                },
                data: formattedData,
              },
            }),
          }
        )

        const json = await res.json()
        console.log("FCM Response:", json)

        // ✅ Token is dead (uninstalled app, revoked OS permission at the OS level
        // long enough that Firebase invalidated it, etc.) — soft-delete so it's
        // never selected again, consistent with this schema's soft-delete pattern.
        const fcmErrorStatus = json?.error?.details?.[0]?.errorCode
        if (fcmErrorStatus === 'UNREGISTERED' || fcmErrorStatus === 'INVALID_ARGUMENT') {
          console.log("Deactivating dead token:", fcm_token)
          await supabase
            .from('device_tokens')
            .update({ is_active: false })
            .eq('fcm_token', fcm_token)
        }

        return json
      })
    )

    return new Response(JSON.stringify(results), {
      headers: { 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error("❌ ERROR:", err)

    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})

// ✅ Generate Firebase access token
const getAccessToken = ({
  clientEmail,
  privateKey,
}: {
  clientEmail: string
  privateKey: string
}): Promise<string> => {
  return new Promise((resolve, reject) => {
    const jwtClient = new JWT({
      email: clientEmail,
      key: privateKey,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    })

    jwtClient.authorize((err, tokens) => {
      if (err) {
        console.error("JWT Error:", err)
        reject(err)
        return
      }
      resolve(tokens!.access_token!)
    })
  })
}
