---
name: ui-component-dev
description: Guide for creating UI components in ADL, enforcing separation between primitives and themed components.
---

# UI Component Development (ADL)

This skill guides you through creating new UI components for the ADL library, enforcing a strict separation between logic (Primitives) and theming (Components).

## Workflow
1.  **Check Primitives**: Look in `src/ui/primitives/`. Is there a low-level primitive that handles the core logic (input, focus, layout)?
2.  **Create Primitive** (if missing): Create a pure logic widget in `src/ui/primitives/`.
3.  **Create Component**: Create the themed wrapper in `src/ui/components/` that consumes the primitive.

---

## 1. Primitives (`src/ui/primitives/`)
Primitives handle **logic, input, and structural layout**. They **never** access `ctx.theme`. All visual properties must be passed via config.

### Pattern
-   **Config Struct**: Plain Old Data (POD) for every possible visual property (colors, padding, sizing).
-   **Return Value**: Interaction state (`clicked`, `hovered`, `active`).
-   **Logic**: Handles `ctx.input`, `ctx.registerFocusable`, `ctx.active_id`.

```zig
// src/ui/primitives/my_widget.zig

pub const Config = struct {
    id: cl.ElementId,
    background_color: cl.Color, // Explicit color, NOT from theme
    border_width: f32,
    // ...
};

pub const State = struct {
    hovered: bool,
    clicked: bool,
};

pub fn render(ctx: *UIContext, config: Config) State {
    // 1. Handle Logic
    const hovered = cl.pointerOver(config.id);
    // ... handle input, focus ...

    // 2. Render Layout (using config colors)
    cl.UI()(.{
        .id = config.id,
        .background_color = config.background_color,
        // ...
    })({});

    return .{ .hovered = hovered, .clicked = clicked };
}
```

---

## 2. Components (`src/ui/components/`)
Components handle **theming and high-level API**. They map user intention (Variants) to concrete values using `ctx.theme`.

### Pattern
-   **Options Struct**: High-level settings (text, variant, disabled state).
-   **Logic**:
    1.  Determine context (is it hovered? active?).
    2.  Resolve colors from `ctx.theme` based on state & variant.
    3.  Call the Primitive.

```zig
// src/ui/components/my_widget.zig
const Primitive = @import("../primitives/my_widget.zig");

pub const Variant = enum { primary, secondary };

pub const Options = struct {
    text: []const u8,
    variant: Variant = .primary,
};

pub fn render(id_str: []const u8, opts: Options) !bool {
    const ctx = try UIContext.getCurrent();
    const id = cl.ElementId.ID(id_str);

    // 1. Resolve Styling
    const theme = ctx.theme;
    const bg_color = switch (opts.variant) {
        .primary => theme.color_primary,
        .secondary => theme.color_secondary,
    };

    // 2. Configure Primitive
    const config = Primitive.Config{
        .id = id,
        .background_color = bg_color, // Pass resolved color
        .border_width = 2.0,
    };

    // 3. Render Primitive
    const state = Primitive.render(ctx, config);
    
    return state.clicked;
}
```

---

## 3. Checklist
1.  [ ] **Primitive**: Does it take raw `cl.Color`? (Yes = Good). Does it import `theme`? (Yes = **BAD**).
2.  [ ] **Component**: Does it contain complex input logic? (Yes = **BAD** -> Move to Primitive).
3.  [ ] **State**: If stateful, does the Primitive use `ctx.getWidgetState`?
4.  [ ] **Exports**: Export component in `src/ui/ui.zig`.
