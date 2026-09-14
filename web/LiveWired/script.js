// ---- Fill these in before deploying ----
const CONFIG = {
  APP_SCHEME: "livewired-auth://login-callback",
  PLAY_STORE_URL: "https://play.google.com/store/apps/details?id=REPLACE_WITH_PACKAGE_NAME",
  APP_STORE_URL: "https://apps.apple.com/app/idREPLACE_WITH_APPLE_ID",
  SUPABASE_URL: "https://vzieacbdhrandechlljw.supabase.co",   // ← Project URL
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6aWVhY2JkaHJhbmRlY2hsbGp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ3OTUwNjcsImV4cCI6MjA4MDM3MTA2N30.q682loyT08p98_IxIZJecvQNium7i4bBSHrfyBS10n0",                                 // ← anon / public key
};

// User-agent sniffing is the only option here (there's no reliable standard
// API for OS detection) - it only decides which store link/label to show,
// never anything security-sensitive.
function detectPlatform() {
  const ua = navigator.userAgent || "";
  if (/android/i.test(ua)) return "android";
  if (/iPhone|iPad|iPod/i.test(ua)) return "ios";
  if (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1) return "ios"; // iPadOS 13+ reports as Mac
  return "desktop";
}

const ERROR_MESSAGES = {
  otp_expired: "This verification link has expired. Please request a new one from the app.",
  access_denied: "This link is no longer valid. It may have already been used.",
  invalid_request: "This link is malformed or incomplete.",
  token_used: "This link has already been used. Try signing in from the app.",
};

function parseAuthParams() {
  const merged = {};
  // URLSearchParams already fully percent-decodes values (and turns "+" into
  // a space), so nothing downstream should decode these a second time.
  for (const source of [window.location.hash.slice(1), window.location.search.slice(1)]) {
    new URLSearchParams(source).forEach((value, key) => {
      merged[key] = value;
    });
  }
  return merged;
}

