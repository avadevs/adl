//! # UI System
//!
//! A high-performance, immediate-mode UI library built on top of Clay.
//!
//! ## State Management Pattern
//! This library uses an **Implicit Context** and **Scoped Registry**.
//! - **Data** (strings, lists) is owned by you.
//! - **View State** (cursors, scroll) is managed automatically by the system.
//!
//! Usage:
//! ```zig
//! // 1. Setup (once per frame)
//! ui_ctx.makeCurrent();
//!
//! // 2. Render
//! ui.textbox("username", &username, .{ .placeholder = "Username" });
//! ```

const std = @import("std");
const cl = @import("zclay");

pub const context = @import("core/context.zig");
pub const element = @import("core/element.zig");
pub const input = @import("core/input.zig");
pub const theme = @import("core/theme.zig");
pub const types = @import("core/types.zig");

pub const useScrollContainer = @import("hooks/useScrollContainer.zig");

// Internal imports
const button_mod = @import("components/button.zig");
const textbox_mod = @import("components/textbox.zig");
const scrollbar_mod = @import("elements/scrollbar.zig");

const scroll_list_mod = @import("containers/scroll_list.zig");
const scroll_table_mod = @import("containers/scroll_table.zig");
const scroll_area_mod = @import("containers/scroll_area.zig");

// Public exports
pub const button_elem = button_mod;
pub const textbox_elem = textbox_mod;
pub const scrollbar_elem = scrollbar_mod;
pub const scrollList = scroll_list_mod;
pub const scrollTable = scroll_table_mod;
pub const scroll_area_elem = scroll_area_mod;

// Types export
pub const TableColumn = scroll_table_mod.Column;

/// The simplified API surface.
/// Functions here automatically use the active UIContext.
pub const UI = struct {
    /// Renders a button.
    pub fn button(id_str: []const u8, options: button_mod.Options) !bool {
        const ctx = try context.UIContext.getCurrent();
        // Assume ID is stable for button functionality (interaction)
        const id = cl.ElementId.ID(id_str);
        return button_mod.render(ctx, id, options);
    }

    /// Renders a textbox.
    /// State is managed automatically.
    pub fn textbox(id_str: []const u8, text: *std.ArrayList(u8), options: textbox_mod.Options) !void {
        try textbox_mod.render(id_str, text, options);
    }

    /// Renders a generic scrollable area.
    pub fn scrollArea(id_str: []const u8, options: scroll_area_mod.Options, content_fn: anytype) !void {
        try scroll_area_mod.render(id_str, options, content_fn);
    }

    /// Begins a scroll list. Returns a ListWalker.
    /// Usage:
    /// const list = try ui.beginList("id", items.len, .{});
    /// var iter = list.iterator();
    /// while (iter.next()) |i| {
    ///     if (list.row(i)) { ... }
    ///     ui.text(items[i]);
    /// }
    /// ui.endList(list);
    pub fn beginList(id_str: []const u8, count: usize, options: scroll_list_mod.Options) !scroll_list_mod.ListWalker {
        return scroll_list_mod.begin(id_str, count, options);
    }

    pub fn endList(walker: scroll_list_mod.ListWalker) void {
        scroll_list_mod.end(walker);
    }

    /// Begins a scroll table. Returns a TableWalker.
    /// Usage:
    /// const table = try ui.beginTable("id", items.len, columns, .{});
    /// table.header();
    /// var iter = table.iterator();
    /// while (iter.next()) |i| {
    ///     _ = table.row(i);
    ///     table.textCell(items[i].name);
    ///     table.textCell(items[i].age);
    /// }
    /// ui.endTable(table);
    pub fn beginTable(id_str: []const u8, count: usize, columns: []const TableColumn, options: scroll_table_mod.Options) !scroll_table_mod.TableWalker {
        return scroll_table_mod.begin(id_str, count, columns, options);
    }

    pub fn endTable(walker: scroll_table_mod.TableWalker) void {
        scroll_table_mod.end(walker);
    }

    // Helper to get context if needed manually
    pub fn getContext() !*context.UIContext {
        return context.UIContext.getCurrent();
    }
};

// Top-level aliases for convenience
pub const button = UI.button;
pub const textbox = UI.textbox;
pub const scrollArea = UI.scrollArea;
pub const beginList = UI.beginList;
pub const endList = UI.endList;
pub const beginTable = UI.beginTable;
pub const endTable = UI.endTable;
pub const open = element.open;
pub const close = element.close;
