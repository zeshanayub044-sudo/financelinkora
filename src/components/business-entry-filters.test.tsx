import {afterEach,describe,expect,it} from "vitest";
import {cleanup,render,screen} from "@testing-library/react";
import {BusinessEntryFilters} from "./business-entry-filters";

afterEach(cleanup);
describe("income and expense history filters",()=>{
 it("submits date and category filters as a navigable GET form",()=>{
  render(<BusinessEntryFilters action="/expenses" from="2026-01-01" to="2026-01-31" category="rent" categories={[{id:"rent",code:"5400",name:"Office rent",is_active:true},{id:"old",code:"5450",name:"Old rent",is_active:false}]}/>);
  const form=screen.getByRole("button",{name:"Apply filters"}).closest("form");
  expect(form).toHaveAttribute("action","/expenses");
  expect(form).toHaveAttribute("method","get");
  expect(screen.getByLabelText("From")).toHaveValue("2026-01-01");
  expect(screen.getByLabelText("To")).toHaveValue("2026-01-31");
  expect(screen.getByLabelText("Category")).toHaveValue("rent");
  expect(screen.getByRole("option",{name:"5450 · Old rent · Inactive"})).toBeInTheDocument();
 });
});
