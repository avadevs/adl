# Mouse Cursor Conventions

A guide to standard mouse cursors and their meaning within our UI library. Using cursors consistently is crucial for creating an intuitive and predictable user experience.

## The Principle of Affordance

Mouse cursors provide an *affordance*—a visual clue about how you can interact with a UI element *before* you click it. The shape of the cursor should immediately inform the user what kind of interaction is possible.

---

## Implemented Cursors

These are the cursors currently in use in this application.

### 1. Default Arrow (`.default`)
This is the neutral, all-purpose cursor. It should be visible most of the time.

-   **When to use:**
    -   Hovering over non-interactive elements like backgrounds, labels, or disabled components.
    -   Interacting with elements that require direct manipulation, such as dragging a scrollbar's thumb.
-   **Example:** The background of a window, the track of a scrollbar.

### 2. Pointing Hand (`.pointing_hand`)
This cursor signals that an element is clickable and will trigger a discrete **action** or **navigation**. It’s the universal symbol for "you can click this."

-   **When to use:**
    -   **Buttons:** Any element that triggers a command (e.g., "Attach", "Save").
    -   **Links:** Elements that navigate to another screen or view.
    -   **Clickable List/Table Items:** When an entire row or item can be clicked to select it or perform an action.
-   **Example:** The "Attach" button, an item in the process list.

### 3. I-Beam (`.ibeam`)
This cursor indicates that the underlying content is text that can be selected or edited.

-   **When to use:**
    -   Hovering over a textbox or any text input field.
    -   Hovering over user-selectable static text.
-   **Example:** The process filter textbox.

### 4. Not Allowed (`.not_allowed`)
This cursor will provide immediate feedback that a requested action is currently disabled or forbidden.

-   **When to use:**
    -   Hovering over a disabled button.
    -   Attempting to drag an element to an invalid drop target.
-   **Example:** Hovering the "Attach" button when no process is selected.

---

## Future Cursors

As our UI library evolves, we will adopt other standard cursors for more complex interactions.

### 5. Grab / Grabbing (`.grab` / `.grabbing`)
This cursor will indicate that an element can be physically moved.

-   **When to use:**
    -   `.grab`: When hovering over a draggable element (e.g., a movable panel, a reorderable list item).
    -   `.grabbing`: While the user is actively dragging that element.
-   **Example:** Dragging UI panels to customize the layout.

### 6. Resize Cursors (`.ns_resize`, `.ew_resize`)
These double-ended arrow cursors indicate that a container's edge can be dragged to resize it.

-   **When to use:**
    -   Hovering over the border between two resizable panels (e.g., a sidebar and a main content area).
-   **Example:** A resizable log panel at the bottom of the screen.

### 7. Crosshair (`.crosshair`)
This cursor is used for precise, two-dimensional selection.

-   **When to use:**
    -   Selecting a region of memory in a hex view.
    -   Tools that require precise pixel selection (e.g., a screen color picker).
-   **Example:** A future memory-scanning tool that allows selecting a block of memory visually.
