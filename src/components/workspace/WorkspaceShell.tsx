"use client";

import {
  Activity,
  Archive,
  Bell,
  Building2,
  CalendarDays,
  CalendarRange,
  ChevronLeft,
  CircleHelp,
  ClipboardList,
  CreditCard,
  FileText,
  FlaskConical,
  LayoutDashboard,
  Package,
  Printer,
  Search,
  Settings,
  Stethoscope,
  Users,
  Wallet,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState, useSyncExternalStore, type ReactNode } from "react";
import { signOut } from "@/app/actions/auth";
import { Logo } from "@/components/brand/Logo";

type WorkspaceShellProps = {
  children: ReactNode;
  labName: string;
  userName: string;
  roleLabel: string;
  grantedPages: string[];
};

const navigation = [
  { label: "Dashboard", page: "dashboard", href: "/lab", icon: LayoutDashboard },
  { label: "Test billing", page: "test_billing", href: "/lab/test-billing", icon: CreditCard },
  { label: "Tests", page: "tests", href: "/lab/tests", icon: FlaskConical },
  { label: "Departments", page: "departments", href: "/lab/departments", icon: ClipboardList },
  { label: "Appointments", page: "appointments", href: "/lab/appointments", icon: CalendarDays },
  { label: "Scheduling", page: "scheduling", href: "/lab/scheduling", icon: CalendarRange },
  { label: "Samples", page: "samples", href: "/lab/samples", icon: Activity },
  { label: "Patients", page: "patients", href: "/lab/patients", icon: Users },
  { label: "Reports", page: "reports", href: "/lab/reports", icon: FileText },
  { label: "Invoice history", page: "invoice_history", href: "/lab/invoice-history", icon: CreditCard },
  { label: "Referring doctors", page: "referring_doctors", href: "/lab/referring-doctors", icon: Stethoscope },
  { label: "Reagent stock", page: "reagent_stock", href: "/lab/reagent-stock", icon: Package },
  { label: "Expenses", page: "expenses", href: "/lab/expenses", icon: Wallet },
  { label: "Analytics", page: "analytics", href: "/lab/analytics", icon: Activity },
  { label: "Manage users", page: "manage_users", href: "/lab/manage-users", icon: Users },
  { label: "Print requests", page: "print_requests", href: "/lab/print-requests", icon: Printer },
  { label: "My print requests", page: "my_print_requests", href: "/lab/my-print-requests", icon: Printer },
  { label: "Settings", page: "settings", href: "/lab/settings", icon: Settings },
  { label: "Trash bin", page: "trash_bin", href: "/lab/trash-bin", icon: Archive },
  { label: "Help", page: "help", href: "/lab/help", icon: CircleHelp },
];

const mobileViewport = "(max-width: 760px)";

function subscribeToViewport(callback: () => void) {
  const mediaQuery = window.matchMedia(mobileViewport);
  mediaQuery.addEventListener("change", callback);
  return () => mediaQuery.removeEventListener("change", callback);
}

function getMobileViewport() {
  return window.matchMedia(mobileViewport).matches;
}

function subscribeToDate(callback: () => void) {
  const timer = window.setInterval(callback, 60_000);
  return () => window.clearInterval(timer);
}

function getDateSnapshot() {
  return new Date().toISOString().slice(0, 10);
}

