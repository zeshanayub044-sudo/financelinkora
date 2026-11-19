import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { WorkspaceUnavailable } from "./workspace-unavailable";

describe("workspace unavailable state", () => {
  it("explains that a membership read failure did not create an organization and offers retry", () => {
    render(<WorkspaceUnavailable />);
    expect(screen.getByRole("alert")).toHaveTextContent("No organization was created");
    expect(screen.getByRole("button", { name: "Retry" })).toBeInTheDocument();
  });

  it("retries the current route", () => {
    const retry = vi.fn();
    render(<WorkspaceUnavailable onRetry={retry} />);
    fireEvent.click(screen.getByRole("button", { name: "Retry" }));
    expect(retry).toHaveBeenCalledOnce();
  });
});
