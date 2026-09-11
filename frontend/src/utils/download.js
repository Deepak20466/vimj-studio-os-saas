export function downloadBlob(data, filename) {
  const url = window.URL.createObjectURL(new Blob([data], { type: "application/pdf" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(url);
}

// A failed axios request made with `responseType: "blob"` still gets its error
// body decoded as a Blob (not JSON), so `err.response.data.detail` is always
// undefined and every failure reads as a generic fallback message — hiding the
// backend's actual reason (e.g. "not found" vs. "must be approved first").
// This reads the blob's text back out as JSON so the real detail can be shown.
export async function blobErrorDetail(err) {
  try {
    const blob = err.response?.data;
    if (!(blob instanceof Blob)) return null;
    const text = await blob.text();
    const data = JSON.parse(text);
    return typeof data.detail === "string" ? data.detail : null;
  } catch {
    return null;
  }
}
