// Clipboard with a fallback for WebViews that deny navigator.clipboard outside a user gesture.
export async function writeClipboard(text) {
  if (!text) return false;
  try { await navigator.clipboard.writeText(text); return true; } catch { /* fall through */ }
  try {
    const area = document.createElement('textarea');
    area.value = text; area.setAttribute('readonly', ''); area.style.position = 'fixed'; area.style.opacity = '0';
    document.body.append(area); area.select();
    const ok = document.execCommand('copy');
    area.remove();
    return ok;
  } catch { return false; }
}
