import { Outlet } from "@tanstack/react-router";
import { Component, type ReactNode } from "react";

class ShellCatch extends Component<{ children: ReactNode }, { error: boolean }> {
  state = { error: false };
  static getDerivedStateFromError() {
    return { error: true };
  }
  render() {
    if (this.state.error) {
      return (
        <div className="flex min-h-dvh flex-col items-center justify-center gap-4 bg-bg px-6 text-fg">
          <p className="text-center text-sm">Algo deu errado.</p>
          <a href="/" className="rounded-md bg-accent px-4 py-2 text-sm font-medium text-accent-fg">
            Katecheo
          </a>
        </div>
      );
    }
    return this.props.children;
  }
}

/** Marketing-site shell: outlet only (product UI lives in the iOS app). */
export function AppShell() {
  return (
    <ShellCatch>
      <Outlet />
    </ShellCatch>
  );
}
