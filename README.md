# ADL - Ava(s) development library
This library provides a lot of different basic components that somebody might need to use to create a multithreaded UI application.
I tried to make every component as generic as possible. This means the library is suited for most GUI applications you might encounter.

A lot of the components are inspired by web application development. We have components like stores or a router (called navigator here) that you might know from different web frameworks. But the components and especially the UI differs from the implementation because the UI is a intermediate UI. This means the UI will completly rerender every frame. While this sounds very inefficient it is actually very fast and prevents a lot of pitfalls retained UIs come with.
I did not create a whole UI system. For the UI we use the excellent library [Clay UI](https://github.com/nicbarker/clay) and the following [zig bindings](https://github.com/johan0A/clay-zig-bindings).

## Principles

1.  **Fast:** Performance is paramount. You chose a compiled language for a reason, and this library honors that choice by being fast and efficient. While we prioritize simplicity for ease of use, we always provide configuration options to unlock maximum performance when you need it.

2.  **Simple:** The library is designed to be developer-friendly and easy to use. It provides sensible defaults to get you started quickly, because your time is better spent building features than digging through documentation. Our goal is to make each component intuitive and straightforward.

3.  **Explicit:** In the spirit of Zig, this library avoids hidden control flow and magic. When a component requires an allocator, for example, you are put in control of its memory management, ensuring there are no surprises in the execution flow.

4.  **Flexible Memory Management:** You have the freedom to provide a custom allocator for any component. For common patterns, such as short-lived string allocations within a single frame, we also provide convenient, optimized solutions like a built-in FrameAllocator.

## UI Design Philosophy

The library is designed with a clear separation of concerns, following a pattern inspired by modern web frameworks like React.

1.  **Logic vs. Presentation:** Complex behavior (like scrolling and virtualization) is encapsulated in headless "hooks", while components focus on rendering.
2.  **Composition over Configuration:** Complex components are built by composing simpler elements and logic hooks, rather than through monolithic configuration.
3.  **State Management:** Components follow a predictable state model, where persistent `State` is owned by the user of the component, and per-frame configuration is passed via an `Options` struct.

## Directory Structure

The library is organized by architectural role to make it easy to understand and navigate.

-   `root.zig` The main entry point for the library. Import this file to get acces to all components and types of this library.

-   `ui.zig`: The main entry point for the UI components of this library.

-   `ui/core/`: Contains the foundational, non-visual infrastructure. This includes the global `UIContext`, the `InputManager`, and the `THEME` definition.

-   `ui/hooks/`: Contains reusable, headless logic functions. These are the "brains" behind complex components. They manage state and behavior but do not render any UI themselves.
    -   `useScrollContainer.zig`: Encapsulates all logic for scrolling, virtualization, and input handling for a scrollable area.

-   `ui/elements/`: Contains the basic, "dumb" presentational components. These are the fundamental visual building blocks of the UI.
    -   `button.zig`
    -   `textbox.zig`
    -   `scrollbar.zig`

-   `ui/containers/`: Contains complex, "smart" components. These are orchestrators that compose hooks and elements to create feature-rich UI widgets for displaying data.
    -   `scroll_list.zig`
    -   `scroll_table.zig`

-   `jobs.zig` A job scheduling solution built on top of [zjobs](https://github.com/zig-gamedev/zjobs) that allows us to pass the result of the jobs back to callback functions.

-   `navigator.zig` A navigator / router that allows screen management.

-   `store.zig` A component that allows you to store a piece of memory and is accessable by multiple threads (uses RwLock to synchronize).

## Usage

To use the library, a developer would typically:

TBD.

## Road to 1.0
1. [ ] Built more applications with this library to make it more battle tested.
2. [ ] Ditch the raylib dependency. I want this library to enable you to use the renderer and input system of your choice.
3. [ ] Abstract `input.zig` further so it does not rely directly on raylib. Instead we should do it like clay where each developer can bring their renderer (for us: input manager) of choice.
4. [ ] Use the clay terminal renderer for tests.
5. [ ] ...