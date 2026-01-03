# ADL - Ava(s) development library
This library provides a lot of different basic components that somebody might need to use to create a multithreaded UI application.
I tried to make every component as generic as possible. This means the library is suited for most GUI applications you might encounter.

A lot of the components are inspired by web application development. We have components like stores or a router that you might know from different web frameworks. The components and especially the UI differs from typical web development pracitces because this library uses an itermediate UI, this means the UI will completly rerender every frame. While this sounds very inefficient it is actually very fast and prevents a lot of pitfalls retained UIs come with.
I did not create a whole UI system. For the UI we use the excellent library [Clay UI](https://github.com/nicbarker/clay) and the following [zig bindings](https://github.com/johan0A/clay-zig-bindings).

## Principles
1.  **Fast:** Performance is paramount. You chose a compiled language for a reason, and this library honors that choice by being fast and efficient. While we prioritize simplicity for ease of use, we always provide configuration options to unlock maximum performance when you need it.

2.  **Simple:** The library is designed to be developer-friendly and easy to use. It provides sensible defaults to get you started quickly, because your time is better spent building features than digging through documentation. Our goal is to make each component intuitive and straightforward. We try to minimize the usage of dependencies. If we can implement a feature in a straightforward and simple way that archieves 95% of what we want then use this instead of complex solutions.  

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

-   `jobs.zig` A job system that allows you to schedule jobs on threads for concurrent execution. Events are used to communicate changes back to registered listeners.

-   `store.zig` A component that allows you to store a piece of memory and is accessable by multiple threads (uses RwLock to synchronize).

-   `router.zig` A router that simplifies screen management. It is url based like in web development.


## Usage

To use the library, a developer would typically:

1. **Import the library**: Import modules through `root.zig` to access all components
2. **Initialize systems**: Set up Jobs, Router, Store, and UI systems as needed
3. **Create application state**: Use Store for thread-safe state management
4. **Define routes**: Set up URL patterns and screen handlers with the Router
5. **Schedule background work**: Use the Jobs system for async operations
6. **Build UI**: Create interfaces using immediate mode UI components

### Getting Started

See `examples/basic_example.zig` for a comprehensive demonstration of how to use all the library modules together in a real application. This example shows:

- Setting up a multi-threaded application with background job processing
- Creating multiple screens with navigation using the Router
- Managing shared state with the Store system
- Building interactive UI components
- Integrating all systems into a cohesive application

To run the example:
```bash
zig build run_example
```