// Deliberately conservative: only used to decide whether to *display* a
// value, never to decide trust. The email is always inserted via
// textContent (see showEmail), so this is a display filter, not an XSS guard.
function isPlausibleEmail(value) {
  return typeof value === "string" && value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function showEmail(lineId, valueId, email) {
  if (!isPlausibleEmail(email)) return;
  const line = document.getElementById(lineId);
  const valueEl = document.getElementById(valueId);
  valueEl.textContent = email; // textContent only - never innerHTML - so this can't be used for markup/script injection
  line.classList.remove("hidden");
}

function showState(id) {
  document.querySelectorAll(".state").forEach((el) => el.classList.add("hidden"));
  document.getElementById(id).classList.remove("hidden");
}

function buildDeepLink(forwardParams) {
  const qs = new URLSearchParams(forwardParams).toString();
  return qs ? `${CONFIG.APP_SCHEME}?${qs}` : CONFIG.APP_SCHEME;
}

// Reveals the store link(s) matching the visitor's platform. On desktop we
// don't know which they'd want, so both are shown.
function revealStoreLinks(suffix, platform) {
  const playLink = document.getElementById(`play-link-${suffix}`);
  const appstoreLink = document.getElementById(`appstore-link-${suffix}`);
  if (playLink) {
    playLink.href = CONFIG.PLAY_STORE_URL;
    if (platform === "android" || platform === "desktop") playLink.classList.remove("hidden");
  }
  if (appstoreLink) {
    appstoreLink.href = CONFIG.APP_STORE_URL;
    if (platform === "ios" || platform === "desktop") appstoreLink.classList.remove("hidden");
  }
}

// For states reached via a real email link (success/failure): try the deep
// link, and if the app doesn't take over the tab, redirect straight to the
// matching store - no extra tap required. The visible button stays as a
// manual retry, since a script-triggered custom-scheme navigation without a
// user gesture is silently blocked by some mobile browsers.
function wireOpenApp(suffix, deepLink, platform) {
  const button = document.getElementById(`open-app-${suffix}`);

  if (platform === "desktop") {
    if (button) button.classList.add("hidden");
    revealStoreLinks(suffix, platform);
    return;
  }

  const storeUrl = platform === "android" ? CONFIG.PLAY_STORE_URL : CONFIG.APP_STORE_URL;

  function attempt() {
    let appOpened = false;
    const onHide = () => { appOpened = true; };
    document.addEventListener("visibilitychange", onHide, { once: true });

    window.location.href = deepLink;

    setTimeout(() => {
      document.removeEventListener("visibilitychange", onHide);
      if (appOpened) return;
      revealStoreLinks(suffix, platform);
      window.location.href = storeUrl;
    }, 1500);
  }

  button.addEventListener("click", attempt);
  attempt(); // best-effort automatic attempt; the button remains as a manual fallback
}

// Performs the actual verification. This is deliberately NOT called on page
// load: {{ .TokenHash }} is delivered to us instead of {{ .ConfirmationURL }}
// precisely so that nothing is consumed by a mere GET. Email security scanners
// (Defender Safe Links, antivirus, link previewers) fetch - and sometimes even
// execute - the page, so the user gesture below is the entire defense. Never
// move this into render() or a load handler.
async function confirmEmail(params, platform) {
  const btn = document.getElementById("confirm-btn");
  btn.disabled = true;
  btn.textContent = "Verifying…";

  try {
    const res = await fetch(`${CONFIG.SUPABASE_URL}/auth/v1/verify`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: CONFIG.SUPABASE_ANON_KEY,
      },
      body: JSON.stringify({
        type: params.type || "signup",
        token_hash: params.token_hash,
      }),
    });

    const data = await res.json().catch(() => ({}));

    if (!res.ok) {
      // GoTrue reports an expired *or* already-consumed token as 401/403 with
      // an otp_expired-ish body; both mean "this link is spent", so fall back
      // to a message that covers either case rather than guessing.
      const code = data.error_code || data.error || "";
      throw new Error(
        ERROR_MESSAGES[code] ||
          (/expired/i.test(data.error_description || data.msg || code)
            ? ERROR_MESSAGES.otp_expired
            : ERROR_MESSAGES.token_used)
      );
    }

    showEmail("email-line-success", "email-value-success", data.user && data.user.email);
    showState("state-success");
    // Hand the freshly minted session to the app so the user lands signed in.
    wireOpenApp(
      "success",
      buildDeepLink({ access_token: data.access_token, refresh_token: data.refresh_token }),
      platform
    );
  } catch (err) {
    document.getElementById("failure-reason").textContent =
      err.message || "This link is invalid or has expired.";
    showState("state-failure");
    wireOpenApp("failure", CONFIG.APP_SCHEME, platform);
  }
}

function render() {
  const params = parseAuthParams();
  const platform = detectPlatform();

  if (params.error || params.error_code || params.error_description) {
    const reason = ERROR_MESSAGES[params.error_code] || params.error_description || "This link is invalid or has expired.";
    document.getElementById("failure-reason").textContent = reason;
    showEmail("email-line-failure", "email-value-failure", params.email);
    showState("state-failure");
    wireOpenApp("failure", CONFIG.APP_SCHEME, platform);
    return;
  }

  // Click-to-confirm: the mail now carries {{ .TokenHash }} pointing here, and
  // verification only happens once the user presses the button (see confirmEmail).
  if (params.token_hash) {
    showEmail("email-line-confirm", "email-value-confirm", params.email);
    showState("state-confirm");
    // once:true - the token is single-use, so a double-tap would fail the second call.
    document
      .getElementById("confirm-btn")
      .addEventListener("click", () => confirmEmail(params, platform), { once: true });
    return;
  }

  if (params.access_token || params.code) {
    // Forward the session tokens/code so the app can finish signing the user in.
    showEmail("email-line-success", "email-value-success", params.email);
    showState("state-success");
    wireOpenApp("success", buildDeepLink(params), platform);
    return;
  }

  // Bare visit, no verification in progress - show the matching store button(s)
  // directly rather than auto-redirecting away from what is effectively the homepage.
  showState("state-unknown");
  revealStoreLinks("unknown", platform);
}

render();
