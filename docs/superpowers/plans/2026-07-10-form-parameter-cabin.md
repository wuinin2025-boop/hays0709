# Form Parameter Cabin Implementation Plan

> **For agentic workers:** Implement inline with test-first verification.

**Goal:** Replace mobile native selects with a branded, accessible parameter-cabin picker while preserving the existing form data flow.

**Architecture:** Keep the native select elements as the source of truth and hide them visually. Generate proxy buttons beside them, use one shared dialog to render options, then dispatch the native `change` event after confirmation so all existing date and city linkage logic remains intact.

**Tech Stack:** Static HTML, CSS, vanilla JavaScript, Node.js assertion tests, Playwright CLI.

## Global Constraints

- Preserve unrelated uncommitted changes in the HTML and existing tests.
- Do not alter answer formats, area data, report generation, or navigation flow.
- Support mobile bottom-sheet and desktop centered-dialog layouts.
- Avoid the browser or operating system native select UI.

---

### Task 1: Add regression coverage

**Files:**
- Create: `tests/form-parameter-cabin.test.mjs`

- [ ] Assert hidden native selects, proxy controls, dialog semantics, and picker functions.
- [ ] Run the test and confirm it fails before implementation.

### Task 2: Implement parameter cabin

**Files:**
- Modify: `瀚纳仕H5 demo-启动舱.html`

- [ ] Complete the parameter-cabin styling and responsive states.
- [ ] Add the shared dialog markup.
- [ ] Generate proxy buttons for all date and location selects.
- [ ] Render, select, confirm, cancel, focus, and scroll-lock behavior.
- [ ] Synchronize disabled states and labels after existing select updates.

### Task 3: Verify interaction and layout

**Files:**
- Test: `tests/form-parameter-cabin.test.mjs`
- Test: existing `tests/*.test.mjs`

- [ ] Run all Node assertion tests.
- [ ] Walk the complete form in a real mobile viewport.
- [ ] Check desktop and mobile screenshots for overflow and overlap.
- [ ] Confirm the next-step button enables after valid input.
