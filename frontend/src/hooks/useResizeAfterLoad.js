import { useEffect } from "react";

// Recharts' ResponsiveContainer measures its parent via ResizeObserver on mount.
// Inside a CSS grid, that first measurement can land before the grid tracks are
// finalized (worse under StrictMode's double-effect mount in dev), leaving charts
// squished until something else forces a reflow. Nudge a resize once data is in.
export default function useResizeAfterLoad(ready) {
  useEffect(() => {
    if (!ready) return;
    const t = setTimeout(() => window.dispatchEvent(new Event("resize")), 60);
    return () => clearTimeout(t);
  }, [ready]);
}
