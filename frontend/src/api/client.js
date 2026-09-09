import axios from "axios";

// Local dev: relative "/api", proxied to localhost:8000 by vite.config.js.
// Production (e.g. Vercel): set VITE_API_BASE_URL to the deployed backend's
// root URL (no trailing slash, no /api suffix — the backend mounts routes
// directly, the /api prefix only exists for the dev proxy rewrite).
const client = axios.create({
  baseURL: import.meta.env.VITE_API_BASE_URL || "/api",
});

client.interceptors.request.use((config) => {
  const token = localStorage.getItem("access_token");
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

let isRefreshing = false;
let queue = [];

function processQueue(error, token = null) {
  queue.forEach((p) => (error ? p.reject(error) : p.resolve(token)));
  queue = [];
}

client.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;
    if (error.response?.status === 401 && !originalRequest._retry && !originalRequest.url.includes("/auth/login")) {
      if (isRefreshing) {
        return new Promise((resolve, reject) => {
          queue.push({ resolve, reject });
        }).then((token) => {
          originalRequest.headers.Authorization = `Bearer ${token}`;
          return client(originalRequest);
        });
      }

      originalRequest._retry = true;
      isRefreshing = true;
      const refreshToken = localStorage.getItem("refresh_token");

      try {
        // Deliberately a bare `axios` call (not `client`) so a failed refresh doesn't
        // re-enter this same response interceptor and deadlock against the `isRefreshing`
        // guard below. It must still resolve against `client`'s own baseURL, though —
        // the old code hardcoded "/api/auth/refresh", a relative path that only resolves
        // correctly in local dev (where Vite's proxy rewrites "/api" to localhost:8000).
        // In production there is no such proxy, so that request hit the frontend's own
        // domain instead of the backend, refresh always failed, and every user was
        // forced back to the login screen the moment their 30-minute access token expired.
        const { data } = await axios.post(`${client.defaults.baseURL}/auth/refresh`, { refresh_token: refreshToken });
        localStorage.setItem("access_token", data.access_token);
        localStorage.setItem("refresh_token", data.refresh_token);
        processQueue(null, data.access_token);
        originalRequest.headers.Authorization = `Bearer ${data.access_token}`;
        return client(originalRequest);
      } catch (refreshError) {
        processQueue(refreshError, null);
        localStorage.clear();
        window.location.href = "/login";
        return Promise.reject(refreshError);
      } finally {
        isRefreshing = false;
      }
    }
    return Promise.reject(error);
  }
);

export default client;
