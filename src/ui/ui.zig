//! # UI System
//!
//! A high-performance, immediate-mode UI library built on top of Clay.
//!
//! ## State Management Pattern
//! This library strictly separates **Data** from **View State**.
//! - **Data** (strings, lists, business logic) is owned by you/your application.
//! - **View State** (cursors, scroll offsets, hover states) is owned by the UI component structs.
//!
//! Most View States are POD (Plain Old Data) and do not require initialization.
//! You simply declare them in your struct and pass a pointer to the UI function.
//!
//! Example:
//! ```zig
//! // Data
//! var username = std.ArrayList(u8).init(allocator);
//! // View State
//! var username_state = ui.textbox.State{};
//!
//! // Render
//! ui.textbox(id, &username_state, &username, .{ .placeholder = "Username" });
//! ```
//!
//! ## Theming
//! The library uses a global theme by default, but you can override specific properties
//! for any component using the `theme_overrides` option.

const std = @import("std");
const cl = @import("zclay");

pub const context = @import("core/context.zig");
pub const input = @import("core/input.zig");
pub const theme = @import("core/theme.zig");
pub const types = @import("core/types.zig");

pub const useScrollContainer = @import("hooks/useScrollContainer.zig");

// Internal imports
const button_mod = @import("elements/button.zig");
const textbox_mod = @import("elements/textbox.zig");
const scrollbar_mod = @import("elements/scrollbar.zig");

const scroll_list_mod = @import("containers/scroll_list.zig");
const scroll_table_mod = @import("containers/scroll_table.zig");
const scroll_area_mod = @import("containers/scroll_area.zig");

// Public exports
pub const button = button_mod;
pub const textbox = textbox_mod;
pub const scrollbar = scrollbar_mod;
pub const scroll_list = scroll_list_mod;
pub const scroll_table = scroll_table_mod;
pub const scroll_area = scroll_area_mod;

/// The main entry point for building UIs.
/// Initialize this struct with a pointer to your UIContext at the start of your render pass.
pub const UI = struct {
    ctx: *context.UIContext,

    pub fn init(ctx: *context.UIContext) UI {
        return .{ .ctx = ctx };
    }

    /// Renders a button.
    pub fn button(self: UI, id: cl.ElementId, options: button_mod.Options) bool {
        return button_mod.render(self.ctx, id, options);
    }

    /// Renders a textbox.
    /// `state`: Interaction state (cursor pos, etc). POD.
    /// `text`: The actual text data (owned by you).
    pub fn textbox(self: UI, id: cl.ElementId, state: *textbox_mod.State, text: *std.ArrayList(u8), options: textbox_mod.Options) void {
        textbox_mod.render(self.ctx, id, state, text, options);
    }

    /// Renders a generic scrollable area.
    /// `content_fn`: A function or lambda that renders the content inside the scroll area.
    pub fn scrollArea(self: UI, id: cl.ElementId, state: *scroll_area_mod.State, options: scroll_area_mod.Options, content_fn: anytype) void {
        scroll_area_mod.render(self.ctx, id, state, options, content_fn);
    }

    // Expose virtualized list helper
    pub fn scrollList(_: UI, comptime Item: type) type {
        return scroll_list_mod.ScrollList(Item);
    }
};