export function WorkspaceShell({
  children,
  labName,
  userName,
  roleLabel,
  grantedPages,
}: WorkspaceShellProps) {
  const pathname = usePathname();
  const mobileViewportMatch = useSyncExternalStore(subscribeToViewport, getMobileViewport, () => false);
  const currentDate = useSyncExternalStore(subscribeToDate, getDateSnapshot, () => "");
  const [sidebarOverride, setSidebarOverride] = useState<boolean | null>(null);
  const [accountOpen, setAccountOpen] = useState(false);
  const [notificationsOpen, setNotificationsOpen] = useState(false);
  const collapsed = sidebarOverride ?? mobileViewportMatch;
  const initials = userName
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");

  useEffect(() => {
    const storedTheme = window.localStorage.getItem("labcore-theme");
    const useDarkTheme =
      storedTheme === "dark" ||
      (storedTheme === null &&
        window.matchMedia("(prefers-color-scheme: dark)").matches);
    const useLargeText = window.localStorage.getItem("labcore-large-text") === "true";
    document.documentElement.dataset.theme = useDarkTheme ? "dark" : "light";
    document.documentElement.classList.toggle("large-text", useLargeText);
  }, []);

  function toggleTheme() {
    const next = document.documentElement.dataset.theme !== "dark";
    document.documentElement.dataset.theme = next ? "dark" : "light";
    window.localStorage.setItem("labcore-theme", next ? "dark" : "light");
  }

  function toggleTextSize() {
    const next = !document.documentElement.classList.contains("large-text");
    document.documentElement.classList.toggle("large-text", next);
    window.localStorage.setItem("labcore-large-text", String(next));
  }

  const visibleNavigation = navigation.filter((item) => grantedPages.includes(item.page));
  const currentPage = navigation.find((item) => item.href === pathname);

  return (
    <div className="workspace">
      <aside className={`workspace-sidebar ${collapsed ? "is-collapsed" : "is-expanded"}`}>
        <Link className="workspace-brand" href="/lab" aria-label={`${labName} dashboard`}>
          {collapsed ? (
            <Logo className="workspace-brand-mark" />
          ) : (
            <Logo variant="horizontal" theme="dark" />
          )}
        </Link>
        <div className="workspace-nav-label">{!collapsed && "WORKSPACE"}</div>
        <nav aria-label="Laboratory workspace">
          {visibleNavigation.map(({ label, href, icon: Icon }) => (
            <Link
              key={href}
              href={href}
              title={collapsed ? label : undefined}
              aria-current={pathname === href ? "page" : undefined}
              className={`workspace-nav-link${pathname === href ? " is-active" : ""}`}
            >
              <Icon size={19} aria-hidden="true" />
              {!collapsed && <span>{label}</span>}
            </Link>
          ))}
        </nav>
        <div className="workspace-sidebar-footer">
          <Building2 size={16} aria-hidden="true" />
          {!collapsed && <span title={labName}>{labName}</span>}
        </div>
      </aside>

      <div className="workspace-main">
        <header className="workspace-header">
          <div className="workspace-header-lab">
            <Link className="workspace-header-logo" href="/lab" aria-label="LabCore dashboard">
              <Logo theme="light" className="workspace-header-mark" />
            </Link>
            <button
              type="button"
              className="workspace-icon-button workspace-collapse"
              onClick={() => setSidebarOverride(!collapsed)}
              aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
              title={collapsed ? "Expand sidebar" : "Collapse sidebar"}
            >
              <ChevronLeft className={collapsed ? "is-rotated" : ""} size={19} />
            </button>
            <div className="workspace-lab-name">
              <strong title={labName}>{labName}</strong>
              <span>Laboratory workspace</span>
            </div>
          </div>

          <div className="workspace-header-title">
            {currentPage ? <currentPage.icon size={18} /> : <LayoutDashboard size={18} />}
            <span>{currentPage?.label ?? "Dashboard"}</span>
          </div>

          <div className="workspace-header-actions">
            <span className="workspace-date">
              {currentDate
                ? new Intl.DateTimeFormat("en", {
                    weekday: "short",
                    day: "numeric",
                    month: "short",
                  }).format(new Date(`${currentDate}T12:00:00`))
                : ""}
            </span>
            <div className="workspace-popover">
              <button
                type="button"
                className="workspace-icon-button"
                aria-label="Notifications"
                aria-expanded={notificationsOpen}
                onClick={() => {
                  setNotificationsOpen((value) => !value);
                  setAccountOpen(false);
                }}
              >
                <Bell size={18} />
              </button>
              {notificationsOpen && (
                <div className="workspace-menu workspace-notifications">
                  <strong>Notifications</strong>
                  <p>Live alerts are not connected yet.</p>
                </div>
              )}
            </div>
            <div className="workspace-popover">
              <button
                type="button"
                className="workspace-avatar"
                aria-label="Account menu"
                aria-expanded={accountOpen}
                onClick={() => {
                  setAccountOpen((value) => !value);
                  setNotificationsOpen(false);
                }}
              >
                {initials || "LS"}
              </button>
              {accountOpen && (
                <div className="workspace-menu workspace-account-menu">
                  <div className="workspace-account">
                    <strong>{userName}</strong>
                    <span>{roleLabel}</span>
                  </div>
                  <button type="button" className="workspace-setting" onClick={toggleTheme}>
                    <span>Dark theme</span>
                    <span className="workspace-switch workspace-theme-switch" aria-hidden="true" />
                  </button>
                  <button type="button" className="workspace-setting" onClick={toggleTextSize}>
                    <span>Large text</span>
                    <span className="workspace-switch workspace-text-switch" aria-hidden="true">
                      <span>A</span><span>A+</span>
                    </span>
                  </button>
                  <form action={signOut}>
                    <button className="workspace-sign-out" type="submit">Sign out</button>
                  </form>
                </div>
              )}
            </div>
            <Link className="workspace-search-link" href="/lab/patients#patient-search" aria-label="Search patients">
              <Search size={17} />
            </Link>
          </div>
        </header>
        <main className="workspace-content">{children}</main>
      </div>
    </div>
  );
}
