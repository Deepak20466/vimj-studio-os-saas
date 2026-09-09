const base = {
  width: 22,
  height: 22,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.8,
  strokeLinecap: "round",
  strokeLinejoin: "round",
};

export const IconDashboard = (p) => (
  <svg {...base} {...p}>
    <rect x="3" y="3" width="7" height="9" rx="1.5" />
    <rect x="14" y="3" width="7" height="5" rx="1.5" />
    <rect x="14" y="12" width="7" height="9" rx="1.5" />
    <rect x="3" y="16" width="7" height="5" rx="1.5" />
  </svg>
);

export const IconStudents = (p) => (
  <svg {...base} {...p}>
    <circle cx="9" cy="8" r="3.2" />
    <path d="M2.8 20c0-3.4 2.7-6 6.2-6s6.2 2.6 6.2 6" />
    <circle cx="17.5" cy="8.6" r="2.4" />
    <path d="M15.3 12.9c2.7.2 4.9 2.5 4.9 5.4" />
  </svg>
);

export const IconCoaches = (p) => (
  <svg {...base} {...p}>
    <circle cx="12" cy="7.5" r="3.6" />
    <path d="M4.5 20.5c0-4.1 3.4-7.2 7.5-7.2s7.5 3.1 7.5 7.2" />
    <path d="M8.5 4.2a4.2 4.2 0 0 1 6.8 3.3" />
  </svg>
);

export const IconActivities = (p) => (
  <svg {...base} {...p}>
    <path d="M4 21V9l8-5 8 5v12" />
    <path d="M9 21v-6h6v6" />
  </svg>
);

export const IconAttendance = (p) => (
  <svg {...base} {...p}>
    <rect x="4" y="5" width="16" height="15" rx="2" />
    <path d="M8 3v4M16 3v4M4 10h16" />
    <path d="M9 14.5l2 2 4-4" />
  </svg>
);

export const IconLeave = (p) => (
  <svg {...base} {...p}>
    <rect x="3.5" y="5" width="17" height="15" rx="2" />
    <path d="M3.5 10h17M8 3v4M16 3v4" />
    <path d="M12 13.5c1.6-1.2 3.2-.6 3.2.9 0 1.7-3.2 3.6-3.2 3.6s-3.2-1.9-3.2-3.6c0-1.5 1.6-2.1 3.2-.9z" />
  </svg>
);

export const IconFees = (p) => (
  <svg {...base} {...p}>
    <circle cx="12" cy="12" r="8.6" />
    <path d="M14.8 9.2a3 3 0 0 0-2.8-1.6c-1.8 0-3.2 1.1-3.2 2.5s1.4 2 3.2 2.4c1.8.4 3.2 1 3.2 2.4s-1.4 2.5-3.2 2.5a3 3 0 0 1-2.9-1.7" />
    <path d="M12 6.4v1.2M12 16.4v1.2" />
  </svg>
);

export const IconReports = (p) => (
  <svg {...base} {...p}>
    <path d="M5 3.5h9l5 5V19a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 19V5A1.5 1.5 0 0 1 5.5 3.5z" />
    <path d="M14 3.5V9h5" />
    <path d="M8 13.5l2 2 5-5" />
  </svg>
);

export const IconClasses = (p) => (
  <svg {...base} {...p}>
    <rect x="3" y="4.5" width="18" height="14" rx="2" />
    <path d="M3 9h18" />
    <path d="M8 13.5h3M8 16h5" />
  </svg>
);

export const IconSalary = (p) => (
  <svg {...base} {...p}>
    <rect x="2.5" y="6" width="19" height="12.5" rx="2" />
    <circle cx="12" cy="12.2" r="2.6" />
    <path d="M6 6v-.5A2 2 0 0 1 8 3.5h8a2 2 0 0 1 2 2V6" />
  </svg>
);

export const IconAbout = (p) => (
  <svg {...base} {...p}>
    <circle cx="12" cy="12" r="8.6" />
    <path d="M12 11v5.2" />
    <circle cx="12" cy="7.8" r="0.15" fill="currentColor" stroke="currentColor" strokeWidth="2.2" />
  </svg>
);

export const IconMore = (p) => (
  <svg {...base} {...p}>
    <circle cx="5" cy="12" r="1.6" fill="currentColor" stroke="none" />
    <circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none" />
    <circle cx="19" cy="12" r="1.6" fill="currentColor" stroke="none" />
  </svg>
);

export const IconLogout = (p) => (
  <svg {...base} {...p}>
    <path d="M9 20H5.5A1.5 1.5 0 0 1 4 18.5v-13A1.5 1.5 0 0 1 5.5 4H9" />
    <path d="M16 16l4-4-4-4" />
    <path d="M20 12H9" />
  </svg>
);

export const IconClose = (p) => (
  <svg {...base} {...p}>
    <path d="M6 6l12 12M18 6L6 18" />
  </svg>
);

export const IconChat = (p) => (
  <svg {...base} {...p}>
    <path d="M4 5.5A2.5 2.5 0 0 1 6.5 3h11A2.5 2.5 0 0 1 20 5.5v8A2.5 2.5 0 0 1 17.5 16H9l-4.5 4v-4H6.5A2.5 2.5 0 0 1 4 13.5v-8z" />
    <path d="M8 8.5h8M8 12h5" />
  </svg>
);

export const IconBell = (p) => (
  <svg {...base} {...p}>
    <path d="M6 9.5a6 6 0 0 1 12 0c0 4 1.5 5.5 1.5 5.5h-15S6 13.5 6 9.5z" />
    <path d="M10.3 19a1.9 1.9 0 0 0 3.4 0" />
  </svg>
);

export const IconSun = (p) => (
  <svg {...base} {...p}>
    <circle cx="12" cy="12" r="4.5" />
    <path d="M12 2.5v2.5M12 19v2.5M4.6 4.6l1.8 1.8M17.6 17.6l1.8 1.8M2.5 12H5M19 12h2.5M4.6 19.4l1.8-1.8M17.6 6.4l1.8-1.8" />
  </svg>
);

export const IconMoon = (p) => (
  <svg {...base} {...p}>
    <path d="M20 14.5A8.5 8.5 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z" />
  </svg>
);

export const IconSwap = (p) => (
  <svg {...base} {...p}>
    <path d="M4 8h13M13 4l4 4-4 4" />
    <path d="M20 16H7M11 12l-4 4 4 4" />
  </svg>
);

export const IconSettings = (p) => (
  <svg {...base} {...p}>
    <circle cx="12" cy="12" r="3" />
    <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
  </svg>
);

export const ICONS_BY_KEY = {
  dashboard: IconDashboard,
  students: IconStudents,
  coaches: IconCoaches,
  activities: IconActivities,
  attendance: IconAttendance,
  leave: IconLeave,
  fees: IconFees,
  reports: IconReports,
  classes: IconClasses,
  salary: IconSalary,
  about: IconAbout,
  chat: IconChat,
  settings: IconSettings,
  swap: IconSwap,
};
